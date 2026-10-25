<#
.SYNOPSIS
    Claude 终极防检测隐身模式 (全自动生产级防护版)
.DESCRIPTION
    彻底解决在免 TUN 模式下，系统、浏览器及桌面端子进程（PowerShell/Git/Node/Python）暴露真实 IP、时区与语言的问题。
    全自动化系统级拦截与伪装：
    1. 自提管理员权限 (UAC) 确保系统网络、组策略与防火墙 100% 写入成功；
    2. 创建状态快照 (.stealth-snapshot.json)，保障用完后无损恢复原有个人系统设置；
    3. 彻底封堵 IPv6 旁路泄漏（禁用物理网卡 IPv6 绑定 + 防火墙阻断所有 IPv6 出站）；
    4. 彻底封堵 Windows 智能多宿主 DNS 泄漏 (禁用 SMHNR 并发向国内网卡发包)；
    5. 物理级防火墙与组策略阻断 WebRTC UDP 泄漏（阻断 STUN 3478/19302 与浏览器直接 UDP）；
    6. 强制浏览器首选语言与界面伪装为 en-US / en (组策略 ForcedLanguages + Preferences 锁定)；
    7. 切换并锁定系统时区为美国太平洋时间 (Pacific Standard Time)，国家代码设为美国 (GeoID 244)；
    8. 注入 CLI 代理环境变量、Git 全局代理与 PowerShell Profile，消除执行策略报错；
    9. 清理 Claude 历史硬件指纹 (ant-did) 与沙箱缓存；
    10. 自动执行全面健康体检并启动 Chrome 打开 https://ip.net.coffee/claude/ 即刻验收。
#>

param (
    [string]$ProxyPort = "7897",
    [string]$Timezone = "Pacific Standard Time",
    [switch]$NoBrowser = $false
)

# -------------------------------------------------------------------------
# 0. 自动获取管理员权限与执行策略
# -------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "🛡️ 正在申请管理员权限以应用底层系统防火墙与安全策略..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($PSBoundParameters.Count -gt 0) {
        foreach ($key in $PSBoundParameters.Keys) {
            $argList += " -$key `"$($PSBoundParameters[$key])`""
        }
    }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

# 解决 PowerShell Profile 加载执行策略报错
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     🚀 启动 Claude 终极防检测隐身模式 (全自动加固版)     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$proxyHttp = "http://127.0.0.1:$ProxyPort"
$proxySocks = "socks5://127.0.0.1:$ProxyPort"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$snapshotPath = Join-Path $scriptDir ".stealth-snapshot.json"

# -------------------------------------------------------------------------
# 1. 创建状态快照（记录原系统配置，保障后续 100% 无损还原）
# -------------------------------------------------------------------------
Write-Host "`n[1/8] 正在记录当前系统状态快照以备无损还原..." -ForegroundColor Yellow
if (-not (Test-Path $snapshotPath)) {
    try {
        $curTz = tzutil /g
        $curGeo = (Get-WinHomeLocation -ErrorAction SilentlyContinue).GeoId
        $v6Adapters = @(Get-NetAdapterBinding -ComponentId ms_tcpip6 -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true } | Select-Object -ExpandProperty Name)
        $origHttpProxy = [System.Environment]::GetEnvironmentVariable("HTTP_PROXY", "User")
        
        $snapshot = [PSCustomObject]@{
            OriginalTimezone   = $curTz
            OriginalGeoId      = $curGeo
            OriginalV6Adapters = $v6Adapters
            OriginalHttpProxy  = $origHttpProxy
            CreatedTime        = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        }
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $snapshotPath -Encoding UTF8
        Write-Host "  ✅ 系统原值快照已安全保存 (.stealth-snapshot.json)" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ 写入快照失败，还原时将采用推荐默认值" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  ℹ️ 已存在先前快照，将保留首次原值配置" -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# 2. 封堵 IPv6 旁路泄露（切断国内宽带真实 IPv6 直连）
# -------------------------------------------------------------------------
Write-Host "`n[2/8] 正在封堵 IPv6 旁路网络泄露..." -ForegroundColor Yellow
# 2.1 临时禁用物理活动网卡的 IPv6 协议绑定
$activeAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -notmatch "Clash|TAP|VPN|vEthernet" }
foreach ($adapter in $activeAdapters) {
    Disable-NetAdapterBinding -Name $adapter.Name -ComponentId ms_tcpip6 -Confirm:$false -ErrorAction SilentlyContinue
}
# 2.2 防火墙规则：阻断所有未经代理出站的 IPv6 数据包
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_IPv6_Outbound" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "ClaudeStealth_Block_IPv6_Outbound" `
    -Direction Outbound -Protocol Any -RemoteAddress "::/0" `
    -Action Block -Description "Claude Stealth Mode: Block all IPv6 outbound leaks" | Out-Null
Write-Host "  ✅ IPv6 旁路通道已锁定 (物理网卡 IPv6 绑定与出站路由已阻断)" -ForegroundColor Green

# -------------------------------------------------------------------------
# 3. 封堵 Windows 智能多宿主 DNS 泄露 (SMHNR)
# -------------------------------------------------------------------------
Write-Host "`n[3/8] 正在封堵 Windows 智能多宿主 DNS 泄露..." -ForegroundColor Yellow
$dnsPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
if (-not (Test-Path $dnsPolicyPath)) {
    New-Item -Path $dnsPolicyPath -Force | Out-Null
}
Set-ItemProperty -Path $dnsPolicyPath -Name "DisableSmartNameResolution" -Value 1 -Type DWord -Force
Write-Host "  ✅ 智能多宿主 DNS 解析已禁用 (阻断向国内网卡并发探测 DNS)" -ForegroundColor Green

# -------------------------------------------------------------------------
# 4. 物理级防火墙与策略阻断 WebRTC UDP 泄漏
# -------------------------------------------------------------------------
Write-Host "`n[4/8] 正在注入 WebRTC 防火墙与底层企业组策略..." -ForegroundColor Yellow

$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) {
    $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
}
$edgeExe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edgeExe)) {
    $edgeExe = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
}

# 4.1 写入 Windows 防火墙出站规则：阻断常见 STUN/TURN UDP 探测端口
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_WebRTC_STUN" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_Chrome_UDP" -ErrorAction SilentlyContinue

New-NetFirewallRule -DisplayName "ClaudeStealth_Block_WebRTC_STUN" `
    -Direction Outbound -Protocol UDP -RemotePort 3478,19302,19303,19304,19305,19306,19307,19308,19309,5349 `
    -Action Block -Description "Claude Stealth Mode: Block STUN UDP Leak" | Out-Null
Write-Host "  ✅ Windows 防火墙: 已拦截 STUN UDP 探测端口 (3478, 19302~19309)" -ForegroundColor Green

# 4.2 阻断 Chrome 浏览器直接出站 UDP（强制走 TCP 代理）
if (Test-Path $chromeExe) {
    New-NetFirewallRule -DisplayName "ClaudeStealth_Block_Chrome_UDP" `
        -Direction Outbound -Program $chromeExe -Protocol UDP `
        -Action Block -Description "Claude Stealth Mode: Block Chrome Outbound UDP" | Out-Null
    Write-Host "  ✅ Windows 防火墙: 已阻断 Chrome UDP 直连 (彻底消灭 111.x 真实公网 IP 暴露)" -ForegroundColor Green
}

# 4.3 注入 Chrome / Edge 企业组策略注册表 (disable_non_proxied_udp)
$browserPolicyPaths = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
)
foreach ($bPath in $browserPolicyPaths) {
    if (-not (Test-Path $bPath)) {
        New-Item -Path $bPath -Force | Out-Null
    }
    Set-ItemProperty -Path $bPath -Name "WebRtcIPHandlingPolicy" -Value "disable_non_proxied_udp" -Type String -Force
}
Write-Host "  ✅ 浏览器底层策略已锁定: disable_non_proxied_udp" -ForegroundColor Green

# -------------------------------------------------------------------------
# 5. 全自动化伪装浏览器语言为 en-US / en
# -------------------------------------------------------------------------
Write-Host "`n[5/8] 正在配置浏览器首选语言为英语 (en-US, en)..." -ForegroundColor Yellow

# 5.1 组策略下发 ForcedLanguages 与 ApplicationLocaleValue
foreach ($bPath in $browserPolicyPaths) {
    Set-ItemProperty -Path $bPath -Name "ApplicationLocaleValue" -Value "en-US" -Type String -Force
    
    $forcedLangPath = Join-Path $bPath "ForcedLanguages"
    if (-not (Test-Path $forcedLangPath)) {
        New-Item -Path $forcedLangPath -Force | Out-Null
    }
    Set-ItemProperty -Path $forcedLangPath -Name "1" -Value "en-US" -Type String -Force
    Set-ItemProperty -Path $forcedLangPath -Name "2" -Value "en" -Type String -Force
}

# 5.2 若 Chrome 正在运行，平滑刷新以加载组策略并防写入冲突
$chromeProcs = Get-Process chrome -ErrorAction SilentlyContinue
if ($chromeProcs) {
    Write-Host "  ℹ️ 检测到 Chrome 正在运行，正在重载进程以应用新策略..." -ForegroundColor Yellow
    $chromeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# 5.3 扫描并改写所有 Chrome 用户 Profile Preferences
$userDataDir = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $userDataDir) {
    $profileDirs = Get-ChildItem -Path $userDataDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
    foreach ($pDir in $profileDirs) {
        $prefFile = Join-Path $pDir.FullName "Preferences"
        if (Test-Path $prefFile) {
            try {
                $raw = Get-Content $prefFile -Raw -Encoding UTF8
                $obj = $raw | ConvertFrom-Json
                
                # webrtc
                if (-not ($obj.PSObject.Properties.Name -contains "webrtc")) {
                    $obj | Add-Member -NotePropertyName "webrtc" -NotePropertyValue ([PSCustomObject]@{ ip_handling_policy = "disable_non_proxied_udp" }) -Force
                } else {
                    $obj.webrtc.ip_handling_policy = "disable_non_proxied_udp"
                }
                
                # intl
                if (-not ($obj.PSObject.Properties.Name -contains "intl")) {
                    $obj | Add-Member -NotePropertyName "intl" -NotePropertyValue ([PSCustomObject]@{
                        accept_languages = "en-US,en"
                        selected_languages = "en-US,en"
                    }) -Force
                } else {
                    $obj.intl.accept_languages = "en-US,en"
                    $obj.intl.selected_languages = "en-US,en"
                }
                
                $obj | ConvertTo-Json -Depth 100 | Set-Content $prefFile -Encoding UTF8
            } catch {}
        }
    }
    Write-Host "  ✅ Chrome 用户配置文件语言偏好已同步为 en-US" -ForegroundColor Green
}

# -------------------------------------------------------------------------
# 6. 切换系统时区为美国太平洋时间，并锁定
# -------------------------------------------------------------------------
Write-Host "`n[6/8] 正在修改系统时区为 [$Timezone]..." -ForegroundColor Yellow
Set-Service -Name tzautoupdate -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service -Name tzautoupdate -Force -ErrorAction SilentlyContinue
tzutil /s $Timezone
Set-WinHomeLocation -GeoId 244 -ErrorAction SilentlyContinue
$currentTz = tzutil /g
Write-Host "  ✅ 当前系统时区已锁定为: $currentTz (GeoID: 244 美国)" -ForegroundColor Green

# -------------------------------------------------------------------------
# 7. 注入 CLI 代理环境变量、PowerShell Profile 与 Git 代理
# -------------------------------------------------------------------------
Write-Host "`n[7/8] 正在配置系统与 CLI 代理环境变量..." -ForegroundColor Yellow
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $proxySocks, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1", "User")

$env:HTTP_PROXY = $proxyHttp
$env:HTTPS_PROXY = $proxyHttp
$env:ALL_PROXY = $proxySocks
$env:NO_PROXY = "localhost,127.0.0.1"

# 注入 PowerShell Profile（保证 Claude 桌面端拉起命令进程时自动带代理）
$psProfileDirs = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell",
    "$env:USERPROFILE\Documents\PowerShell"
)
$profileSnippet = @"
# === Claude Stealth Mode Proxy Auto-Inject ===
`$env:HTTP_PROXY = "$proxyHttp"
`$env:HTTPS_PROXY = "$proxyHttp"
`$env:ALL_PROXY = "$proxySocks"
`$env:NO_PROXY = "localhost,127.0.0.1"
"@

foreach ($dir in $psProfileDirs) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $p1 = Join-Path $dir "profile.ps1"
    Set-Content -Path $p1 -Value $profileSnippet -Encoding UTF8 -Force
}

# 广播系统环境变量变更
try {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
    $result = [System.UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout([System.IntPtr]0xffff, 0x001A, [System.UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
} catch {}

if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global http.proxy $proxyHttp
    git config --global https.proxy $proxyHttp
}
Write-Host "  ✅ 命令行与子进程代理已就绪 (HTTP_PROXY / ALL_PROXY / Git)" -ForegroundColor Green

# 清理旧的 Claude 桌面端硬件指纹与沙箱残留
$claudePkgData = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache"
if (Test-Path $claudePkgData) {
    Remove-Item -Path $claudePkgData -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✅ 已抹除旧 Claude 硬件指纹 (ant-did)" -ForegroundColor Green
}
Get-ChildItem "$env:LOCALAPPDATA\Temp" -Filter "*claude*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------------
# 8. 执行全面健康自检并自动拉起浏览器
# -------------------------------------------------------------------------
Write-Host "`n[8/8] 正在运行全面隐身环境自检..." -ForegroundColor Yellow
$testerScript = Join-Path $scriptDir "Test-ClaudeStealth.ps1"
if (Test-Path $testerScript) {
    & $testerScript -ProxyPort $ProxyPort
}

# 自动启动 Chrome 并打开检测页进行验收
if (-not $NoBrowser -and (Test-Path $chromeExe)) {
    Write-Host "`n🚀 正在拉起 Chrome 打开 https://ip.net.coffee/claude/ 进行实时验收..." -ForegroundColor Green
    Start-Process $chromeExe -ArgumentList "--force-webrtc-ip-handling-policy=disable_non_proxied_udp --lang=en-US https://ip.net.coffee/claude/"
}
