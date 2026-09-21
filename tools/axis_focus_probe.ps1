<#
    Messung: sieht Godot die Lenkradachse - und aendert der Fensterfokus das?

    Hintergrund (gemessen am 21.09.2026, 19:40): `python tools/ffb_hw_probe.py`
    liest die G29-Achse ueber DirectInput einwandfrei (24/24 gueltige Werte,
    Kraft bewegt sie um -32524), waehrend `tests/probe_axis_read.gd` im
    Fensterlauf **alle** Achsen als 0.000 meldet (`data=false`) - auch ohne
    laufenden Helfer. Die bisherige Erklaerung "Netzteil/Kabel" passt dazu
    nicht.

    DirectInput liest in diesem Projekt mit DISCL_BACKGROUND, Godot dagegen
    haengt an der Windows-Eingabe, die bei manchen Bauarten nur Daten liefert,
    wenn das Fenster im Vordergrund ist. Dieses Skript misst beide Zustaende
    nacheinander im **selben** Lauf: erst ohne Fokus, dann mit Vordergrund.

        powershell -File tools/axis_focus_probe.ps1

    Ausgabe: die AXIS_READ-Zeilen des Probels plus ein Vergleich der Spannen.
#>
param(
    [int]$Seconds = 10,
    [switch]$NoFocus
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$log = Join-Path $PSScriptRoot 'axis_focus.log'
$errLog = Join-Path $PSScriptRoot 'axis_focus.err'
Remove-Item $log, $errLog -ErrorAction SilentlyContinue

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ApexForeground {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

# Ein einziger, selbst gequoteter Argument-String. Als *Array* zerlegt
# Start-Process die Argumente selbst und schneidet den Projektpfad am
# Leerzeichen ab ("C:\Users\Mark") - genau die Falle, die den Richtungstest
# in Welle 4 den Helfer nie starten liess.
$runnerArgs = "-ExecutionPolicy Bypass -File `"$PSScriptRoot\run_godot.ps1`" " +
    "-Timeout 180 --path `"$project\godot_f1`" --resolution 320x200 " +
    "--script tests/probe_axis_read.gd"
Write-Host "[axis] starte Godot (Fensterlauf)"
$runner = Start-Process -FilePath 'powershell' -ArgumentList $runnerArgs -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $log -RedirectStandardError $errLog

# Der Probe laeuft 8 s, nachdem die Szene geladen ist. Erst warten, bis die
# erste AXIS_READ-Zeile im Protokoll steht (davor ist Godot noch am Laden),
# dann drei Sekunden ohne Fokus messen und erst danach nach vorn holen - so
# stehen beide Zustaende im **selben** Lauf und sind vergleichbar.
$bootDeadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $bootDeadline) {
    if ((Test-Path $log) -and (Select-String -Path $log -Pattern 'AXIS_READ device=' -Quiet)) {
        break
    }
    Start-Sleep -Milliseconds 250
}
Start-Sleep -Seconds 3
$focused = $null
if (-not $NoFocus) {
    for ($i = 0; $i -lt 12 -and -not $focused; $i++) {
        $candidates = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowHandle -ne 0 })
        if ($candidates.Count -gt 0) {
            $focused = $candidates[0]
            [void][ApexForeground]::ShowWindow($focused.MainWindowHandle, 9)
            [void][ApexForeground]::SetForegroundWindow($focused.MainWindowHandle)
            Write-Host ("[axis] Fenster in den Vordergrund geholt: pid={0} hwnd={1}" -f `
                $focused.Id, $focused.MainWindowHandle)
        } else {
            Start-Sleep -Milliseconds 500
        }
    }
    if (-not $focused) { Write-Host "[axis] kein Fenster gefunden - Fokus ungeprueft" }
}

$deadline = (Get-Date).AddSeconds($Seconds + 15)
while (-not $runner.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
}
if (-not $runner.HasExited) {
    Write-Host "[axis] Godot laeuft noch - wird beendet"
    Stop-Process -Id $runner.Id -Force -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name like '%Godot%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*probe_axis_read*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Get-Content $log -ErrorAction SilentlyContinue | Select-String -Pattern 'AXIS_READ'
$errors = Get-Content $errLog -ErrorAction SilentlyContinue
if ($errors) { Write-Host "[axis] stderr:"; $errors | Select-Object -Last 10 }
