package main

import (
	"context"
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
}

func NewApp() *App {
	gw := NewGateway("127.0.0.1:8999", "http://127.0.0.1:7897")
	return &App{
		gateway:         gw,
		origProxyServer: "127.0.0.1:7897",
		origProxyEnable: 1,
	}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx

	// 1. 启动本地流控网关 (监听 127.0.0.1:8999)
	_ = a.gateway.Start()

	// 2. 将 Windows 系统代理切换至本网关 127.0.0.1:8999，确保所有 Chrome/Edge/Claude 流量经过此网关
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
	// 退出时无损还原系统代理
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

	// 刷新 WinINet 缓存，使浏览器无需重启即刻生效
	wininet := syscall.NewLazyDLL("wininet.dll")
	setOption := wininet.NewProc("InternetSetOptionW")
	setOption.Call(0, 39, 0, 0) // INTERNET_OPTION_SETTINGS_CHANGED
	setOption.Call(0, 37, 0, 0) // INTERNET_OPTION_REFRESH
}

// findScript 智能定位脚本绝对路径 (兼容在 bin、desktop、根目录各种运行场景)
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

	// 以 RunAs 管理员提权运行对应 PowerShell 脚本 (指定 ProxyPort 为 8999 网关)
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

	// 快速探测当前系统时区与防火墙规则状态
	cmd := exec.Command("powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", testerScript)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, _ := cmd.CombinedOutput()
	outputStr := string(out)

	isProtected := strings.Contains(outputStr, "A+ 极致隐身安全") || strings.Contains(outputStr, "良好")
	hasWebRtc := strings.Contains(outputStr, "Windows 防火墙已激活 STUN UDP 阻断规则")
	hasV6Block := strings.Contains(outputStr, "IPv6 旁路已完全阻断")
	hasSmhnr := strings.Contains(outputStr, "智能多宿主名称解析 (SMHNR) 已禁用")

	return map[string]interface{}{
		"isProtected": isProtected,
		"hasWebRtc":   hasWebRtc,
		"hasV6Block":  hasV6Block,
		"hasSmhnr":    hasSmhnr,
		"rawReport":   outputStr,
	}
}

// GetTrafficNow 手动拉取当前网关流量数据
func (a *App) GetTrafficNow() map[string]interface{} {
	return a.gateway.GetStats()
}
