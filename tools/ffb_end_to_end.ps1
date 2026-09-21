<#
    End-to-end: das echte Spiel gegen den echten Helfer.

    Die anderen Pruefungen decken je eine Haelfte ab:
      * tests/test_ffb_link.gd    - das Spiel sendet (mit eigenem Empfaenger)
      * g29_ffb.py --dry-run      - der Helfer liest (mit synthetischem Sender)

    Hier laufen beide zusammen: der Helfer horcht auf einem eigenen Port,
    danach faehrt das Spiel headless eine echte Runde. Geprueft wird, was der
    Helfer - derselbe Code wie im Betrieb - vom Spiel wirklich gesehen hat:
    Pakete, Kraft im Bogen, Ruetteln, Ereignisse, Herkunft, Wertebereiche.

    Zwei Laeufe, weil die Einstellungen des Fahrers dabei nichts angehen:
      1. FFB AN  (eigene Datei)  -> die Kraft muss ankommen
      2. FFB AUS (eigene Datei)  -> es darf keine Kraft ankommen
    Der zweite Lauf ist der Beweis, dass der Schalter im Menue wirklich bis
    ans Lenkrad durchschlaegt - und nicht nur die Anzeige umstellt.

    Frueher las dieser Lauf die echten `user://ffb_settings.json` des Fahrers.
    Stand dort "FFB AUS" (ein Prueflauf hatte die Datei ueberschrieben),
    meldete der Test "die Kraft im Bogen kommt an FAIL" - obwohl die Kette in
    Ordnung war. Mit `APEX_FFB_SETTINGS` bringt jeder Lauf seine eigene Datei
    mit.

    Kein Lenkrad noetig. Fuer den Fuehltest am Rad gibt es --demo.

        powershell -File tools/ffb_end_to_end.ps1
        powershell -File tools/ffb_end_to_end.ps1 -GameScript tests/probe_ffb.gd
#>
param(
    [int]$Port = 5621,
    [string]$GameScript = "tests/probe_ffb.gd",
    [int]$SettleSeconds = 3
)

$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python -ErrorAction Stop).Source
$logPath = Join-Path $project "tools\ffb_e2e.log"
$errPath = Join-Path $project "tools\ffb_e2e.err"
# Godot loest `user://` in seinem eigenen Datenordner auf - dort muss die
# Datei liegen, die der Lauf ueber APEX_FFB_SETTINGS mitbringt.
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\Apex Circuit"
$settingsQuoted = "user://ffb_e2e_settings.json"

## Alte Helfer und Spiele aufraeumen, bevor gemessen wird. Gemessen am
## 21.09.2026 blieben aus frueheren Laeufen sowohl ein headless Spiel als auch
## ein Helfer als Waise stehen; der Helfer hielt dabei seine Logdatei und das
## Lenkrad, das Spiel sperrte die ausgelieferte .exe (der naechste Export
## scheiterte mit einem nackten IOException). Eine Messung neben einem alten
## Prozess ist keine Messung.
## Aber nicht blind: laeuft gerade ein anderer Prueflauf, gehoeren Spiel und
## Helfer zu IHM. Werden sie hier erschlagen, messen beide Laeufe nichts
## (gemessen am 21.09.2026: zwei parallele Laeufe nahmen sich gegenseitig
## Helfer und Spiel weg). Prozesse, die vor weniger als 5 Minuten gestartet
## wurden, gelten als "laufender Lauf" - dann bricht dieses Skript mit Exit 125
## ab, statt zu toeten. Alte Waisen werden wie bisher aufgeraeumt.
$staleGames = @(Get-CimInstance Win32_Process -Filter "Name like '%Apex%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*Apex Circuit.exe*' -or $_.CommandLine -like '*ApexCircuit.exe*' })
if ($staleGames.Count -gt 0) {
    $young = @($staleGames | Where-Object {
            $_.CreationDate -and ((Get-Date) - $_.CreationDate).TotalSeconds -lt 300 })
    if ($young.Count -gt 0) {
        $ids = ($young | ForEach-Object { "$($_.ProcessId)" }) -join ', '
        Write-Host (("[e2e] ABBRUCH: es laeuft schon ein Spiel (PID {0}, gestartet " +
            "vor weniger als 5 Minuten) - parallele Laeufe messen sich gegenseitig " +
            "kaputt. Bitte warten oder spaeter starten.") -f $ids)
        exit 125
    }
}
foreach ($g in $staleGames) {
    Write-Host ("[e2e] Beende altes Spiel (Waise): PID {0}" -f $g.ProcessId)
    Stop-Process -Id $g.ProcessId -Force -ErrorAction SilentlyContinue
}
$staleHelpers = @(Get-CimInstance Win32_Process -Filter "Name like '%python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*g29_ffb.py*' })
if ($staleHelpers.Count -gt 0) {
    $youngHelpers = @($staleHelpers | Where-Object {
            $_.CreationDate -and ((Get-Date) - $_.CreationDate).TotalSeconds -lt 300 })
    if ($youngHelpers.Count -gt 0) {
        $ids = ($youngHelpers | ForEach-Object { "$($_.ProcessId)" }) -join ', '
        Write-Host (("[e2e] ABBRUCH: es laeuft schon ein Helfer (PID {0}, gestartet " +
            "vor weniger als 5 Minuten) - parallele Laeufe messen sich gegenseitig " +
            "kaputt. Bitte warten oder spaeter starten.") -f $ids)
        exit 125
    }
}
foreach ($h in $staleHelpers) {
    Write-Host ("[e2e] Beende alten Helfer (Waise): PID {0}" -f $h.ProcessId)
    Stop-Process -Id $h.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($staleGames.Count -gt 0 -or $staleHelpers.Count -gt 0) { Start-Sleep -Milliseconds 800 }
$settingsPath = Join-Path $userDir "ffb_e2e_settings.json"

function Write-Settings([bool]$enabled) {
    if (-not (Test-Path -LiteralPath $userDir)) {
        New-Item -ItemType Directory -Path $userDir -Force | Out-Null
    }
    $state = if ($enabled) { "true" } else { "false" }
    $json = '{"version":1,"enabled":' + $state + ',"gain":0.75,"damper":0.7,' +
        '"effects":true,"ontrack_effects":1.0,"kerb_effects":1.0,' +
        '"offtrack_effects":1.0,"invert":false,"rotation_deg":400.0}'
    Set-Content -LiteralPath $settingsPath -Value $json -Encoding ascii -NoNewline
}

# Ein Lauf: Helfer starten, Spiel fahren lassen, Helfer stoppen, Log auswerten.
function Invoke-Run([bool]$FfbOn) {
    foreach ($p in @($logPath, $errPath)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    Write-Settings $FfbOn
    $label = if ($FfbOn) { "FFB AN" } else { "FFB AUS" }
    Write-Host "[e2e] Lauf: $label (Einstellungen: $settingsQuoted)"

    # Start-Process zerlegt ArgumentList selbst; der Projektpfad enthaelt ein
    # Leerzeichen ("Mark Waldeis"), also muss der Skriptpfad gequotet sein.
    # `-u` ist Pflicht: in eine Datei umgeleitet puffert Python sonst, und die
    # Zeile "hoert auf" erscheint erst, wenn der Puffer voll ist - der
    # Wartetest unten lief dann in den Timeout, obwohl der Helfer laengst
    # horchte.
    $helperArgs = "-u `"$project\tools\g29_ffb.py`" --dry-run --dry-run-seconds 0 " +
        "--verbose --port $Port"
    $helper = Start-Process -FilePath $python -ArgumentList $helperArgs `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $logPath -RedirectStandardError $errPath

    try {
        $deadline = (Get-Date).AddSeconds(20)
        $listening = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 300
            if ((Test-Path -LiteralPath $logPath) -and
                (Select-String -Path $logPath -Pattern 'hoert auf' -Quiet)) {
                $listening = $true
                break
            }
            if ($helper.HasExited) { break }
        }
        if (-not $listening) {
            Write-Host "[e2e] FAIL: der Helfer horcht nicht. Log:"
            Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue | Select-Object -Last 20
            Get-Content -LiteralPath $errPath -ErrorAction SilentlyContinue | Select-Object -Last 20
            exit 1
        }

        Start-Sleep -Seconds $SettleSeconds
        $env:APEX_FFB_PORT = "$Port"
        $env:APEX_FFB_SETTINGS = $settingsQuoted
        & powershell -File "$PSScriptRoot\run_godot.ps1" --headless --path godot_f1 --script $GameScript 2>&1 |
            Select-String -Pattern 'FFB_MESSUNG|FFB_PROBE|Runde|Clipping|Kraft in der Runde' |
            ForEach-Object { Write-Host "  [spiel] $($_.Line)" }
        $script:gameExit = $LASTEXITCODE
        Remove-Item Env:\APEX_FFB_PORT -ErrorAction SilentlyContinue
        Remove-Item Env:\APEX_FFB_SETTINGS -ErrorAction SilentlyContinue
    } finally {
        Start-Sleep -Milliseconds 800
        if (-not $helper.HasExited) { Stop-Process -Id $helper.Id -Force }
    }

    $stats = [pscustomobject]@{
        packets = 0; peakTorque = 0.0; peakRumble = 0.0; maxHz = 0.0
        sources = @{}; events = @{}; maxSpeed = 0.0; clipMax = 0.0; overOne = 0
        helperLines = 0
    }
    foreach ($line in @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\[ffb\] ' })) {
        $stats.helperLines++
        if ($line -match '^\[ffb\] (\d+) Pakete, torque=([+-][\d.]+) .* rumble=([\d.]+)@([\d.]+)Hz .* Quelle=(\S+) Clip=([\d]+)% Ereignis=(\S+) Tempo=([\d]+)km/h') {
            $stats.packets = [int]$Matches[1]
            $torque = [math]::Abs([double]$Matches[2])
            if ($torque -gt $stats.peakTorque) { $stats.peakTorque = $torque }
            $rumble = [double]$Matches[3]
            if ($rumble -gt $stats.peakRumble) { $stats.peakRumble = $rumble }
            $hz = [double]$Matches[4]
            if ($hz -gt $stats.maxHz) { $stats.maxHz = $hz }
            $src = $Matches[5]
            if ($src -and $src -ne '-') { $stats.sources[$src] = 1 }
            $ev = $Matches[7]
            if ($ev -and $ev -ne '-') { $stats.events[$ev] = 1 }
            $speed = [double]$Matches[8]
            if ($speed -gt $stats.maxSpeed) { $stats.maxSpeed = $speed }
            $clip = [double]$Matches[6]
            if ($clip -gt $stats.clipMax) { $stats.clipMax = $clip }
            if ($torque -gt 1.0) { $stats.overOne++ }
        }
    }
    # Die echten Spitzen aus jedem Sample des Helfer-Loops (200 Hz). Die
    # `[ffb]`-Zeilen oben erscheinen nur alle 2 s - ein Kurvenscheitel mit
    # 3,5 g haelt rund eine Sekunde und fiel dabei schon durchs Raster
    # (derselbe Lauf meldete einmal 0.560, einmal 0.250). Was hier steht, ist
    # das Maximum ueber den ganzen Lauf, nicht eine Stichprobe.
    $peakSeen = $false
    foreach ($line in @(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^\[ffb-peak\] ' })) {
        $peakSeen = $true
        if ($line -match '^\[ffb-peak\] torque=([\d.]+) rumble=([\d.]+) hz=([\d.]+) over=(\d+) packets=(\d+) speed=([\d.]+) clip=([\d.]+)') {
            $t = [double]$Matches[1]
            if ($t -gt $stats.peakTorque) { $stats.peakTorque = $t }
            $r = [double]$Matches[2]
            if ($r -gt $stats.peakRumble) { $stats.peakRumble = $r }
            $h = [double]$Matches[3]
            if ($h -gt $stats.maxHz) { $stats.maxHz = $h }
            $stats.overOne = [int]$Matches[4]
            $p = [int]$Matches[5]
            if ($p -gt $stats.packets) { $stats.packets = $p }
            $s = [double]$Matches[6]
            if ($s -gt $stats.maxSpeed) { $stats.maxSpeed = $s }
            $c = [double]$Matches[7]
            if ($c -gt $stats.clipMax) { $stats.clipMax = $c }
        }
    }
    $stats | Add-Member -NotePropertyName peakLineSeen -NotePropertyValue $peakSeen -Force
    return $stats
}

Write-Host "==== Ende-zu-Ende: Spiel -> Helfer (das Rad selbst braucht Netzteil) ===="
Write-Host "[e2e] Port $Port, Spiel-Skript $GameScript"

$on = Invoke-Run $true
$off = Invoke-Run $false

$checks = @()
function Add-Check($ok, $label, $detail) {
    $script:checks += [pscustomobject]@{ ok = $ok; label = $label; detail = $detail }
}

Add-Check ($on.packets -ge 300) "der Helfer sieht die Pakete des Spiels" "$($on.packets) Pakete"
# Ohne diese Zeile kaeme die Kraft wieder nur aus 2-s-Stichproben - und ein
# kurzer Kurvenscheitel koennte zufaellig fehlen.
Add-Check ($on.peakLineSeen) "der Helfer meldet die echten Spitzen" "Zeile [ffb-peak] im Log"
Add-Check ($on.peakTorque -ge 0.30) "die Kraft im Bogen kommt an" ("Spitze {0:N3}" -f $on.peakTorque)
Add-Check ($on.peakRumble -ge 0.30) "das Ruetteln kommt an" ("Spitze {0:N3}@{1:N1}Hz" -f $on.peakRumble, $on.maxHz)
Add-Check ($on.sources.Count -ge 1) "die Herkunft kommt an" (($on.sources.Keys | Sort-Object) -join ', ')
Add-Check ($on.events.Count -ge 1) "Ereignisse kommen an" (($on.events.Keys | Sort-Object) -join ', ')
Add-Check ($on.overOne -eq 0) "kein Wert ueber 1.0" "$($on.overOne) Ausreisser"
Add-Check ($on.maxSpeed -ge 60) "das Spiel hat wirklich gefahren" ("bis {0:N0} km/h" -f $on.maxSpeed)
# Der Schalter im Menue muss am Lenkrad ankommen, nicht nur in der Anzeige.
Add-Check ($off.packets -ge 300) "auch mit FFB AUS kommen Pakete" "$($off.packets) Pakete"
Add-Check ($off.peakTorque -le 0.001 -and $off.peakRumble -le 0.001) `
    "der Schalter im Menue kommt am Lenkrad an" `
    ("FFB AUS -> Kraft {0:N3}, Ruetteln {1:N3}" -f $off.peakTorque, $off.peakRumble)

Write-Host ""
Write-Host "[e2e] Helfer-Meldungen: AN $($on.helperLines) / AUS $($off.helperLines) (je $SettleSeconds s), Spiel-Exit $gameExit"
$failed = 0
foreach ($c in $checks) {
    if (-not $c.ok) { $failed++ }
    Write-Host ("{0} {1} {2}" -f $(if ($c.ok) { 'PASS' } else { 'FAIL' }), $c.label, $c.detail)
}

if ($failed -gt 0 -or $on.helperLines -eq 0) {
    Write-Host "[e2e] Log: $logPath"
    Write-Host "E2E_RESULT FAIL $failed von $($checks.Count) Pruefungen"
    exit 1
}
Write-Host "E2E_RESULT PASS $($checks.Count) Pruefungen, 0 Mangel"
exit 0
