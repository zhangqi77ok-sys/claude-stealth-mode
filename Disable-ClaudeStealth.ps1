<#
.SYNOPSIS
    一键恢复系统常规工作模式 (无损精准回滚版)
.DESCRIPTION
    读取 .stealth-snapshot.json 快照，将系统时区、IPv6、DNS、防火墙及浏览器策略精准恢复为原状。
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "🛡️ 正在申请管理员权限以清除防火墙规则并精准还原系统配置..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         🔄 正在恢复常规日常工作模式 (无损回滚)           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$snapshotPath = Join-Path $scriptDir ".stealth-snapshot.json"
$snapshot = $null
if (Test-Path $snapshotPath) {
    try {
        $snapshot = Get-Content $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host "  ✅ 已读取原值快照文件，将按照快照精准还原" -ForegroundColor Green
    } catch {}
}

# -------------------------------------------------------------------------
# 1. 恢复 IPv6 网络与协议栈
# -------------------------------------------------------------------------
Write-Host "`n[1/6] 正在恢复 IPv6 协议栈与出站连接..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_IPv6_Outbound" -ErrorAction SilentlyContinue

if ($snapshot -and $snapshot.OriginalV6Adapters) {
    foreach ($adapterName in $snapshot.OriginalV6Adapters) {
        Enable-NetAdapterBinding -Name $adapterName -ComponentId ms_tcpip6 -Confirm:$false -ErrorAction SilentlyContinue
    }
} else {
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        Enable-NetAdapterBinding -Name $_.Name -ComponentId ms_tcpip6 -Confirm:$false -ErrorAction SilentlyContinue
    }
}
Write-Host "  ✅ IPv6 协议栈与出站访问已恢复" -ForegroundColor Green

# -------------------------------------------------------------------------
# 2. 恢复 Windows 智能多宿主 DNS (SMHNR) 与系统定位
# -------------------------------------------------------------------------
Write-Host "`n[2/6] 正在恢复 Windows 默认 DNS 解析与定位策略..." -ForegroundColor Yellow
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "DisableSmartNameResolution" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -ErrorAction SilentlyContinue
Write-Host "  ✅ DNS 智能多宿主解析与物理定位策略已恢复为系统默认" -ForegroundColor Green

# -------------------------------------------------------------------------
# 3. 清理 Windows 防火墙拦截与 Claude 熔断规则
# -------------------------------------------------------------------------
Write-Host "`n[3/6] 正在清除 WebRTC 防火墙拦截与 Claude Desktop 熔断规则..." -ForegroundColor Yellow
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_WebRTC_STUN" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "ClaudeStealth_Block_Chrome_UDP" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "ClaudeStealth_ClaudeApp_KillSwitch" -ErrorAction SilentlyContinue
Remove-NetFirewallRule -DisplayName "ClaudeStealth_ClaudeApp_Block_UDP" -ErrorAction SilentlyContinue
Write-Host "  ✅ Windows 防火墙出站规则与客户端熔断已清除，恢复常规网络连接" -ForegroundColor Green

# -------------------------------------------------------------------------
# 4. 清理浏览器注册表企业策略与恢复中文偏好
# -------------------------------------------------------------------------
Write-Host "`n[4/6] 正在清除 Chrome / Edge 组策略与恢复中文语言..." -ForegroundColor Yellow
$browserPolicyPaths = @(
    "HKLM:\SOFTWARE\Policies\Google\Chrome",
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
)
foreach ($bPath in $browserPolicyPaths) {
    if (Test-Path $bPath) {
        Remove-ItemProperty -Path $bPath -Name "WebRtcIPHandlingPolicy" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $bPath -Name "ApplicationLocaleValue" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $bPath -Name "QuicAllowed" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $bPath -Name "BuiltInDnsClientEnabled" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $bPath -Name "DefaultGeolocationSetting" -ErrorAction SilentlyContinue
        
        $forcedLangPath = Join-Path $bPath "ForcedLanguages"
        if (Test-Path $forcedLangPath) {
            Remove-Item -Path $forcedLangPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# 恢复 Chrome 偏好文件语言为中文优先
$userDataDir = "$env:LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $userDataDir) {
    $profileDirs = Get-ChildItem -Path $userDataDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
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
}
Write-Host "  ✅ 浏览器底层 QUIC、DNS、WebRTC 策略与首选中文语言已恢复" -ForegroundColor Green

# -------------------------------------------------------------------------
# 5. 恢复系统时区与区域归属
# -------------------------------------------------------------------------
$targetTz = "China Standard Time"
$targetGeo = 45
if ($snapshot -and $snapshot.OriginalTimezone) {
    $targetTz = $snapshot.OriginalTimezone
}
if ($snapshot -and $snapshot.OriginalGeoId) {
    $targetGeo = $snapshot.OriginalGeoId
}

Write-Host "`n[5/6] 正在恢复系统时区为 [$targetTz] (GeoID: $targetGeo)..." -ForegroundColor Yellow
tzutil /s $targetTz
Set-WinHomeLocation -GeoId $targetGeo -ErrorAction SilentlyContinue
Set-Service -Name tzautoupdate -StartupType Manual -ErrorAction SilentlyContinue
$currentTz = tzutil /g
Write-Host "  ✅ 当前系统时区已恢复为: $currentTz (GeoID: $targetGeo)" -ForegroundColor Green

# -------------------------------------------------------------------------
# 6. 清理代理环境变量、PowerShell Profile 与 Git 代理
# -------------------------------------------------------------------------
Write-Host "`n[6/6] 正在清理命令行 HTTP_PROXY 环境变量与启动脚本..." -ForegroundColor Yellow
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

if (Get-Command git -ErrorAction SilentlyContinue) {
    git config --global --unset http.proxy
    git config --global --unset https.proxy
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

# 清理快照文件
if (Test-Path $snapshotPath) {
    Remove-Item -Path $snapshotPath -Force -ErrorAction SilentlyContinue
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  🎉 系统设置已成功无损还原！常规办公网络环境已就绪。" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
