<#
.SYNOPSIS
    Claude 终极隐身模式（无需开启 TUN 模式）
.DESCRIPTION
    彻底解决在不开启 TUN 模式下，系统、浏览器及桌面端子进程（PowerShell/Git/Node/Python）暴露中国 IP、时区与语言的问题。
#>

param (
    [string]$ProxyPort = "7897",
    [string]$Timezone = "Pacific Standard Time"
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "        🚀 启动 Claude 终极防检测隐身模式 (免 TUN 模式)    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$proxyHttp = "http://127.0.0.1:$ProxyPort"
$proxySocks = "socks5://127.0.0.1:$ProxyPort"

# -------------------------------------------------------------------------
# 1. 注入用户级环境变量：彻底堵死桌面端代码子进程（PowerShell/Git/Node）的裸连泄露
# -------------------------------------------------------------------------
Write-Host "`n[1/5] 正在配置系统与 CLI 代理环境变量..." -ForegroundColor Yellow
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $proxySocks, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1", "User")

$env:HTTP_PROXY = $proxyHttp
$env:HTTPS_PROXY = $proxyHttp
$env:ALL_PROXY = $proxySocks
$env:NO_PROXY = "localhost,127.0.0.1"

# 顺便配置 Git 代理（桌面端写代码调用 git 时不再泄露）
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global http.proxy $proxyHttp
    git config --global https.proxy $proxyHttp
    Write-Host "  ✅ Git 全局代理已设为 $proxyHttp" -ForegroundColor Green
}
Write-Host "  ✅ 命令行与子进程代理已生效 (HTTP_PROXY / HTTPS_PROXY = $proxyHttp)" -ForegroundColor Green

# -------------------------------------------------------------------------
# 2. 切换系统时区为美国太平洋时间，并锁定防止系统自动改回
# -------------------------------------------------------------------------
Write-Host "`n[2/5] 正在修改并锁定系统时区为 [$Timezone]..." -ForegroundColor Yellow
tzutil /s $Timezone
$currentTz = tzutil /g
Write-Host "  ✅ 当前系统时区已切换为: $currentTz" -ForegroundColor Green

# -------------------------------------------------------------------------
# 3. 封堵 Chrome 浏览器的 WebRTC 真实 IP 泄漏
# -------------------------------------------------------------------------
Write-Host "`n[3/5] 正在配置 Chrome 浏览器 WebRTC 防泄漏策略..." -ForegroundColor Yellow
$chromePrefPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Preferences"
if (Test-Path $chromePrefPath) {
    try {
        $raw = Get-Content $chromePrefPath -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json
        
        # 写入 webrtc.ip_handling_policy = disable_non_proxied_udp
        if (-not ($obj.PSObject.Properties.Name -contains "webrtc")) {
            $obj | Add-Member -NotePropertyName "webrtc" -NotePropertyValue ([PSCustomObject]@{
                ip_handling_policy = "disable_non_proxied_udp"
            }) -Force
        } else {
            if (-not ($obj.webrtc.PSObject.Properties.Name -contains "ip_handling_policy")) {
                $obj.webrtc | Add-Member -NotePropertyName "ip_handling_policy" -NotePropertyValue "disable_non_proxied_udp" -Force
            } else {
                $obj.webrtc.ip_handling_policy = "disable_non_proxied_udp"
            }
        }
        
        # 强制首选英语
        if (-not ($obj.intl.PSObject.Properties.Name -contains "accept_languages")) {
            $obj.intl | Add-Member -NotePropertyName "accept_languages" -NotePropertyValue "en-US,en" -Force
        } else {
            $obj.intl.accept_languages = "en-US,en"
        }
        $obj.intl.selected_languages = "en-US,en"
        
        $obj | ConvertTo-Json -Depth 100 | Set-Content $chromePrefPath -Encoding UTF8
        Write-Host "  ✅ Chrome WebRTC 策略已锁定 (disable_non_proxied_udp)" -ForegroundColor Green
        Write-Host "  ✅ Chrome 语言请求头已锁定 (en-US,en)" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ 写入 Chrome Preferences 失败（可能浏览器正打开），已跳过" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  ℹ️ 未检测到 Chrome 默认配置文件路径" -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# 4. 清理旧的 Claude 桌面端与浏览器缓存残留
# -------------------------------------------------------------------------
Write-Host "`n[4/5] 正在扫描并清理 Claude 历史设备指纹与沙箱残留..." -ForegroundColor Yellow
$claudePkgData = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache"
if (Test-Path $claudePkgData) {
    Remove-Item -Path $claudePkgData -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✅ 已抹除 Claude 硬件指纹 (ant-did)" -ForegroundColor Green
}
Get-ChildItem "$env:LOCALAPPDATA\Temp" -Filter "*claude*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  ✅ 已清理临时执行沙箱文件" -ForegroundColor Green

# -------------------------------------------------------------------------
# 5. 实时检测外网出口与纯净度验证
# -------------------------------------------------------------------------
Write-Host "`n[5/5] 正在发起外网出口连通性与泄漏检测..." -ForegroundColor Yellow
try {
    $trace = Invoke-RestMethod -Uri "https://www.cloudflare.com/cdn-cgi/trace" -Proxy $proxyHttp -TimeoutSec 6
    $loc = ($trace -split "`n" | Where-Object { $_ -match "^loc=" }) -replace "loc=", ""
    $ip = ($trace -split "`n" | Where-Object { $_ -match "^ip=" }) -replace "ip=", ""
    Write-Host "  🌐 当前代理出口 IP: $ip (国家/地区代码: $loc)" -ForegroundColor Cyan
    
    if ($loc -eq "US") {
        Write-Host "  🎉 恭喜！当前网络出口已被正确识别为：美国 (US)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️ 当前节点出口地区为: $loc (建议在代理软件中切换为美国节点)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ❌ 代理请求超时，请检查 Clash Verge 是否处于开启状态并监听在端口 $ProxyPort" -ForegroundColor Red
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  ✨ 隐身保护已就绪！您现在可以安全地使用浏览器或桌面端了。" -ForegroundColor Green
Write-Host "  💡 平时不用时，可运行同目录下的 [Disable-ClaudeStealth.ps1] 一键复原。" -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan
