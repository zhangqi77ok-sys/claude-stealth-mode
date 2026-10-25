<#
.SYNOPSIS
    一键恢复系统常规模式（恢复中国标准时间、中文语言、默认防火墙与网络设置）
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "🛡️ 正在申请管理员权限以清除防火墙规则与恢复系统策略..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         🔄 正在恢复常规日常工作模式 (中国时区/网络)      " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. 清理用户环境变量中的代理设置
Write-Host "`n[1/5] 正在清理命令行 HTTP_PROXY 环境变量..." -ForegroundColor Yellow
[System.Environment]::SetEnvironmentVariable("HTTP_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("ALL_PROXY", $null, "User")
[System.Environment]::SetEnvironmentVariable("NO_PROXY", $null, "User")

Remove-Item Env:\HTTP_PROXY -ErrorAction SilentlyContinue
Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue
Remove-Item Env:\ALL_PROXY -ErrorAction SilentlyContinue
Remove-Item Env:\NO_PROXY -ErrorAction SilentlyContinue

# 清理 PowerShell profile 注入
$psProfileDirs = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\profile.ps1"
)
foreach ($p in $psProfileDirs) {
    if (Test-Path $p) {
        Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "  ✅ PowerShell Profile 代理注入已清除" -ForegroundColor Green

# 清理 Git 代理
if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global --unset http.proxy
    git config --global --unset https.proxy
    Write-Host "  ✅ Git 全局代理已复原" -ForegroundColor Green
}
Write-Host "  ✅ 命令行环境变量已复原" -ForegroundColor Green

# 2. 移除 Windows 防火墙规则
Write-Host "`n[2/5] 正在清除 WebRTC 防火墙拦截规则..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_WebRTC_STUN" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_Chrome_UDP" -ErrorAction SilentlyContinue
Write-Host "  ✅ Windows 防火墙出站规则已清除，恢复常规网络连接" -ForegroundColor Green

# 3. 清理浏览器注册表企业策略
Write-Host "`n[3/5] 正在清除 Chrome / Edge 组策略与语言锁定..." -ForegroundColor Yellow
$browserPolicyPaths = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
)
foreach ($bPath in $browserPolicyPaths) {
    if (Test-Path $bPath) {
        Remove-ItemProperty -Path $bPath -Name "WebRtcIPHandlingPolicy" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $bPath -Name "ApplicationLocaleValue" -ErrorAction SilentlyContinue
        $forcedLangPath = Join-Path $bPath "ForcedLanguages"
        if (Test-Path $forcedLangPath) {
            Remove-Item -Path $forcedLangPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
Write-Host "  ✅ 浏览器底层 WebRTC 与语言强制策略已清除" -ForegroundColor Green

# 恢复 Chrome 偏好文件语言为中文优先
$userDataDir = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $userDataDir) {
    $profileDirs = Get-ChildItem -Path $userDataDir -Directory | Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
    foreach ($pDir in $profileDirs) {
        $prefFile = Join-Path $pDir.FullName "Preferences"
        if (Test-Path $prefFile) {
            try {
                $raw = Get-Content $prefFile -Raw -Encoding UTF8
                $obj = $raw | ConvertFrom-Json
                if ($obj.intl) {
                    $obj.intl.accept_languages = "zh-CN,zh,en-US,en"
                    $obj.intl.selected_languages = "zh-CN,zh"
                }
                if ($obj.webrtc) {
                    $obj.webrtc.ip_handling_policy = "default"
                }
                $obj | ConvertTo-Json -Depth 100 | Set-Content $prefFile -Encoding UTF8
            } catch {}
        }
    }
    Write-Host "  ✅ Chrome 用户偏好语言已恢复为中文优先" -ForegroundColor Green
}

# 4. 恢复系统时区为中国标准时间
Write-Host "`n[4/5] 正在恢复系统时区为 [China Standard Time]..." -ForegroundColor Yellow
tzutil /s "China Standard Time"
Set-WinHomeLocation -GeoId 45 -ErrorAction SilentlyContinue
Set-Service -Name tzautoupdate -StartupType Manual -ErrorAction SilentlyContinue
Write-Host "  ✅ Windows 归属区域已恢复为: 中国 (GeoID 45)" -ForegroundColor Green
Write-Host "  ✅ Windows 自动时区更新已恢复为按需启动" -ForegroundColor Green
$currentTz = tzutil /g
Write-Host "  ✅ 当前系统时区已恢复为: $currentTz" -ForegroundColor Green

# 5. 广播环境变量变更
Write-Host "`n[5/5] 正在广播系统变更..." -ForegroundColor Yellow
try {
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Auto)]
        public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.UIntPtr lpdwResult);
'@
    $result = [System.UIntPtr]::Zero
    [Win32.NativeMethods]::SendMessageTimeout([System.IntPtr]0xffff, 0x001A, [System.UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null
} catch {}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  🎉 所有设置已成功还原为中国正常状态！" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
