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
# 1. 注入用户级环境变量 + PowerShell Profile：彻底堵死桌面端代码子进程的裸连泄露
# -------------------------------------------------------------------------
Write-Host "`n[1/6] 正在配置系统与 CLI 代理环境变量..." -ForegroundColor Yellow

# 1.1 写入注册表用户环境变量
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyHttp, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $proxySocks, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", "localhost,127.0.0.1", "User")

$env:HTTP_PROXY = $proxyHttp
$env:HTTPS_PROXY = $proxyHttp
$env:ALL_PROXY = $proxySocks
$env:NO_PROXY = "localhost,127.0.0.1"

# 1.2 注入 PowerShell / Windows PowerShell 启动 Profile（保证 Claude 桌面端拉起 powershell.exe 时百分之百带代理）
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
Write-Host "  ✅ PowerShell 自动加载 Profile 已注入 (彻底保障桌面端写代码)" -ForegroundColor Green

# 1.3 广播系统环境变量变更 (WM_SETTINGCHANGE)，通知新开软件即刻生效
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
Write-Host "  ✅ 命令行与子进程代理已生效 (HTTP_PROXY / HTTPS_PROXY = $proxyHttp)" -ForegroundColor Green

# -------------------------------------------------------------------------
# 2. 切换系统时区为美国太平洋时间，并锁定
# -------------------------------------------------------------------------
Write-Host "`n[2/6] 正在修改系统时区为 [$Timezone]..." -ForegroundColor Yellow
Set-Service -Name tzautoupdate -StartupType Disabled
Stop-Service -Name tzautoupdate -Force
tzutil /s $Timezone
Set-WinHomeLocation -GeoId 244
Write-Host "  ✅ Windows 自动时区更新已禁用，归属区域已设为: 美国 (GeoID 244)" -ForegroundColor Green
$currentTz = tzutil /g
Write-Host "  ✅ 当前系统时区已切换为: $currentTz" -ForegroundColor Green

# -------------------------------------------------------------------------
# 3. 封堵 Chrome 浏览器的 WebRTC 真实 IP 泄漏与语言
# -------------------------------------------------------------------------
Write-Host "`n[3/6] 正在配置 Chrome 浏览器 WebRTC 防泄漏策略与语言..." -ForegroundColor Yellow
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
}

# 检测 WebRTC Control 扩展安装状态
$webrtcExt = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions\fjkmabmdepjfammlpliljpnbhleegehm"
if (Test-Path $webrtcExt) {
    Write-Host "  ✅ 检测到 WebRTC Control 插件已就绪 (内存级 UDP 拦截正常)" -ForegroundColor Green
} else {
    Write-Host "  ℹ️ 建议安装 WebRTC Control 扩展以实现 100% 内存级防泄露" -ForegroundColor DarkGray
}

# -------------------------------------------------------------------------
# 4. 维护桌面专属防检测 Chrome 快捷方式
# -------------------------------------------------------------------------
Write-Host "`n[4/6] 正在维护桌面防检测快捷方式..." -ForegroundColor Yellow
try {
    $wsh = New-Object -ComObject WScript.Shell
    $desktop = [System.Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktop "Google Chrome (防检测无痕).lnk"
    $chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    if (-not (Test-Path $chromeExe)) {
        $chromeExe = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    }
    if (Test-Path $chromeExe) {
        $shortcut = $wsh.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $chromeExe
        $shortcut.Arguments = "--force-webrtc-ip-handling-policy=disable_non_proxied_udp --lang=en-US --incognito"
        $shortcut.IconLocation = "$chromeExe,0"
        $shortcut.Description = "Claude 防检测专用 Chrome"
        $shortcut.Save()
        Write-Host "  ✅ 桌面快捷方式已更新: Google Chrome (防检测无痕)" -ForegroundColor Green
    }
} catch {}

# -------------------------------------------------------------------------
# 5. 清理旧的 Claude 桌面端硬件指纹与沙箱残留
# -------------------------------------------------------------------------
Write-Host "`n[5/6] 正在扫描并清理 Claude 历史设备指纹与沙箱残留..." -ForegroundColor Yellow
$claudePkgData = "$env:LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\LocalCache"
if (Test-Path $claudePkgData) {
    Remove-Item -Path $claudePkgData -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  ✅ 已抹除 Claude 硬件指纹 (ant-did)" -ForegroundColor Green
}
Get-ChildItem "$env:LOCALAPPDATA\Temp" -Filter "*claude*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  ✅ 已清理临时执行沙箱文件" -ForegroundColor Green

# -------------------------------------------------------------------------
# 6. 实时检测外网出口与纯净度验证
# -------------------------------------------------------------------------
Write-Host "`n[6/6] 正在发起外网出口连通性与泄漏检测..." -ForegroundColor Yellow
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

