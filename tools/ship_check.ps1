<#
    Prueft den AUSGELIEFERTEN Build (den Desktop-Start), nicht die Quellen.

    Der Desktop-Start laeuft auf `Apex Circuit.exe` + `.pck`, nicht auf
    `godot_f1/`. Aendert jemand Quellen, ohne neu zu exportieren, spielt der
    Nutzer eine alte Version - genau das war schon einmal der Fall.

    Beweis statt Vermutung: das exportierte Spiel wird headless gestartet, der
    echte Helfer horcht mit. Gemessen wird ein Merkmal, das nur der neue Stand
    hat - `APEX_FFB_SETTINGS` aus `ffb_settings.gd`:

      * Einstellungsdatei mit FFB AN  -> Reibung/Daempfung liegen an
      * Einstellungsdatei mit FFB AUS -> alles ist 0

    Gemessen wird im Stand, denn genau dort ist die Kraft absichtlich 0 (kein
    Nachlauf, keine erfundene Zentrierung). Was im Stand anliegt, sind die
    Koerper-Kanaele: Reibung (0,19 bei stehendem Rad) und Daempfung. Ein alter
    Build kennt die Variable nicht und liefert in beiden Faellen dieselben
    Zahlen; damit ist "der Build enthaelt den neuen Code" gemessen und nicht
    aus einem Zeitstempel geschlossen.

        powershell -File tools/ship_check.ps1
#>
param(
    [string]$Exe = "$env:USERPROFILE\Desktop\Apex Circuit\Apex Circuit.exe",
    [int]$Port = 5631,
    [int]$Seconds = 12
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python -ErrorAction Stop).Source
$helper = Join-Path $project "tools\g29_ffb.py"
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\Apex Circuit"
$settingsName = "user://ffb_ship_test.json"
$settingsFile = Join-Path $userDir "ffb_ship_test.json"

if (-not (Test-Path -LiteralPath $Exe)) {
    Write-Host "SHIP FAIL: $Exe fehlt"
    exit 1
}
if (-not (Test-Path -LiteralPath $userDir)) {
    New-Item -ItemType Directory -Path $userDir -Force | Out-Null
}

function Run-Shipped([bool]$enabled, [int]$runPort) {
    $state = if ($enabled) { 'true' } else { 'false' }
    $json = '{"version":1,"enabled":' + $state + ',"gain":0.75,"damper":0.7,' +
        '"effects":true,"ontrack_effects":1.0,"kerb_effects":1.0,' +
        '"offtrack_effects":1.0,"invert":false,"rotation_deg":400.0}'
    Set-Content -LiteralPath $settingsFile -Value $json -Encoding ascii -NoNewline

    $log = Join-Path $env:TEMP "apex_ship_$runPort.log"
    $err = Join-Path $env:TEMP "apex_ship_$runPort.err"
    foreach ($p in @($log, $err)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }

    $helperArgs = "-u `"$helper`" --dry-run --dry-run-seconds 0 --verbose --port $runPort"
    $proc = Start-Process -FilePath $python -ArgumentList $helperArgs -WindowStyle Hidden `
        -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
    Start-Sleep -Seconds 3

    $env:APEX_FFB_PORT = "$runPort"
    $env:APEX_FFB_SETTINGS = $settingsName
    $game = Start-Process -FilePath $Exe -ArgumentList "--headless" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds $Seconds
    if (-not $game.HasExited) { Stop-Process -Id $game.Id -Force }
    Start-Sleep -Milliseconds 900
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    Remove-Item Env:\APEX_FFB_PORT -ErrorAction SilentlyContinue
    Remove-Item Env:\APEX_FFB_SETTINGS -ErrorAction SilentlyContinue

    $peak = 0.0
    $peakFric = 0.0
    $peakDamp = 0.0
    $packets = 0
    $lines = 0
    $lastSource = "-"
    foreach ($l in @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\[ffb\] ' })) {
        $lines++
        if ($l -notmatch '^\[ffb\] (\d+) Pakete') { continue }
        $seen = [int]$Matches[1]
        # Die Zeilen vor dem Spielstart sind der Leerlauf des Helfers (kein
        # Paket, Grundgewicht 0,10/0,05). Sie sagen nichts ueber das Spiel und
        # wuerden die Messung verwaschen - genau das hat den ersten Lauf hier
        # falsch aussehen lassen.
        if ($seen -eq 0) { continue }
        $packets = $seen
        if ($l -match 'torque=([+-][\d.]+)') {
            $t = [math]::Abs([double]$Matches[1])
            if ($t -gt $peak) { $peak = $t }
        }
        if ($l -match 'fric=([\d.]+)') {
            $v = [double]$Matches[1]
            if ($v -gt $peakFric) { $peakFric = $v }
        }
        if ($l -match 'damp=([\d.]+)') {
            $v = [double]$Matches[1]
            if ($v -gt $peakDamp) { $peakDamp = $v }
        }
        if ($l -match 'Quelle=(\S+)') { $lastSource = $Matches[1] }
    }
    return [pscustomobject]@{
        enabled = $enabled; lines = $lines; packets = $packets; peak = $peak
        fric = $peakFric; damp = $peakDamp; source = $lastSource; log = $log
    }
}

Write-Host "==== Ausgelieferter Build: $Exe ===="
Write-Host "[ship] Kraftstufe des Builds wird gemessen (Einstellungen aus $settingsName)"

$on = Run-Shipped $true $Port
$off = Run-Shipped $false ($Port + 1)

Write-Host ""
Write-Host ("[ship] FFB AN : {0} Pakete, Kraft {1:N3}, Reibung {2:N3}, Daempfung {3:N3}" -f `
    $on.packets, $on.peak, $on.fric, $on.damp) + "  Quelle=$($on.source)"
Write-Host ("[ship] FFB AUS: {0} Pakete, Kraft {1:N3}, Reibung {2:N3}, Daempfung {3:N3}" -f `
    $off.packets, $off.peak, $off.fric, $off.damp) + "  Quelle=$($off.source)"

$failed = 0
function Check($ok, $label, $detail) {
    if (-not $ok) { $script:failed++ }
    Write-Host ("{0} {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $label, $detail)
}

Check ($on.packets -ge 300) "der Build sendet FFB-Pakete" "$($on.packets) Pakete"
Check ($on.fric -ge 0.05 -or $on.peak -ge 0.05) "der Build legt im Stand Reibung an" `
    ("Reibung {0:N3}, Kraft {1:N3}" -f $on.fric, $on.peak)
Check ($off.fric -le 0.001 -and $off.peak -le 0.001 -and $off.damp -le 0.001) `
    "der Build kennt APEX_FFB_SETTINGS (neuer Stand)" `
    (("FFB AUS -> Reibung {0:N3}, Kraft {1:N3}, Daempfung {2:N3} " +
      "(ein alter Build haette hier die Werte des AN-Laufs)") -f $off.fric, $off.peak, $off.damp)

if ($failed -gt 0) {
    Write-Host "[ship] Log: $($on.log)"
    Write-Host "SHIP_RESULT FAIL $failed Mangel"
    exit 1
}
Write-Host "SHIP_RESULT PASS 3 Pruefungen, 0 Mangel"
exit 0
