<#
  postinstall.ps1 — усе, що робить систему zero-touch.
  Запускається Inno Setup від імені адміністратора, тихо.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Ini)

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$AppDir = $PSScriptRoot
$LogDir = Join-Path $env:ProgramData 'RustDeskZeroTouch'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir 'postinstall.log'

function W([string]$m) { "$(Get-Date -f s)  $m" | Out-File $Log -Append -Encoding ASCII }
function WriteNoBom([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

# ---------- параметри ----------
$cfg = (Get-Content $Ini -Raw) -replace '^\uFEFF', ''
$P = @{}
foreach ($line in ($cfg -split "`r?`n")) {
    if ($line -match '^\s*([^=\s]+)\s*=\s*(.*)$') { $P[$Matches[1].ToLower()] = $Matches[2].Trim() }
}
$Password   = $P['password']
$Server     = $P['server']
$Key        = $P['key']
$MeshDomain = $P['meshdomain']
$MeshId     = $P['meshid']
$Ntfy       = $P['ntfytopic']
$TgToken    = $P['tgtoken']
$TgChat     = $P['tgchat']

W "start: flavor=$($P['flavor']) server='$Server'"

# зберігаємо параметри машинно-широко — щоб watchdog міг їх перечитати
try { Copy-Item $Ini (Join-Path $AppDir 'params.ini') -Force } catch { W "params.ini FAIL: $($_.Exception.Message)" }

$RustDesk = Join-Path ${env:ProgramFiles} 'RustDesk\rustdesk.exe'
if (-not (Test-Path $RustDesk)) { $RustDesk = 'C:\Program Files\RustDesk\rustdesk.exe' }

# ---------- 1. зупинити службу ----------
$svc = Get-Service -Name 'RustDesk' -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') { Stop-Service 'RustDesk' -Force; Start-Sleep 3; W 'service stopped' }

# ---------- 2. зібрати конфіг ----------
function Render([string]$tplPath) {
    $t = Get-Content $tplPath -Raw
    $t = $t.Replace('__PASSWORD__', $Password).Replace('__SERVER__', $Server).Replace('__KEY__', $Key)
    if (-not $Server) {
        $t = ($t -split "`r?`n" | Where-Object {
            $_ -notmatch "^\s*(custom-rendezvous-server|relay-server|key|rendezvous_server)\s*=\s*''\s*$"
        }) -join "`r`n"
    }
    return $t
}
$toml2 = Render (Join-Path $AppDir 'config\RustDesk2.toml.tmpl')
$toml1 = Render (Join-Path $AppDir 'config\RustDesk.toml.tmpl')

# ---------- 3. ТРИ профілі + усі користувачі ----------
$targets = @(
    (Join-Path $env:APPDATA 'RustDesk\config'),
    "$env:SystemRoot\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config",
    "$env:SystemRoot\System32\config\systemprofile\AppData\Roaming\RustDesk\config"
)
Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $targets += (Join-Path $_.FullName 'AppData\Roaming\RustDesk\config')
}

foreach ($dir in ($targets | Select-Object -Unique)) {
    try {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        WriteNoBom (Join-Path $dir 'RustDesk2.toml') $toml2
        WriteNoBom (Join-Path $dir 'RustDesk.toml')  $toml1
        & icacls.exe $dir /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-19:(OI)(CI)F' /T /C *> $null
        W "config -> $dir"
    } catch { W "FAIL config -> $dir : $($_.Exception.Message)" }
}

# ---------- 4. служба: авто-старт + авто-рестарт ----------
& sc.exe config RustDesk start= auto *> $null
& sc.exe failure RustDesk reset= 86400 actions= restart/5000/restart/5000/restart/30000 *> $null
Start-Service RustDesk -ErrorAction SilentlyContinue
Start-Sleep 5
W "service: $((Get-Service RustDesk -ErrorAction SilentlyContinue).Status)"

# ---------- 5. watchdog ----------
try {
    $wd  = Join-Path $AppDir 'watchdog.ps1'
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$wd`""
    $trg = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $set = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    $prn = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'RustDeskZeroTouchWatchdog' -Action $act -Trigger $trg `
        -Settings $set -Principal $prn -Force | Out-Null
    W 'watchdog registered'
} catch { W "watchdog FAIL: $($_.Exception.Message)" }

# ---------- 6. MeshCentral (не обов'язково) ----------
if ($MeshDomain -and $MeshId) {
    try {
        $tmp = Join-Path $env:TEMP 'meshagent.exe'
        Invoke-WebRequest "https://$MeshDomain/meshagents?id=4&meshid=$MeshId" -OutFile $tmp -UseBasicParsing
        Start-Process $tmp -ArgumentList '-fullinstall' -Wait -WindowStyle Hidden
        W "mesh agent: $((Get-Service 'mesh agent' -ErrorAction SilentlyContinue).Status)"
    } catch { W "mesh agent FAIL: $($_.Exception.Message)" }
}

# ---------- 7. чекін ----------
function CheckIn([string]$text) {
    if ($Ntfy) {
        try {
            $f = Join-Path $env:TEMP 'rz_checkin.txt'
            $text | Set-Content $f -Encoding ASCII
            & curl.exe -sS -X POST -H "Content-Type: text/plain" --data-binary "@$f" "https://ntfy.sh/$Ntfy" | Out-Null
            W 'check-in -> ntfy OK'
        } catch { W "ntfy FAIL: $($_.Exception.Message)" }
    }
    if ($TgToken -and $TgChat) {
        try {
            Invoke-RestMethod "https://api.telegram.org/bot$TgToken/sendMessage" -Method Post `
                -Body @{ chat_id = $TgChat; text = $text } -TimeoutSec 20 | Out-Null
            W 'check-in -> telegram OK'
        } catch { W "tg FAIL: $($_.Exception.Message)" }
    }
}

$id = ''
if (Test-Path $RustDesk) {
    for ($i = 0; $i -lt 20 -and -not $id; $i++) {
        try { $id = (& $RustDesk --get-id 2>$null | Select-Object -First 1).Trim() } catch {}
        if (-not $id) { Start-Sleep 4 }
    }
}
$msg = @"
[RustDesk ZeroTouch] new machine
host  : $env:COMPUTERNAME
user  : $env:USERNAME
id    : $id
server: $(if ($Server) { $Server } else { 'rustdesk-public' })
time  : $(Get-Date -f s)
"@
W $msg
$id | Set-Content (Join-Path $LogDir 'rustdesk_id.txt') -Encoding ASCII
CheckIn $msg

Restart-Service RustDesk -Force -ErrorAction SilentlyContinue
W 'done'
