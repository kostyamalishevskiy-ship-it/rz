<#
  watchdog.ps1 — SYSTEM, кожні 5 хвилин. Ідемпотентний.
#>
$ErrorActionPreference = 'SilentlyContinue'
$AppDir = $PSScriptRoot
$LogDir = Join-Path $env:ProgramData 'RustDeskZeroTouch'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir 'watchdog.log'
function W([string]$m) { "$(Get-Date -f s)  $m" | Out-File $Log -Append -Encoding ASCII }

# 1. служби
foreach ($name in @('RustDesk', 'mesh agent')) {
    $s = Get-Service -Name $name
    if ($s -and $s.Status -ne 'Running') { Start-Service $name; W "started $name (was $($s.Status))" }
}
& sc.exe failure 'mesh agent' reset= 86400 actions= restart/5000/restart/5000/restart/30000 | Out-Null

# 2. конфіг — якщо RustDesk його перезаписав
$svcCfg = "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml"
$usrCfg = "$env:APPDATA\RustDesk\config\RustDesk.toml"
$params = Join-Path $AppDir 'params.ini'

if ((Test-Path $params) -and (Test-Path (Join-Path $AppDir 'postinstall.ps1'))) {
    $need = $false
    foreach ($f in @($svcCfg, $usrCfg)) {
        if (-not (Test-Path $f)) { $need = $true; continue }
        if (-not (Select-String -Path $f -Pattern '^\s*password\s*=' -Quiet)) { $need = $true }
    }
    if ($need) {
        W 'config missing -> re-apply'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $AppDir 'postinstall.ps1') -Ini $params | Out-Null
        Restart-Service RustDesk -Force
    }
}

# 3. ротація логу
$lines = Get-Content $Log
if ($lines.Count -gt 2000) { $lines | Select-Object -Last 500 | Set-Content $Log -Encoding ASCII }
