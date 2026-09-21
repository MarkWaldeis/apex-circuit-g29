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

## Der erste Messversuch kann ins Leere greifen. Gemessen am 21.09.2026
## (20:06): ein Lauf meldete "FFB AUS -> Reibung 0,050, Daempfung 0,100" und
## sah damit aus wie ein alter Build - der AUS-Lauf hatte aber nur **38**
## Pakete gesehen, also die ersten Sekunden nach dem Start. Dort stehen noch
## die Vorgabewerte des Modells (Daempfung 0,10, Reibung 0,05), bevor die
## erste echte Physik-Zeile kommt; der naechste Lauf mit demselben Build lieferte
## 427 Pakete und 0,000/0,000. Eine Messung, die nicht stattgefunden hat, ist
## kein Beweis - deshalb: Zeilen unter 120 Paketen zaehlen nicht (das ist die
## Anlaufphase), und ein Lauf mit weniger als 300 Paketen wird wiederholt,
## bevor er als Ergebnis gilt.
$MinPackets = 300
## Der Helfer hat ein **Ruhegewicht** (Daempfung 0,10, Reibung 0,05), damit
## das Lenkrad zwischen zwei Laeufen nicht tot in der Hand liegt
## (`tools/g29_ffb.py`, der `stale`-Zweig). Sobald das Spiel sendet, klingt es
## auf dessen Werte ab - gemessen am 21.09.2026 (20:13) stand in der Zeile bei
## 6 Paketen noch `damp=0.06 fric=0.03`, obwohl der Build in diesem Lauf
## korrekt 0,00 sandte. Die ersten Pakete sind also Uebergang, nicht Ergebnis.
$SettlePackets = 120
$script:strayGames = 0

## Ein Spiel, das den Lauf ueberlebt, ist kein kleiner Schoenheitsfehler:
## gemessen am 21.09.2026 (20:10) blieb ein headless `Apex Circuit.exe` als
## Waise stehen (Elternprozess weg). Folge: `export_windows.cmd` brach danach
## mit einem nackten `Copy-Item IOException` ab, weil die laufende .exe ihre
## eigene Datei sperrt - und jedes weitere Programm, das das Lenkrad oeffnet,
## misst an einem fremden Spiel vorbei. Deshalb wird nach dem Beenden
## nachgesehen, ob der Prozess wirklich weg ist, und laut gemeldet, wenn nicht.
function Stop-RecordedProcess($proc, [string]$label) {
    if ($null -eq $proc) { return $true }
    try {
        if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        Wait-Process -Id $proc.Id -Timeout 5 -ErrorAction SilentlyContinue
    } catch {
        # Prozess war schon weg - genau das ist der Normalfall.
    }
    $still = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    if ($still) {
        Write-Host ("[ship] WARNUNG: {0} {1} laeuft noch - wird ein zweites Mal beendet" -f $label, $proc.Id)
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 700
        $still = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
    }
    if ($still) {
        # Das `-f` gehoert IN die Klammer: aussen bindet PowerShell es an
        # `Write-Host -ForegroundColor` (Abkuerzung) und bricht genau dann mit
        # "Cannot convert value ... to type System.ConsoleColor" ab, wenn die
        # Meldung helfen soll. Dieselbe Falle war schon im Fehlerpfad von
        # tools/export_and_deliver.ps1 (behoben am 21.09.2026). Und es muss um
        # die **ganze** zusammengesetzte Zeichenkette stehen: `"a{0}" + "b" -f x`
        # formatiert nur das zweite Stueck und druckt dann "{0}" woertlich
        # (gemessen am 21.09.2026 mit einem nicht beendbaren Prozess).
        Write-Host (("[ship] FAIL: {0} {1} liess sich nicht beenden - weitere " +
            "Messungen und der Export waeren unbrauchbar") -f $label, $proc.Id)
        return $false
    }
    return $true
}

## Ein alter Helfer ist genauso schaedlich wie ein altes Spiel: er haelt das
## Lenkrad und die Logdatei und laesst den naechsten Lauf mit "die Datei wird
## von einem anderen Prozess verwendet" scheitern (gemessen am 21.09.2026,
## 20:12 und 20:24 - zwei Laeufe blieben als Waisen stehen). Vor dem Messen
## wird deshalb aufgeraeumt, und zwar sichtbar.
$leftoverHelpers = @(Get-CimInstance Win32_Process -Filter "Name like '%python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*g29_ffb.py*' })
foreach ($h in $leftoverHelpers) {
    Write-Host ("[ship] Raeume alten Helfer auf: PID {0}" -f $h.ProcessId)
    Stop-Process -Id $h.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($leftoverHelpers.Count -gt 0) { Start-Sleep -Milliseconds 700 }

function Run-Shipped([bool]$enabled, [int]$runPort) {
    $state = if ($enabled) { 'true' } else { 'false' }
    $json = '{"version":1,"enabled":' + $state + ',"gain":0.75,"damper":0.7,' +
        '"effects":true,"ontrack_effects":1.0,"kerb_effects":1.0,' +
        '"offtrack_effects":1.0,"invert":false,"rotation_deg":400.0}'
    Set-Content -LiteralPath $settingsFile -Value $json -Encoding ascii -NoNewline

    $peak = 0.0
    $peakFric = 0.0
    $peakDamp = 0.0
    $packets = 0
    $lines = 0
    $lastSource = "-"

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        # Eigener Dateiname je Versuch: ein liegengelassener Helfer aus einem
        # frueheren Lauf haelt seine Logdatei offen - mit festem Namen brach
        # der naechste Lauf dann mit "wird von einem anderen Prozess
        # verwendet" ab, bevor er ueberhaupt gemessen hatte.
        $stamp = "{0}_{1}" -f (Get-Date -Format 'HHmmss'), $attempt
        $log = Join-Path $env:TEMP "apex_ship_$($runPort)_$stamp.log"
        $err = Join-Path $env:TEMP "apex_ship_$($runPort)_$stamp.err"
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
        if (-not (Stop-RecordedProcess $game "Spiel-Prozess")) { $script:strayGames++ }
        Start-Sleep -Milliseconds 900
        if (-not (Stop-RecordedProcess $proc "Helfer")) { $script:strayGames++ }
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
            # Die Leerlaufzeilen des Helfers gehoeren nicht zum Spiel: sobald
            # kein Paket mehr kommt (Spiel beendet), faellt die Kraft auf die
            # Vorgabewerte zurueck (Daempfung 0,10 / Reibung 0,05) und die
            # Zeile traegt trotzdem die Paketzahl des ganzen Laufs. Gemessen am
            # 21.09.2026 (20:11) sah genau das aus wie "alter Build" - der
            # AUS-Lauf meldete 0,050/0,100 statt 0,000/0,000.
            if ($l -match '\[idle\]') { continue }
            if ($l -notmatch '^\[ffb\] (\d+) Pakete') { continue }
            $seen = [int]$Matches[1]
            # **Ruhezeilen sind keine Messung.** Der Helfer druckt, wenn kein
            # Paket mehr kommt, eine Zeile mit `[idle]`, den *letzten*
            # Paketzaehler und seinen eigenen Ruhewerten (Daempfung 0,10,
            # Reibung 0,05). Gemessen am 21.09.2026 (20:22) las die Pruefung
            # genau diese Zeile und meldete "FFB AUS -> Reibung 0,050": ein
            # Fehlalarm, der wie ein alter Build aussah. Vorher stand hier nur
            # `$seen -eq 0` - das faengt die Zeile *vor* dem Spielstart ab,
            # aber nicht die nach dem Ende des Spiels.
            if ($seen -lt $SettlePackets -or $l -match '\[idle\]') { continue }
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
        if ($packets -ge $MinPackets) { break }
        # Auch hier muss das `-f` **in** die Klammer und um die ganze
        # zusammengesetzte Zeichenkette: aussen bindet es an
        # `Write-Host -ForegroundColor` und bricht die Messung genau dann ab,
        # wenn sie wiederholen will. Gemessen am 21.09.2026 (ParameterBinding:
        # 'Cannot convert value "38" to type System.ConsoleColor').
        Write-Host (("[ship] Lauf {0} (FFB {1}) lieferte nur {2} Pakete - " +
            "wird wiederholt") -f $attempt,
            $(if ($enabled) { 'AN' } else { 'AUS' }), $packets)
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
Check ($off.packets -ge $MinPackets -and $off.fric -le 0.001 -and $off.peak -le 0.001 `
        -and $off.damp -le 0.001) `
    "der Build kennt APEX_FFB_SETTINGS (neuer Stand)" `
    (("FFB AUS -> {0} Pakete, Reibung {1:N3}, Kraft {2:N3}, Daempfung {3:N3} " +
      "(ein alter Build haette hier die Werte des AN-Laufs)") -f `
        $off.packets, $off.fric, $off.peak, $off.damp)

# Der zweite, unabhaengige Beweis, dass im Pack wirklich der neue Stand liegt:
# ein Testfall, den es vorher nicht gab, laeuft **im ausgelieferten Build**.
# `tests/test_pedal_span.gd` haelt den Fund vom 21.09.2026 fest - eine
# Pedal-Kalibrierung mit einem Punkt neben der Achse
# (`throttle_press: -1.8828`) deckelte Vollgas auf 53 %. Ein alter Build
# liefert dort 0.53 und damit rot, der neue 1.00 und gruen. Der Test schreibt
# nur in seine eigenen `user://g29_pedal_span_*.json`, nie in das Fahrer-Profil.
$pedalLog = Join-Path $env:TEMP "apex_ship_pedal.log"
$pedalErr = Join-Path $env:TEMP "apex_ship_pedal.err"
foreach ($p in @($pedalLog, $pedalErr)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
$pedal = Start-Process -FilePath $Exe `
    -ArgumentList "--headless --script res://tests/test_pedal_span.gd" `
    -WindowStyle Hidden -PassThru -Wait `
    -RedirectStandardOutput $pedalLog -RedirectStandardError $pedalErr
$pedalOut = @(Get-Content -LiteralPath $pedalLog -ErrorAction SilentlyContinue)
$pedalPush = @($pedalOut | Where-Object { $_ -match "Vollgas" } | Select-Object -First 1)
Check ($pedalOut -match "PEDAL_SPAN PASS") `
    "der Build enthaelt die Pedal-Haertung (neuer Stand)" `
    ($(if ($pedalPush.Count -gt 0) { $pedalPush[0] } else { "kein Ergebnis (Log: $pedalLog)" }))

# Dasselbe fuer die Selbstmessung der Kraftrichtung (Welle 5): ein Testfall,
# den es vorher nicht gab, im ausgelieferten Build. Er prueft, dass der Helfer
# seine Achsenstellung mitschickt, dass daraus die Richtung folgt und dass
# ohne Achsdaten **nichts** behauptet wird.
$dirLog = Join-Path $env:TEMP "apex_ship_direction.log"
$dirErr = Join-Path $env:TEMP "apex_ship_direction.err"
foreach ($p in @($dirLog, $dirErr)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
$dir = Start-Process -FilePath $Exe `
    -ArgumentList "--headless --script res://tests/test_ffb_direction.gd" `
    -WindowStyle Hidden -PassThru -Wait `
    -RedirectStandardOutput $dirLog -RedirectStandardError $dirErr
$dirOut = @(Get-Content -LiteralPath $dirLog -ErrorAction SilentlyContinue)
$dirKey = @($dirOut | Where-Object { $_ -match "gleichlaeufig_dreht_die_kraft_um" } | Select-Object -First 1)
Check ($dirOut -match "FFB_DIRECTION PASS") `
    "der Build misst die Kraftrichtung selbst (neuer Stand)" `
    ($(if ($dirKey.Count -gt 0) { $dirKey[0] } else { "kein Ergebnis (Log: $dirLog)" }))

# Und der Grund, warum dieser Test ueberhaupt existiert: dass die ausgelieferte
# Datei die AKTUELLE ist. Gemessen am 21.09.2026 (19:10) liefen die beiden
# Kopien auseinander - ausgeliefert 18:58, Export 19:06. Dieser Test haette
# damals angeschlagen; ohne ihn blieb es unbemerkt, weil die aeltere Kopie
# zufaellig schon alle neuen Testfaelle bestand.
$newestSource = @(
    Get-ChildItem -Path (Join-Path $project 'godot_f1') -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "*\.godot\*" -and $_.Extension -in '.gd', '.tscn', '.cfg', '.json' }
    Get-Item (Join-Path $project 'godot_f1\project.godot')
) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$deliveredPck = [System.IO.Path]::ChangeExtension($Exe, '.pck')
$deliveredTime = if (Test-Path -LiteralPath $deliveredPck) { (Get-Item -LiteralPath $deliveredPck).LastWriteTime } else { [datetime]::MinValue }
Check ($deliveredTime -ge $newestSource.LastWriteTime) `
    "die ausgelieferte Datei ist nicht aelter als die Quelle" `
    ("ausgeliefert {0}, neueste Quelle {1} ({2})" -f `
        $deliveredTime.ToString('dd.MM. HH:mm:ss'), $newestSource.LastWriteTime.ToString('dd.MM. HH:mm:ss'), $newestSource.Name)

# Ein liegengebliebener Spielprozess sperrt die ausgelieferte .exe und laesst
# den naechsten Export mit einem nackten IOException scheitern (gemessen am
# 21.09.2026). Deshalb ist auch das eine Pruefung, nicht nur eine Warnung.
$leftovers = @(Get-Process -Name 'Apex Circuit', 'ApexCircuit' -ErrorAction SilentlyContinue)
Check ($leftovers.Count -eq 0) "kein Spielprozess bleibt stehen" `
    ($(if ($leftovers.Count -eq 0) { "keiner" } else {
        ($leftovers | ForEach-Object { "$($_.Id)/$($_.ProcessName)" }) -join ', ' }))

if ($failed -gt 0) {
    Write-Host "[ship] Log: $($on.log)"
    Write-Host "SHIP_RESULT FAIL $failed Mangel"
    exit 1
}
Write-Host "SHIP_RESULT PASS 7 Pruefungen, 0 Mangel"
exit 0
