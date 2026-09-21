<#
    Hardware-Messung der Kraftrichtung.

    Das Spiel definiert "rechts = +1". Ob eine positive DirectInput-Kraft das
    G29 nach rechts oder nach links dreht, ist von aussen nicht zu sehen -
    deshalb faehrt dieser Aufruf beides: Helfer starten, Spiel messen lassen.

    Das Lenkrad muss dafuer frei stehen (Haende weg). Der Test bewegt es
    zweimal drei Sekunden lang mit 0,35 Kraft.

        powershell -File tools/ffb_direction_check.ps1
        powershell -File tools/ffb_direction_check.ps1 -Force 0.25 -Invert
#>
param(
    [double]$Force = 0.35,
    [switch]$Invert,
    [switch]$Shared,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python).Source
$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) {
    $godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
}

$ffbArgs = @("$project\tools\g29_ffb.py", "--verbose", "--gain", "1.0")
if ($Invert) { $ffbArgs += "--invert" }
if ($Shared) { $ffbArgs += "--shared" }

Write-Host "[direction] starte Helfer"
$bridge = Start-Process -FilePath $python -ArgumentList $ffbArgs -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput "$project\tools\ffb_bridge.log" `
    -RedirectStandardError "$project\tools\ffb_bridge.err"
Start-Sleep -Seconds 2

Write-Host "[direction] messe am Lenkrad (Haende weg!)"
# Ueber den Wrapper, nicht direkt: zwei Godot-Instanzen auf demselben Projekt
# zerstoen den .godot-Cache und liefern erfundene Messwerte.
& powershell -File "$project\tools\run_godot.ps1" --path "$project\godot_f1" --resolution 320x200 --script tests/probe_ffb_steer.gd 2>&1 |
    Select-String -Pattern "FFB_STEER|PASS|FAIL"

if (-not $bridge.HasExited) { Stop-Process -Id $bridge.Id -Force }
Write-Host "[direction] Helfer-Log:"
Get-Content "$project\tools\ffb_bridge.log" -ErrorAction SilentlyContinue | Select-Object -Last 6
