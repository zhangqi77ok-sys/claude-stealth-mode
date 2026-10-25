package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"
	"golang.org/x/sys/windows/registry"
)

// App 应用核心结构体
type App struct {
	ctx             context.Context
	gateway         *Gateway
	origProxyServer string
	origProxyEnable uint32
	upstreamPort    string
}

// 自动探测本地常用代理软件的运行端口
func probeLocalProxyPort() string {
	candidates := []string{"7897", "7890", "10808", "10809", "2080", "1080"}
	for _, p := range candidates {
		conn, err := net.DialTimeout("tcp", "127.0.0.1:"+p, 120*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			return p
		}
	}
	return "7897"
}

func NewApp() *App {
	detectedPort := probeLocalProxyPort()
	upstream := "http://127.0.0.1:" + detectedPort

	gw := NewGateway("127.0.0.1:8999", upstream)
	return &App{
		gateway:         gw,
		origProxyServer: "127.0.0.1:" + detectedPort,
		origProxyEnable: 1,
		upstreamPort:    detectedPort,
	}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	// 1. 启动本地流控网关 (监听 127.0.0.1:8999)
	_ = a.gateway.Start()

	// 2. 将 Windows 系统代理切换至本网关 127.0.0.1:8999
	a.setWindowsProxy(true)

	// 3. 启动后台事件推送：每秒向前端广播当前流入流出速率与总流量
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for range ticker.C {
			stats := a.gateway.GetStats()
			runtime.EventsEmit(a.ctx, "traffic-tick", stats)
		}
	}()
}

func (a *App) shutdown(ctx context.Context) {
	a.setWindowsProxy(false)
	_ = a.gateway.Stop()
}

// setWindowsProxy 自动切换 Windows 系统代理至本地网关或还原
func (a *App) setWindowsProxy(enable bool) {
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Internet Settings`, registry.QUERY_VALUE|registry.SET_VALUE)
	if err == nil {
		defer k.Close()
		if enable {
			if orig, _, err := k.GetStringValue("ProxyServer"); err == nil && orig != "" && orig != "127.0.0.1:8999" {
				a.origProxyServer = orig
			}
			if en, _, err := k.GetIntegerValue("ProxyEnable"); err == nil {
				a.origProxyEnable = uint32(en)
			}
			_ = k.SetDWordValue("ProxyEnable", 1)
			_ = k.SetStringValue("ProxyServer", "127.0.0.1:8999")
		} else {
			if a.origProxyServer != "" {
				_ = k.SetStringValue("ProxyServer", a.origProxyServer)
				_ = k.SetDWordValue("ProxyEnable", a.origProxyEnable)
			} else {
				_ = k.SetDWordValue("ProxyEnable", 0)
			}
		}
	}

	wininet := syscall.NewLazyDLL("wininet.dll")
	setOption := wininet.NewProc("InternetSetOptionW")
	setOption.Call(0, 39, 0, 0)
	setOption.Call(0, 37, 0, 0)
}

// findScript 智能定位脚本绝对路径
func findScript(scriptName string) string {
	if exePath, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exePath)
		candidates := []string{
			filepath.Join(exeDir, scriptName),
			filepath.Join(exeDir, "..", scriptName),
			filepath.Join(exeDir, "..", "..", scriptName),
		}
		for _, c := range candidates {
			if _, err := os.Stat(c); err == nil {
				if abs, err := filepath.Abs(c); err == nil {
					return abs
				}
			}
		}
	}
	candidates := []string{
		scriptName,
		filepath.Join("..", scriptName),
		filepath.Join("..", "..", scriptName),
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			if abs, err := filepath.Abs(c); err == nil {
				return abs
			}
		}
	}
	return scriptName
}

// ToggleStealth 开启或关闭底层系统隐身防护 (UAC 管理员提升执行)
func (a *App) ToggleStealth(enable bool) (string, error) {
	scriptName := "Enable-ClaudeStealth.ps1"
	if !enable {
		scriptName = "Disable-ClaudeStealth.ps1"
	}
	scriptPath := findScript(scriptName)

	if enable {
		a.setWindowsProxy(true)
	} else {
		a.setWindowsProxy(false)
	}

	args := "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\" -NoBrowser"
	if enable {
		args += " -ProxyPort 8999"
	}

	cmd := exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
		"Start-Process powershell -Verb RunAs -ArgumentList '"+args+"'")
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	err := cmd.Run()
	if err != nil {
		return "执行失败: " + err.Error(), err
	}

	if enable {
		return "防护已启动，策略正在生效", nil
	}
	return "已还原常规日常工作模式", nil
}

// GetStatus 获取当前系统防泄漏策略检测状态 (10项)
func (a *App) GetStatus() map[string]interface{} {
	testerScript := findScript("Test-ClaudeStealth.ps1")

	cmd := exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", testerScript)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, _ := cmd.CombinedOutput()
	outputStr := string(out)

	isProtected := strings.Contains(outputStr, "A+ 极致隐身安全") || strings.Contains(outputStr, "良好")
	hasWebRtc := strings.Contains(outputStr, "Windows 防火墙已激活 STUN UDP 阻断规则")
	hasV6Block := strings.Contains(outputStr, "IPv6 旁路已完全阻断")
	hasSmhnr := strings.Contains(outputStr, "智能多宿主名称解析 (SMHNR) 已禁用")

	return map[string]interface{}{
		"isProtected":  isProtected,
		"hasWebRtc":    hasWebRtc,
		"hasV6Block":   hasV6Block,
		"hasSmhnr":     hasSmhnr,
		"upstreamPort": a.upstreamPort,
		"isAutoStart":  a.GetAutoStart(),
		"rawReport":    outputStr,
	}
}

// GetTrafficNow 手动拉取当前网关流量数据
func (a *App) GetTrafficNow() map[string]interface{} {
	stats := a.gateway.GetStats()
	stats["upstreamPort"] = a.upstreamPort
	return stats
}

// ClearTrafficLogs 清空网关历史日志
func (a *App) ClearTrafficLogs() bool {
	a.gateway.ClearLogs()
	return true
}

// DismissRiskAlert 忽略当前风控警报
func (a *App) DismissRiskAlert() bool {
	a.gateway.DismissRiskAlert()
	return true
}

// SetUpstreamPort 手动或自动切换上游代理端口 (如 7897, 7890, 10808)
func (a *App) SetUpstreamPort(port string) string {
	cleanPort := strings.TrimSpace(port)
	if cleanPort == "" {
		cleanPort = "7897"
	}
	a.upstreamPort = cleanPort
	upstreamURL := "http://127.0.0.1:" + cleanPort
	a.gateway.SetUpstream(upstreamURL)
	return fmt.Sprintf("已切换上游代理至 127.0.0.1:%s", cleanPort)
}

// TestNodeLatency 实时探测节点出口 IP、归属国与网络延迟 (经由网关 8999 探测)
func (a *App) TestNodeLatency() map[string]interface{} {
	proxyURL, _ := url.Parse("http://127.0.0.1:8999")
	client := &http.Client{
		Transport: &http.Transport{
			Proxy: http.ProxyURL(proxyURL),
		},
		Timeout: 5 * time.Second,
	}

	start := time.Now()
	resp, err := client.Get("https://www.cloudflare.com/cdn-cgi/trace")
	latency := time.Since(start).Milliseconds()

	if err != nil {
		return map[string]interface{}{
			"success": false,
			"error":   err.Error(),
			"latency": latency,
		}
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	bodyStr := string(bodyBytes)

	ip := ""
	loc := ""
	lines := strings.Split(bodyStr, "\n")
	for _, l := range lines {
		if strings.HasPrefix(l, "ip=") {
			ip = strings.TrimPrefix(l, "ip=")
		}
		if strings.HasPrefix(l, "loc=") {
			loc = strings.TrimPrefix(l, "loc=")
		}
	}

	return map[string]interface{}{
		"success": true,
		"latency": latency,
		"ip":      ip,
		"loc":     loc,
		"isUS":    loc == "US",
	}
}

// WipeClaudeDeviceFingerprint 彻底抹除 Claude 设备硬件指纹 (ant-did)、沙箱缓存与残留
func (a *App) WipeClaudeDeviceFingerprint() map[string]interface{} {
	_ = exec.Command("taskkill", "/F", "/IM", "claude.exe").Run()

	localAppData := os.Getenv("LOCALAPPDATA")

	// 清理 WindowsApps 商店版硬件指纹与沙箱
	storeCache := filepath.Join(localAppData, "Packages", "Claude_pzs8sxrjxfjjc", "LocalCache")
	if _, err := os.Stat(storeCache); err == nil {
		_ = os.RemoveAll(storeCache)
	}

	// 清理独立安装版 LocalAppData
	userClaude := filepath.Join(localAppData, "Claude")
	if _, err := os.Stat(userClaude); err == nil {
		_ = os.RemoveAll(filepath.Join(userClaude, "Cache"))
		_ = os.RemoveAll(filepath.Join(userClaude, "Code Cache"))
		_ = os.RemoveAll(filepath.Join(userClaude, "Session Storage"))
		_ = os.Remove(filepath.Join(userClaude, "ant-device-registry.json"))
	}

	// 清理 Temp 中的临时会话
	tempDir := os.Getenv("TEMP")
	entries, _ := os.ReadDir(tempDir)
	for _, e := range entries {
		if strings.Contains(strings.ToLower(e.Name()), "claude") {
			_ = os.RemoveAll(filepath.Join(tempDir, e.Name()))
		}
	}

	return map[string]interface{}{
		"success": true,
		"message": "已彻底粉碎 Claude 硬件指纹 (ant-did)、沙箱缓存与残留记录！",
	}
}

// ToggleAutoStart 开关开机自启
func (a *App) ToggleAutoStart(enable bool) bool {
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, registry.SET_VALUE)
	if err != nil {
		return false
	}
	defer k.Close()

	if enable {
		if exe, err := os.Executable(); err == nil {
			_ = k.SetStringValue("ClaudeStealthGuardian", exe)
			return true
		}
	} else {
		_ = k.DeleteValue("ClaudeStealthGuardian")
		return false
	}
	return false
}

// GetAutoStart 获取当前是否设置了开机自启
func (a *App) GetAutoStart() bool {
	k, err := registry.OpenKey(registry.CURRENT_USER, `Software\Microsoft\Windows\CurrentVersion\Run`, registry.QUERY_VALUE)
	if err != nil {
		return false
	}
	defer k.Close()
	_, _, err = k.GetStringValue("ClaudeStealthGuardian")
	return err == nil
}

// RunFullCheck 运行完整 10 项健康体检并返回结构化报告数据
func (a *App) RunFullCheck() map[string]interface{} {
	testerScript := findScript("Test-ClaudeStealth.ps1")
	cmd := exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", testerScript)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, _ := cmd.CombinedOutput()
	output := string(out)

	type CheckItem struct {
		Title  string `json:"title"`
		Passed bool   `json:"passed"`
		Desc   string `json:"desc"`
	}

	items := []CheckItem{
		{
			Title:  "CLI 与子进程环境变量代理",
			Passed: strings.Contains(output, "系统用户环境变量已注入"),
			Desc:   "HTTP_PROXY / ALL_PROXY 已就绪",
		},
		{
			Title:  "IPv4 出口与国家检测 (US)",
			Passed: strings.Contains(output, "国家: US") || strings.Contains(output, "代理出口正常"),
			Desc:   "节点出口归属美国，延迟良好",
		},
		{
			Title:  "IPv6 旁路阻断防护",
			Passed: strings.Contains(output, "IPv6 旁路已完全阻断"),
			Desc:   "物理网卡与防火墙出站双重封死 IPv6",
		},
		{
			Title:  "WebRTC STUN UDP 隔离",
			Passed: strings.Contains(output, "Windows 防火墙已激活 STUN UDP 阻断规则"),
			Desc:   "3478/19302 端口拦截，杜绝真实 IP 暴露",
		},
		{
			Title:  "Windows 智能多宿主 DNS 封堵",
			Passed: strings.Contains(output, "智能多宿主名称解析 (SMHNR) 已禁用"),
			Desc:   "禁止向国内物理网卡并发探测 DNS",
		},
		{
			Title:  "QUIC (HTTP/3 UDP 443) 禁用",
			Passed: strings.Contains(output, "QUIC 协议已禁用"),
			Desc:   "封死 UDP 443 旁路，强制走 TCP 代理安全通道",
		},
		{
			Title:  "远端代理 DNS 强制解析",
			Passed: strings.Contains(output, "浏览器异步 DNS 已禁用"),
			Desc:   "域名解析完全委托远端代理 (Remote DNS)",
		},
		{
			Title:  "HTML5 物理地理位置定位封锁",
			Passed: strings.Contains(output, "浏览器物理定位已全面禁止"),
			Desc:   "切断 Wi-Fi BSSID 物理位置穿透",
		},
		{
			Title:  "系统时区与国家代码伪装",
			Passed: strings.Contains(output, "Pacific Standard Time") || strings.Contains(output, "GeoID: 244"),
			Desc:   "锁定美国太平洋时间与 GeoID 244",
		},
		{
			Title:  "Claude Desktop 专属断网熔断 (Kill Switch)",
			Passed: strings.Contains(output, "Claude Desktop 熔断已激活") || strings.Contains(output, "未检测到本地已安装的 Claude Desktop"),
			Desc:   "严禁公网直连，代理异常物理断网 (Fail-Closed)",
		},
	}

	passCount := 0
	for _, it := range items {
		if it.Passed {
			passCount++
		}
	}

	grade := "B 基础防护"
	if passCount >= 10 {
		grade = "A+ 极致隐身安全 (满分)"
	} else if passCount >= 8 {
		grade = "A 良好安全防护"
	}

	return map[string]interface{}{
		"items":     items,
		"score":     passCount,
		"total":     len(items),
		"grade":     grade,
		"rawReport": output,
	}
}
