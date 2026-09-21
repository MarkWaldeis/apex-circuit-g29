<#
    Faehrt die komplette headless-Testliste nacheinander durch die
    Godot-Sperre und wertet jeden Lauf ehrlich aus.

    Warum es das gibt (gemessen am 21.09.2026, 18:56): eine zweite
    Godot-Instanz am selben Projekt zerschiesst `.godot/`. Der betroffene Lauf
    meldete dann
        "Could not preload resource script res://scripts/ffb_link.gd"
        "Nonexistent function 'new' in base 'GDScript'"
    und trotzdem exit=0 samt "LAP_DRIVE PASS". Mein erster Zaehlversuch
    ("wie viele Testdateien sind gruen?") haette das als gruen gezaehlt.
    Deshalb gilt ein Lauf hier nur dann als bestanden, wenn
      * der Exit-Code 0 ist, UND
      * die Ausgabe keinen Hinweis auf einen unvollstaendigen Lauf enthaelt
        (SCRIPT ERROR, Parse Error, Compile Error, Nonexistent function,
        Failed to load script, Invalid call), UND
      * mindestens eine PASS-Zeile vorkommt.

    Die gezaehlte Zahl ist die der PASS-Zeilen - sie enthaelt die
    Abschlusszeile der Datei ("test_x.gd PASS"). In den Berichten sind die
    einzelnen Pruefungen einer Datei deshalb oft genau eine weniger.

    Usage:
        powershell -File tools/run_all_tests.ps1
        powershell -File tools/run_all_tests.ps1 -Filter ffb
        powershell -File tools/run_all_tests.ps1 -Timeout 300
#>
param(
    [string]$Filter = '',
    [int]$Timeout = 900
)

$ErrorActionPreference = 'Continue'

$project = Split-Path -Parent $PSScriptRoot
$testsDir = Join-Path $project 'godot_f1\tests'
$logDir = Join-Path $PSScriptRoot 'testlogs'
$runner = Join-Path $PSScriptRoot 'run_godot.ps1'
$corruption = 'SCRIPT ERROR|Parse Error|Compile Error|Nonexistent function|Failed to load script|Invalid call|Cannot open file'

New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$tests = @(Get-ChildItem -Path (Join-Path $testsDir 'test_*.gd') | Sort-Object Name)
if ($Filter) {
    $tests = @($tests | Where-Object { $_.Name -like "*$Filter*" })
}
if ($tests.Count -eq 0) {
    Write-Host "run_all_tests: keine Testdatei gefunden (Filter='$Filter')"
    exit 1
}

Push-Location $project
$rows = @()
$bad = 0
$totalChecks = 0
$started = Get-Date
try {
    foreach ($test in $tests) {
        $script = "tests/" + $test.Name
        $t0 = Get-Date
        $out = & powershell -NoProfile -File $runner -Timeout $Timeout --headless --path godot_f1 --script $script 2>&1
        $code = $LASTEXITCODE
        $seconds = [Math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
        $lines = @($out | ForEach-Object { "$_" })
        $lines | Set-Content -LiteralPath (Join-Path $logDir ($test.Name -replace '\.gd$', '.log')) -Encoding utf8

        # Die Tests schreiben ihre Zeilen selbst ("PASS x", "DRIVE_UNIT PASS
        # kmh=..."). Gemessen am 21.09.2026 zaehlte ein Muster, das nur "PASS "
        # am Zeilenanfang akzeptiert, test_drive_unit.gd faelschlich als
        # "keine PASS-Zeile" - ein Zaehlfehler, der einen gruenen Test rot
        # macht, ist genauso schlecht wie das Gegenteil.
        $passes = @($lines | Where-Object { $_ -match '(^|\s)PASS(\s|$)' }).Count
        $fails = @($lines | Where-Object { $_ -match '(^|\s)FAIL(\s|$)' }).Count
        $corrupt = @($lines | Where-Object { $_ -match $corruption }).Count
        $reasons = @()
        if ($code -eq 125) { $reasons += 'exit=125 fremde Godot-Instanz' }
        elseif ($code -eq 126) { $reasons += 'exit=126 Godot haengt (Timeout)' }
        elseif ($code -eq 124) { $reasons += 'exit=124 Sperre belegt' }
        elseif ($code -ne 0) { $reasons += "exit=$code" }
        if ($corrupt -gt 0) { $reasons += "$corrupt x Fehlerzeile -> Lauf ungueltig" }
        if ($fails -gt 0) { $reasons += "$fails x FAIL-Zeile" }
        if ($passes -eq 0) { $reasons += 'keine PASS-Zeile' }

        if ($reasons.Count -eq 0) {
            $totalChecks += $passes
            $rows += [pscustomobject]@{
                Status = 'OK'; Test = $test.Name; Pruefungen = $passes; Sekunden = $seconds; Grund = ''
            }
        } else {
            $bad++
            $rows += [pscustomobject]@{
                Status = 'FEHLER'; Test = $test.Name; Pruefungen = $passes; Sekunden = $seconds
                Grund = ($reasons -join '; ')
            }
        }
        Write-Host ("{0,-7} {1,-34} {2,3} Pruefungen {3,7:N1} s {4}" -f
            $rows[-1].Status, $test.Name, $passes, $seconds, $rows[-1].Grund)
    }
} finally {
    Pop-Location
}

$totalSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 1)
Write-Host ""
Write-Host ("run_all_tests: {0} Dateien, {1} Pruefungen, {2} s" -f $tests.Count, $totalChecks, $totalSeconds)
if ($bad -gt 0) {
    Write-Host ("run_all_tests: ERGEBNIS FEHLERHAFT - {0} von {1} Dateien sind kein Beweis (Logs in {2})" -f $bad, $tests.Count, $logDir)
    exit 1
}
Write-Host "run_all_tests: ERGEBNIS GRUEN (jede Datei mit Exit 0, ohne Fehlerzeilen, mit PASS)"
exit 0
