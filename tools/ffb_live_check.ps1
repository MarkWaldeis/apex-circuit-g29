<#
    Hardware check: real force at the G29 and the game's steering readout at the
    same time.

    Starts tools/g29_ffb.py (which takes the wheel over the way it must for real
    force), feeds it a square-wave force, and runs the game headless next to it.
    If the game keeps reading the wheel while the wheel is being driven, the
    probe reports a steering span instead of a frozen value.

        powershell -File tools/ffb_live_check.ps1
#>
param(
    [double]$Seconds = 5.0,
    [double]$Force = 0.35,
    [switch]$Shared
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python).Source
$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) {
    $godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
}

$ffbArgs = @("$project\tools\g29_ffb.py", "--verbose")
if ($Shared) { $ffbArgs += "--shared" }

Write-Host "[live] starting force feedback bridge"
$bridge = Start-Process -FilePath $python -ArgumentList $ffbArgs -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput "$project\tools\ffb_bridge.log" `
    -RedirectStandardError "$project\tools\ffb_bridge.err"
Start-Sleep -Seconds 2

Write-Host "[live] sending $Force force for $Seconds s"
$sender = Start-Process -FilePath $python -ArgumentList @("$project\tools\ffb_send_test.py", "$Seconds", "$Force") `
    -WindowStyle Hidden -PassThru

Write-Host "[live] running the game probe"
& $godot --headless --path "$project\godot_f1" --script tests/probe_steer_live.gd 2>&1 |
    Select-String -Pattern "STEER_LIVE|G29 data arrived|G29 connected"

$sender.WaitForExit()
if (-not $bridge.HasExited) { Stop-Process -Id $bridge.Id -Force }
Write-Host "[live] bridge log:"
Get-Content "$project\tools\ffb_bridge.log" -ErrorAction SilentlyContinue | Select-Object -Last 12
