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

# Start-Process zerlegt den Argument-String selbst; der Projektpfad enthaelt
# ein Leerzeichen ("Mark Waldeis"). Ohne die Anfuehrungszeichen startet Python
# mit "C:\Users\Mark" als Skript, der Helfer laeuft nie an - und der Test
# meldet "Lenkrad bewegt sich nicht", obwohl in Wahrheit nie eine Kraft
# gesendet wurde. Gemessen am 21.09.2026 (tools/ffb_bridge.err).
$ffbArgs = "-u `"$project\tools\g29_ffb.py`" --verbose --gain 1.0"
if ($Invert) { $ffbArgs += " --invert" }
if ($Shared) { $ffbArgs += " --shared" }

# Der Prueflauf darf das Lenkrad-Profil des Fahrers nicht anfassen: er kann
# nicht headless laufen (headless zaehlt Godot keine Joysticks auf), der
# Headless-Schutz in save_profile() greift also nicht. Gemessen am 21.09.2026
# schrieb dieser Aufruf sonst user://g29_profile.json neu und veraenderte die
# Pedal-Kalibrierung des Fahrers.
$env:APEX_G29_PROFILE = "user://g29_profile_diag.json"

function Stop-StrayProbe {
    Get-CimInstance Win32_Process -Filter "Name like '%Godot%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*probe_ffb_steer*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

$probeLog = "$project\tools\ffb_direction_probe.log"
$probeErr = "$project\tools\ffb_direction_probe.err"
$bridge = $null
$previous = $ErrorActionPreference
try {
    Write-Host "[direction] starte Helfer"
    $bridge = Start-Process -FilePath $python -ArgumentList $ffbArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$project\tools\ffb_bridge.log" `
        -RedirectStandardError "$project\tools\ffb_bridge.err"
    Start-Sleep -Seconds 2

    Write-Host "[direction] messe am Lenkrad (Haende weg!)"
    # Ueber den Wrapper, nicht direkt: zwei Godot-Instanzen auf demselben
    # Projekt zerstoen den .godot-Cache und liefern erfundene Messwerte.
    # Ein einziger, selbst gequoteter Argument-String: Start-Process zerlegt
    # eine Liste selbst und schneidet dabei den Projektpfad am Leerzeichen
    # ("Mark Waldeis") ab - derselbe Fehler, der den Helfer oben nie starten
    # liess. Gemessen am 21.09.2026: "-File C:\Users\Mark ... keine .ps1".
    $probeArgs = "-File `"$project\tools\run_godot.ps1`" --path `"$project\godot_f1`" " +
        "--resolution 320x200 --script tests/probe_ffb_steer.gd"
    $probe = Start-Process -FilePath "powershell" -WindowStyle Hidden -PassThru `
        -ArgumentList $probeArgs `
        -RedirectStandardOutput $probeLog -RedirectStandardError $probeErr
    if (-not $probe.WaitForExit($TimeoutSeconds * 1000)) {
        Write-Host "[direction] Prueflauf haengt - wird abgebrochen"
        Stop-Process -Id $probe.Id -Force -ErrorAction SilentlyContinue
    }
    Stop-StrayProbe
    Get-Content $probeLog -ErrorAction SilentlyContinue |
        Select-String -Pattern "FFB_STEER|PASS|FAIL"
} finally {
    # Aufraeumen in jedem Fall: vorher blieb der Helfer stehen, wenn der
    # Prueflauf mit Fehler abbrach - dann ist das Lenkrad fuer die naechste
    # Messung besetzt und der naechste Lauf misst Unsinn.
    Stop-StrayProbe
    if ($bridge -and -not $bridge.HasExited) { Stop-Process -Id $bridge.Id -Force }
    $ErrorActionPreference = $previous
}
Write-Host "[direction] Helfer-Log:"
Get-Content "$project\tools\ffb_bridge.log" -ErrorAction SilentlyContinue | Select-Object -Last 6
