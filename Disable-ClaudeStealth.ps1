<#
.SYNOPSIS
    一键恢复系统常规模式（恢复中国标准时间与默认网络设置）
#>

$ErrorActionPreference = "SilentlyContinue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "         🔄 正在恢复常规日常工作模式 (中国时区)           " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. 清理用户环境变量中的代理设置
Write-Host "`n[1/4] 正在清理命令行 HTTP_PROXY 环境变量..." -ForegroundColor Yellow
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

# 2. 恢复系统时区为中国标准时间
Write-Host "`n[2/4] 正在恢复系统时区为 [China Standard Time]..." -ForegroundColor Yellow
tzutil /s "China Standard Time"
Set-WinHomeLocation -GeoId 45
Write-Host "  ✅ Windows 归属区域已恢复为: 中国 (GeoID 45)" -ForegroundColor Green
$currentTz = tzutil /g
Write-Host "  ✅ 当前系统时区已恢复为: $currentTz" -ForegroundColor Green

# 3. 恢复 Chrome 语言为中文优先（如果需要）
Write-Host "`n[3/4] 正在恢复 Chrome 首选语言..." -ForegroundColor Yellow
$chromePrefPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Preferences"
if (Test-Path $chromePrefPath) {
    try {
        $raw = Get-Content $chromePrefPath -Raw -Encoding UTF8
        $obj = $raw | ConvertFrom-Json
        $obj.intl.accept_languages = "zh-CN,zh,en-US,en"
        $obj.intl.selected_languages = "zh-CN,zh"
        $obj | ConvertTo-Json -Depth 100 | Set-Content $chromePrefPath -Encoding UTF8
        Write-Host "  ✅ Chrome 语言已恢复为中文优先" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Chrome Preferences 未能修改（请在浏览器手动调整）" -ForegroundColor DarkGray
    }
}

# 4. 广播环境变量变更
Write-Host "`n[4/4] 正在广播系统变更..." -ForegroundColor Yellow
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

