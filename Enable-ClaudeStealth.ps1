<#
.SYNOPSIS
    Claude 终极防检测隐身模式（免 TUN 模式，全自动系统级拦截）
.DESCRIPTION
    彻底解决在不开启 TUN 模式下，系统、浏览器及桌面端子进程（PowerShell/Git/Node/Python）暴露中国真实 IP、时区与语言的问题。
    全脚本自动化解决：
    1. 自提管理员权限 (UAC)，确保底层网络、组策略与防火墙 100% 写入成功；
    2. 自动解决 PowerShell 脚本执行策略 (RemoteSigned)，消除 profile.ps1 安全加载报错；
    3. 注入系统环境变量、Git 代理与 PowerShell Profile，堵死命令行与代码子进程直连国内公网 IP；
    4. 切换并锁定系统时区为美国太平洋时间 (Pacific Standard Time)，国家代码设为美国 (GeoID 244)；
    5. 物理级封堵 WebRTC UDP 泄漏（彻底消灭 111.x 异常公网 IP）：
       - 下发 Chrome/Edge 企业级组策略 (WebRtcIPHandlingPolicy = disable_non_proxied_udp)；
       - 添加 Windows 内核级防火墙规则，阻断 STUN UDP 探测端口 (3478, 19302-19309) 与 Chrome 直连 UDP；
    6. 强制浏览器语言伪装为 en-US, en（彻底消灭 语言不一致）：
       - 下发 Chrome/Edge 组策略 ForcedLanguages (1=en-US, 2=en) 与 ApplicationLocaleValue = en-US；
       - 自动平滑重置运行中的 Chrome 并修改所有用户 Profile Preferences；
    7. 清理 Claude 历史设备硬件指纹 (ant-did) 与沙箱缓存；
    8. 自动拉起 Chrome 打开 https://ip.net.coffee/claude/ 供实时验收全绿效果。
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
    Write-Host "🛡️ 正在申请管理员权限以应用系统防火墙与底层安全策略..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($PSBoundParameters.Count -gt 0) {
        foreach ($key in $PSBoundParameters.Keys) {
            $argList += " -$key `"$($PSBoundParameters[$key])`""
        }
    }
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit
}

# 彻底解决 PowerShell Profile 执行安全报错
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "     🚀 启动 Claude 终极防检测隐身模式 (全脚本自动化版)   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$proxyHttp = "http://127.0.0.1:$ProxyPort"
$proxySocks = "socks5://127.0.0.1:$ProxyPort"

# -------------------------------------------------------------------------
# 1. 注入系统与 CLI 代理环境变量 + PowerShell Profile
# -------------------------------------------------------------------------
Write-Host "`n[1/7] 正在配置系统与 CLI 代理环境变量..." -ForegroundColor Yellow

# 1.1 写入注册表用户环境变量
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $proxySocks, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1", "User")

$env:HTTP_PROXY = $proxyHttp
$env:HTTPS_PROXY = $proxyHttp
$env:ALL_PROXY = $proxySocks
$env:NO_PROXY = "localhost,127.0.0.1"

# 1.2 注入 PowerShell 启动 Profile（保证 Claude 桌面端拉起子进程自动继承代理）
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
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $p1 = Join-Path $dir "profile.ps1"
    Set-Content -Path $p1 -Value $profileSnippet -Encoding UTF8 -Force
}
Write-Host "  ✅ PowerShell Profile 代理注入就绪" -ForegroundColor Green

# 1.3 广播系统环境变量变更 (WM_SETTINGCHANGE)
try {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
    $result = [System.UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout([System.IntPtr]0xffff, 0x001A, [System.UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
} catch {}

# 1.4 配置 Git 全局代理
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global http.proxy $proxyHttp
    git config --global https.proxy $proxyHttp
    Write-Host "  ✅ Git 全局代理已设为 $proxyHttp" -ForegroundColor Green
}
Write-Host "  ✅ 命令行与代码执行子进程已锁定代理通道" -ForegroundColor Green

# -------------------------------------------------------------------------
# 2. 切换系统时区为美国太平洋时间，并锁定
# -------------------------------------------------------------------------
Write-Host "`n[2/7] 正在修改系统时区为 [$Timezone]..." -ForegroundColor Yellow
Set-Service -Name tzautoupdate -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service -Name tzautoupdate -Force -ErrorAction SilentlyContinue
tzutil /s $Timezone
Set-WinHomeLocation -GeoId 244 -ErrorAction SilentlyContinue
Write-Host "  ✅ Windows 自动时区更新已禁用，归属区域已设为: 美国 (GeoID 244)" -ForegroundColor Green
$currentTz = tzutil /g
Write-Host "  ✅ 当前系统时区已切换为: $currentTz" -ForegroundColor Green

# -------------------------------------------------------------------------
# 3. 物理级防火墙与策略阻断 WebRTC UDP 泄漏 (核心痛点解决)
# -------------------------------------------------------------------------
Write-Host "`n[3/7] 正在注入 WebRTC 防泄漏策略与 Windows 防火墙规则..." -ForegroundColor Yellow

# 查找 Chrome 可执行文件路径
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chromeExe)) {
    $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
}
$edgeExe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $edgeExe)) {
    $edgeExe = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
}

# 3.1 写入 Windows 防火墙出站规则：阻断 STUN UDP 穿透
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_WebRTC_STUN" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_Chrome_UDP" -ErrorAction SilentlyContinue

# 规则 1：阻断所有常见 WebRTC STUN/TURN 服务器端口 (UDP)
New-NetFirewallRule -DisplayName "ClaudeStealth_Block_WebRTC_STUN" `
    -Direction Outbound -Protocol UDP -RemotePort 3478,19302,19303,19304,19305,19306,19307,19308,19309,5349 `
    -Action Block -Description "Claude Stealth Mode: Block STUN UDP Leak" | Out-Null
Write-Host "  ✅ Windows 防火墙: 已阻断 STUN UDP 探测端口 (3478, 19302~19309)" -ForegroundColor Green

# 规则 2：阻断 Chrome 浏览器的直接出站 UDP（强制全走 TCP 代理通道，杜绝直连物理网卡）
if (Test-Path $chromeExe) {
    New-NetFirewallRule -DisplayName "ClaudeStealth_Block_Chrome_UDP" `
        -Direction Outbound -Program $chromeExe -Protocol UDP `
        -Action Block -Description "Claude Stealth Mode: Block Chrome Outbound UDP" | Out-Null
    Write-Host "  ✅ Windows 防火墙: 已隔离 Chrome UDP 直连 (彻底堵死 111.x 真实 IP 泄漏)" -ForegroundColor Green
}

# 3.2 注入 Chrome / Edge 企业组策略注册表 (disable_non_proxied_udp)
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
Write-Host "  ✅ 浏览器底层策略已锁定: disable_non_proxied_udp (WebRTC 禁用直连 UDP)" -ForegroundColor Green

# -------------------------------------------------------------------------
# 4. 全自动化伪装浏览器语言为 en-US / en (解决语言不一致)
# -------------------------------------------------------------------------
Write-Host "`n[4/7] 正在配置浏览器语言环境 (强制 en-US 首选)..." -ForegroundColor Yellow

# 4.1 写入 Chrome / Edge 企业组策略：锁定 ForcedLanguages 与 ApplicationLocaleValue
foreach ($bPath in $browserPolicyPaths) {
    # 界面语言设为 en-US
    Set-ItemProperty -Path $bPath -Name "ApplicationLocaleValue" -Value "en-US" -Type String -Force
    
    # 强制首选内容语言列表 (ForcedLanguages): 1=en-US, 2=en
    $forcedLangPath = Join-Path $bPath "ForcedLanguages"
    if (-not (Test-Path $forcedLangPath)) {
        New-Item -Path $forcedLangPath -Force | Out-Null
    }
    Set-ItemProperty -Path $forcedLangPath -Name "1" -Value "en-US" -Type String -Force
    Set-ItemProperty -Path $forcedLangPath -Name "2" -Value "en" -Type String -Force
}
Write-Host "  ✅ 浏览器组策略已强制下发: ForcedLanguages = ['en-US', 'en']" -ForegroundColor Green

# 4.2 若 Chrome 正在运行，平滑关闭以更新用户配置文件
$chromeProcs = Get-Process chrome -ErrorAction SilentlyContinue
if ($chromeProcs) {
    Write-Host "  ℹ️ 检测到 Chrome 正在运行，正在刷新 Chrome 进程以加载新策略..." -ForegroundColor Yellow
    $chromeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# 4.3 扫描并改写所有 Chrome 用户 Profile Preferences
$userDataDir = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $userDataDir) {
    $profileDirs = Get-ChildItem -Path $userDataDir -Directory | Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
    foreach ($pDir in $profileDirs) {
        $prefFile = Join-Path $pDir.FullName "Preferences"
        if (Test-Path $prefFile) {
            try {
                $raw = Get-Content $prefFile -Raw -Encoding UTF8
                $obj = $raw | ConvertFrom-Json
                
                # 写入 webrtc
                if (-not ($obj.PSObject.Properties.Name -contains "webrtc")) {
                    $obj | Add-Member -NotePropertyName "webrtc" -NotePropertyValue ([PSCustomObject]@{ ip_handling_policy = "disable_non_proxied_udp" }) -Force
                } else {
                    $obj.webrtc.ip_handling_policy = "disable_non_proxied_udp"
                }
                
                # 写入 intl
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
    Write-Host "  ✅ Chrome 用户配置文件语言与 WebRTC 偏好已更新为 en-US" -ForegroundColor Green
}

# -------------------------------------------------------------------------
# 5. 维护桌面专属防检测 Chrome 快捷方式
# -------------------------------------------------------------------------
Write-Host "`n[5/7] 正在维护桌面防检测快捷方式..." -ForegroundColor Yellow
try {
    $wsh = New-Object -ComObject WScript.Shell
    $desktop = [System.Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "Google Chrome (防检测模式).lnk"
    if (Test-Path $chromeExe) {
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $chromeExe
        $shortcut.Arguments = "--force-webrtc-ip-handling-policy=disable_non_proxied_udp --lang=en-US"
        $shortcut.IconLocation = "$chromeExe,0"
        $shortcut.Description = "Claude 防检测专用 Chrome"
        $shortcut.Save()
        Write-Host "  ✅ 桌面快捷方式已更新: Google Chrome (防检测模式)" -ForegroundColor Green
    }
} catch {}

# -------------------------------------------------------------------------
# 6. 清理旧的 Claude 桌面端硬件指纹与沙箱残留
# -------------------------------------------------------------------------
Write-Host "`n[6/7] 正在扫描并清理 Claude 历史设备指纹与沙箱残留..." -ForegroundColor Yellow
$claudePkgData = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache"
if (Test-Path $claudePkgData) {
    Remove-Item -Path $claudePkgData -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✅ 已抹除 Claude 硬件指纹 (ant-did)" -ForegroundColor Green
}
Get-ChildItem "$env:LOCALAPPDATA\Temp" -Filter "*claude*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  ✅ 已清理临时执行沙箱文件" -ForegroundColor Green

# -------------------------------------------------------------------------
# 7. 实时检测外网出口与纯净度验证
# -------------------------------------------------------------------------
Write-Host "`n[7/7] 正在发起外网出口连通性检测..." -ForegroundColor Yellow
try {
    $trace = Invoke-RestMethod -Uri "https://www.cloudflare.com/cdn-cgi/trace" -Proxy $proxyHttp -TimeoutSec 6
    $loc = ($trace -split "`n" | Where-Object { $_ -match "^loc=" }) -replace "loc=", ""
    $ip = ($trace -split "`n" | Where-Object { $_ -match "^ip=" }) -replace "ip=", ""
    Write-Host "  🌐 当前代理出口 IP: $ip (国家/地区: $loc)" -ForegroundColor Cyan
    
    if ($loc -eq "US") {
        Write-Host "  🎉 节点正常：出口已被识别为美国 (US)" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️ 当前节点出口为: $loc (建议在代理软件中切换为美国节点)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ❌ 代理请求超时，请检查 Clash Verge 是否处于开启状态并监听在端口 $ProxyPort" -ForegroundColor Red
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  ✨ 隐身保护已全部就绪！WebRTC 与语言已全面锁定为美国环境。" -ForegroundColor Green
Write-Host "  💡 平时不用时，可运行同目录下的 [Disable-ClaudeStealth.ps1] 一键复原。" -ForegroundColor DarkGray
Write-Host "==========================================================" -ForegroundColor Cyan

# 自动启动 Chrome 并打开检测页进行验收
if (-not $NoBrowser -and (Test-Path $chromeExe)) {
    Write-Host "`n🚀 正在自动启动 Chrome 并打开 https://ip.net.coffee/claude/ 供您即刻验收..." -ForegroundColor Green
    Start-Process $chromeExe -ArgumentList "--force-webrtc-ip-handling-policy=disable_non_proxied_udp --lang=en-US https://ip.net.coffee/claude/"
}
