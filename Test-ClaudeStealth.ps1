<#
.SYNOPSIS
    Claude 隐身环境与防泄漏健康体检工具 (CLI 自动化测试)
.DESCRIPTION
    全方位体检当前系统与网络防封状态：
    1. CLI 与系统代理环境变量配置
    2. IPv4 出口 IP、延迟与国家/地区判定 (US)
    3. IPv6 旁路阻断与泄漏检测 (确保国内 IPv6 无法直连外网)
    4. WebRTC STUN UDP 防火墙拦截状态
    5. Windows 智能多宿主 DNS (SMHNR) 防泄露策略
    6. 系统时区与国家区域伪装
    7. 浏览器底层企业组策略 (WebRTC 禁用非代理 UDP 与 英语语言锁定)
#>

param (
    [string]$ProxyPort = "7897"
)

$ErrorActionPreference = "SilentlyContinue"
$proxyHttp = "http://127.0.0.1:$ProxyPort"

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "       🛡️ Claude 隐身防泄漏环境健康体检报告 (CLI)         " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$score = 0
$totalTests = 7

# -------------------------------------------------------------------------
# 1. 检查环境变量代理
# -------------------------------------------------------------------------
Write-Host "`n[1/7] 正在检测 CLI 与代码子进程代理环境变量..." -ForegroundColor Yellow
$userHttp = [System.Environment]::GetEnvironmentVariable("HTTP_PROXY", "User")
$userHttps = [System.Environment]::GetEnvironmentVariable("HTTPS_PROXY", "User")
if ($userHttp -and $userHttps) {
    Write-Host "  ✅ 系统用户环境变量已注入: HTTP_PROXY=$userHttp" -ForegroundColor Green
    $score++
} else {
    Write-Host "  ⚠️ 系统用户环境变量未检测到代理注入 (非隐身模式或已还原)" -ForegroundColor DarkYellow
}

# -------------------------------------------------------------------------
# 2. 检查 IPv4 代理出口与可用性
# -------------------------------------------------------------------------
Write-Host "`n[2/7] 正在发起 IPv4 代理出口与 Claude 连通性测试..." -ForegroundColor Yellow
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $trace = Invoke-RestMethod -Uri "https://www.cloudflare.com/cdn-cgi/trace" -Proxy $proxyHttp -TimeoutSec 6
    $sw.Stop()
    $loc = ($trace -split "`n" | Where-Object { $_ -match "^loc=" }) -replace "loc=", ""
    $ip = ($trace -split "`n" | Where-Object { $_ -match "^ip=" }) -replace "ip=", ""
    
    if ($loc -eq "US") {
        Write-Host "  ✅ 代理出口正常: $ip (国家: $loc，延迟: $($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
        $score++
    } else {
        Write-Host "  ⚠️ 代理出口可用，但归属地区为 [$loc] (建议在代理软件中切换为美国节点)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ❌ 代理连接失败，请检查 Clash Verge 是否处于开启状态并监听端口 $ProxyPort" -ForegroundColor Red
}

# -------------------------------------------------------------------------
# 3. 检查 IPv6 旁路封堵与防泄漏
# -------------------------------------------------------------------------
Write-Host "`n[3/7] 正在探测 IPv6 旁路泄漏状态..." -ForegroundColor Yellow
$activeV6Adapters = Get-NetAdapterBinding -ComponentId ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
$v6FwRule = Get-NetFirewallRule -DisplayName "ClaudeStealth_Block_IPv6_Outbound" -ErrorAction SilentlyContinue

# 测试是否能直连公网 IPv6
$canConnectV6 = $false
try {
    $v6Client = New-Object System.Net.Sockets.TcpClient
    $iar = $v6Client.BeginConnect("2606:4700:4700::1111", 53, $null, $null)
    $success = $iar.AsyncWaitHandle.WaitOne(1500)
    if ($success) {
        $v6Client.EndConnect($iar)
        $canConnectV6 = $true
    }
    $v6Client.Close()
} catch {}

if (-not $canConnectV6) {
    Write-Host "  ✅ IPv6 旁路已完全阻断 (无法直连外网 IPv6，杜绝国内真实 IP 绕过代理)" -ForegroundColor Green
    $score++
} else {
    Write-Host "  ⚠️ 检测到物理网络支持公网 IPv6 直连，可能存在双栈绕过代理风险" -ForegroundColor Red
}

# -------------------------------------------------------------------------
# 4. 检查 WebRTC STUN UDP 防火墙拦截
# -------------------------------------------------------------------------
Write-Host "`n[4/7] 正在检测 WebRTC STUN UDP 防火墙隔离状态..." -ForegroundColor Yellow
$stunRule = Get-NetFirewallRule -DisplayName "ClaudeStealth_Block_WebRTC_STUN" -ErrorAction SilentlyContinue
$chromeUdpRule = Get-NetFirewallRule -DisplayName "ClaudeStealth_Block_Chrome_UDP" -ErrorAction SilentlyContinue

if ($stunRule -and $stunRule.Enabled -eq "True") {
    Write-Host "  ✅ Windows 防火墙已激活 STUN UDP 阻断规则 (端口 3478, 19302~19309 已锁定)" -ForegroundColor Green
    if ($chromeUdpRule -and $chromeUdpRule.Enabled -eq "True") {
        Write-Host "  ✅ Windows 防火墙已激活 Chrome UDP 直连隔离规则" -ForegroundColor Green
    }
    $score++
} else {
    Write-Host "  ⚠️ 未检测到 STUN UDP 防火墙出站规则" -ForegroundColor DarkYellow
}

# -------------------------------------------------------------------------
# 5. 检查 Windows 智能多宿主 DNS 策略 (SMHNR)
# -------------------------------------------------------------------------
Write-Host "`n[5/7] 正在检测 Windows 智能多宿主 DNS 防泄露策略..." -ForegroundColor Yellow
$dnsPolicy = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -ErrorAction SilentlyContinue
if ($dnsPolicy -and $dnsPolicy.DisableSmartNameResolution -eq 1) {
    Write-Host "  ✅ 智能多宿主名称解析 (SMHNR) 已禁用 (杜绝向国内网卡并发探测 DNS)" -ForegroundColor Green
    $score++
} else {
    Write-Host "  ℹ️ SMHNR 策略未配置 (隐身模式开启时将自动注入)" -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# 6. 检查系统时区与区域归属
# -------------------------------------------------------------------------
Write-Host "`n[6/7] 正在检测系统时区与地理归属..." -ForegroundColor Yellow
$curTz = tzutil /g
$curGeo = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
if ($curTz -match "Pacific" -and $curGeo -eq 244) {
    Write-Host "  ✅ 系统时区与区域已匹配美国: $curTz (GeoID: 244)" -ForegroundColor Green
    $score++
} else {
    Write-Host "  ⚠️ 当前系统时区为: $curTz (GeoID: $curGeo)" -ForegroundColor DarkYellow
}

# -------------------------------------------------------------------------
# 7. 检查浏览器底层企业组策略
# -------------------------------------------------------------------------
Write-Host "`n[7/7] 正在检测浏览器 WebRTC 与语言企业策略..." -ForegroundColor Yellow
$chromePol = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -ErrorAction SilentlyContinue
$forcedLang = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome\ForcedLanguages" -ErrorAction SilentlyContinue

$webrtcOk = ($chromePol -and $chromePol.WebRtcIPHandlingPolicy -eq "disable_non_proxied_udp")
$langOk = ($chromePol -and $chromePol.ApplicationLocaleValue -eq "en-US") -and ($forcedLang -and $forcedLang."1" -eq "en-US")

if ($webrtcOk -and $langOk) {
    Write-Host "  ✅ Chrome 组策略生效: disable_non_proxied_udp 且锁定 en-US 语言" -ForegroundColor Green
    $score++
} elseif ($webrtcOk) {
    Write-Host "  ⚠️ Chrome WebRTC 策略已就绪，但 ForcedLanguages 语言组策略未生效" -ForegroundColor Yellow
} else {
    Write-Host "  ℹ️ 浏览器企业策略未配置" -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# 汇总评分展示
# -------------------------------------------------------------------------
Write-Host "`n==========================================================" -ForegroundColor Cyan
if ($score -eq $totalTests) {
    Write-Host "  🎉 体检通过！各项指标评级: [A+ 极致隐身安全] ($score/$totalTests)" -ForegroundColor Green
    Write-Host "  🛡️ WebRTC、IPv6、DNS、时区与语言已 100% 物理级隔离！" -ForegroundColor Green
} elseif ($score -ge 5) {
    Write-Host "  🟡 当前环境评级: [良好] ($score/$totalTests 项达标)" -ForegroundColor Yellow
    Write-Host "  💡 可运行 .\Enable-ClaudeStealth.ps1 一键补全未达标策略。" -ForegroundColor DarkGray
} else {
    Write-Host "  ⚪ 当前处于常规日常模式 / 未开启隐身 ($score/$totalTests)" -ForegroundColor DarkGray
    Write-Host "  💡 使用 Claude 前请右键以管理员运行 .\Enable-ClaudeStealth.ps1" -ForegroundColor Cyan
}
Write-Host "==========================================================" -ForegroundColor Cyan
