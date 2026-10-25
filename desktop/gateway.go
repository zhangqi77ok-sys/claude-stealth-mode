package main

import (
	"bufio"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// ConnectionLog 代表一条连接的流入流出审计记录
type ConnectionLog struct {
	ID        string    `json:"id"`
	Time      string    `json:"time"`
	Host      string    `json:"host"`
	Method    string    `json:"method"`
	BytesIn   uint64    `json:"bytesIn"`
	BytesOut  uint64    `json:"bytesOut"`
	Status    string    `json:"status"` // "Active", "Closed", "Blocked"
	Duration  string    `json:"duration"`
	IsClaude  bool      `json:"isClaude"`
	StartTime time.Time `json:"-"`
}

// RiskAlert 代表捕获到的 Cloudflare 挑战或封锁告警
type RiskAlert struct {
	Time   string `json:"time"`
	Host   string `json:"host"`
	Reason string `json:"reason"`
	Status int    `json:"status"`
}

func isClaudeHost(host string) bool {
	h := strings.ToLower(host)
	return strings.Contains(h, "claude.ai") ||
		strings.Contains(h, "anthropic.com") ||
		strings.Contains(h, "challenges.cloudflare.com")
}

// Gateway 统一安全网关与流量监控器
type Gateway struct {
	listenAddr    string
	upstreamProxy string
	server        *http.Server
	listener      net.Listener

	totalIn   uint64
	totalOut  uint64
	claudeIn  uint64
	claudeOut uint64
	speedIn   uint64
	speedOut  uint64

	lastIn     uint64
	lastOut    uint64
	activeConn int32

	logsLock  sync.RWMutex
	logs      []*ConnectionLog
	riskAlert *RiskAlert

	isRunning bool
	stopChan  chan struct{}
}

func NewGateway(listenAddr, upstreamProxy string) *Gateway {
	return &Gateway{
		listenAddr:    listenAddr,
		upstreamProxy: upstreamProxy,
		logs:          make([]*ConnectionLog, 0, 100),
		stopChan:      make(chan struct{}),
	}
}

func (g *Gateway) Start() error {
	l, err := net.Listen("tcp", g.listenAddr)
	if err != nil {
		return err
	}
	g.listener = l
	g.isRunning = true

	g.server = &http.Server{
		Handler: http.HandlerFunc(g.handleHTTP),
	}

	go func() {
		_ = g.server.Serve(l)
	}()

	// 启动后台速率计算定时器
	go g.speedCalculator()

	return nil
}

func (g *Gateway) Stop() error {
	if !g.isRunning {
		return nil
	}
	g.isRunning = false
	close(g.stopChan)
	if g.server != nil {
		return g.server.Close()
	}
	return nil
}

func (g *Gateway) ClearLogs() {
	g.logsLock.Lock()
	defer g.logsLock.Unlock()
	g.logs = make([]*ConnectionLog, 0, 100)
}

func (g *Gateway) triggerRiskAlert(host string, status int, reason string) {
	g.logsLock.Lock()
	defer g.logsLock.Unlock()
	g.riskAlert = &RiskAlert{
		Time:   time.Now().Format("15:04:05"),
		Host:   host,
		Status: status,
		Reason: reason,
	}
}

func (g *Gateway) DismissRiskAlert() {
	g.logsLock.Lock()
	defer g.logsLock.Unlock()
	g.riskAlert = nil
}

func (g *Gateway) SetUpstream(proxyURL string) {
	g.logsLock.Lock()
	defer g.logsLock.Unlock()
	g.upstreamProxy = proxyURL
}

func (g *Gateway) GetUpstream() string {
	g.logsLock.RLock()
	defer g.logsLock.RUnlock()
	return g.upstreamProxy
}

func (g *Gateway) speedCalculator() {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-g.stopChan:
			return
		case <-ticker.C:
			curIn := atomic.LoadUint64(&g.totalIn)
			curOut := atomic.LoadUint64(&g.totalOut)

			// 每秒计算速率 (Bytes/s)
			atomic.StoreUint64(&g.speedIn, curIn-g.lastIn)
			atomic.StoreUint64(&g.speedOut, curOut-g.lastOut)

			g.lastIn = curIn
			g.lastOut = curOut
		}
	}
}

func (g *Gateway) handleHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		g.handleTunnel(w, r)
	} else {
		g.handleForward(w, r)
	}
}

// handleTunnel 处理 HTTPS CONNECT 隧道
func (g *Gateway) handleTunnel(w http.ResponseWriter, r *http.Request) {
	atomic.AddInt32(&g.activeConn, 1)
	defer atomic.AddInt32(&g.activeConn, -1)

	isClaude := isClaudeHost(r.Host)
	startTime := time.Now()
	connLog := &ConnectionLog{
		ID:        fmt.Sprintf("%d", startTime.UnixNano()),
		Time:      startTime.Format("15:04:05"),
		Host:      r.Host,
		Method:    "CONNECT",
		Status:    "Active",
		IsClaude:  isClaude,
		StartTime: startTime,
	}
	g.addLog(connLog)

	var upstreamConn net.Conn
	var err error

	upstreamProxy := g.GetUpstream()
	// 如果配置了上游代理 (如 127.0.0.1:7897)，则向代理发起 CONNECT 握手
	if upstreamProxy != "" {
		u, parseErr := url.Parse(upstreamProxy)
		if parseErr == nil && u.Host != "" {
			d := net.Dialer{Timeout: 6 * time.Second}
			upstreamConn, err = d.Dial("tcp", u.Host)
			if err == nil {
				// 向上游代理发送 HTTP CONNECT
				connectReq := fmt.Sprintf("CONNECT %s HTTP/1.1\r\nHost: %s\r\n\r\n", r.Host, r.Host)
				_, err = upstreamConn.Write([]byte(connectReq))
				if err == nil {
					br := bufio.NewReader(upstreamConn)
					resp, respErr := http.ReadResponse(br, r)
					if respErr != nil || resp.StatusCode != http.StatusOK {
						if resp != nil && (resp.StatusCode == 403 || resp.StatusCode == 429) {
							g.triggerRiskAlert(r.Host, resp.StatusCode, "上游代理节点返回 403/429 访问拒绝，建议切换干净节点")
						}
						upstreamConn.Close()
						err = fmt.Errorf("upstream proxy error")
					}
				}
			}
		}
	} else {
		// 直连上游
		upstreamConn, err = net.DialTimeout("tcp", r.Host, 6*time.Second)
	}

	if err != nil {
		connLog.Status = "Blocked"
		connLog.Duration = time.Since(startTime).Truncate(time.Millisecond).String()
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	defer upstreamConn.Close()

	// 接管客户端连接
	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "webserver doesn't support hijacking", http.StatusInternalServerError)
		return
	}
	clientConn, _, err := hj.Hijack()
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	defer clientConn.Close()

	// 告知客户端隧道已打通
	_, _ = clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))

	// 双向数据中继与实时计量
	var wg sync.WaitGroup
	wg.Add(2)

	// 1. 客户端 -> 上游 (数据流出 / Outflow)
	go func() {
		defer wg.Done()
		buf := make([]byte, 32*1024)
		for {
			n, rErr := clientConn.Read(buf)
			if n > 0 {
				atomic.AddUint64(&g.totalOut, uint64(n))
				atomic.AddUint64(&connLog.BytesOut, uint64(n))
				if isClaude {
					atomic.AddUint64(&g.claudeOut, uint64(n))
				}
				_, wErr := upstreamConn.Write(buf[:n])
				if wErr != nil {
					break
				}
			}
			if rErr != nil {
				break
			}
		}
	}()

	// 2. 上游 -> 客户端 (数据流入 / Inflow)
	go func() {
		defer wg.Done()
		buf := make([]byte, 32*1024)
		for {
			n, rErr := upstreamConn.Read(buf)
			if n > 0 {
				atomic.AddUint64(&g.totalIn, uint64(n))
				atomic.AddUint64(&connLog.BytesIn, uint64(n))
				if isClaude {
					atomic.AddUint64(&g.claudeIn, uint64(n))
				}
				_, wErr := clientConn.Write(buf[:n])
				if wErr != nil {
					break
				}
			}
			if rErr != nil {
				break
			}
		}
	}()

	wg.Wait()
	connLog.Status = "Closed"
	connLog.Duration = time.Since(startTime).Truncate(time.Millisecond).String()
}

// handleForward 处理常规 HTTP 请求 (清洗 Header 并转发)
func (g *Gateway) handleForward(w http.ResponseWriter, r *http.Request) {
	atomic.AddInt32(&g.activeConn, 1)
	defer atomic.AddInt32(&g.activeConn, -1)

	isClaude := isClaudeHost(r.URL.Host)
	startTime := time.Now()
	connLog := &ConnectionLog{
		ID:        fmt.Sprintf("%d", startTime.UnixNano()),
		Time:      startTime.Format("15:04:05"),
		Host:      r.URL.Host,
		Method:    r.Method,
		Status:    "Active",
		IsClaude:  isClaude,
		StartTime: startTime,
	}
	g.addLog(connLog)

	// 自动清洗请求头中的语言特征
	r.Header.Set("Accept-Language", "en-US,en;q=0.9")

	upstreamProxy := g.GetUpstream()
	transport := &http.Transport{
		Proxy: http.ProxyFromEnvironment,
	}
	if upstreamProxy != "" {
		if u, err := url.Parse(upstreamProxy); err == nil {
			transport.Proxy = http.ProxyURL(u)
		}
	}

	outReq, err := http.NewRequest(r.Method, r.URL.String(), r.Body)
	if err != nil {
		connLog.Status = "Blocked"
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	outReq.Header = r.Header.Clone()

	resp, err := transport.RoundTrip(outReq)
	if err != nil {
		connLog.Status = "Blocked"
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode == 403 || resp.StatusCode == 429 || strings.EqualFold(resp.Header.Get("Cf-Mitigated"), "challenge") {
		g.triggerRiskAlert(r.URL.Host, resp.StatusCode, "捕获到 Cloudflare 访问挑战/拦截 (403/429/Challenge)")
	}

	// 拷贝响应头与状态码
	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)

	// 流式中继并计数流入数据
	buf := make([]byte, 16*1024)
	for {
		n, rErr := resp.Body.Read(buf)
		if n > 0 {
			atomic.AddUint64(&g.totalIn, uint64(n))
			atomic.AddUint64(&connLog.BytesIn, uint64(n))
			if isClaude {
				atomic.AddUint64(&g.claudeIn, uint64(n))
			}
			_, _ = w.Write(buf[:n])
		}
		if rErr != nil {
			break
		}
	}

	connLog.Status = "Closed"
	connLog.Duration = time.Since(startTime).Truncate(time.Millisecond).String()
}

func (g *Gateway) addLog(l *ConnectionLog) {
	g.logsLock.Lock()
	defer g.logsLock.Unlock()
	if len(g.logs) >= 80 {
		g.logs = g.logs[1:]
	}
	g.logs = append(g.logs, l)
}

func (g *Gateway) GetStats() map[string]interface{} {
	g.logsLock.RLock()
	defer g.logsLock.RUnlock()

	recentLogs := make([]*ConnectionLog, len(g.logs))
	copy(recentLogs, g.logs)

	return map[string]interface{}{
		"speedIn":       atomic.LoadUint64(&g.speedIn),
		"speedOut":      atomic.LoadUint64(&g.speedOut),
		"totalIn":       atomic.LoadUint64(&g.totalIn),
		"totalOut":      atomic.LoadUint64(&g.totalOut),
		"claudeIn":      atomic.LoadUint64(&g.claudeIn),
		"claudeOut":     atomic.LoadUint64(&g.claudeOut),
		"activeConns":   atomic.LoadInt32(&g.activeConn),
		"upstreamProxy": g.upstreamProxy,
		"riskAlert":     g.riskAlert,
		"logs":          recentLogs,
	}
}
