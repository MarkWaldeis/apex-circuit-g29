<#
    Serialised Godot runner.

    Godot rewrites its import/cache folder (`.godot/`) while it runs. Two
    instances on the same project at the same time can therefore read a
    half-written cache, which shows up as nonsense like
    "Nonexistent function 'new' in base 'GDScript'" and fake PASS lines.
    Everyone on this project runs Godot through this wrapper instead: the lock
    makes the runs queue up, so parallel agents cannot corrupt each other.

    Usage:
        powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_x.gd
        powershell -File tools/run_godot.ps1 -Timeout 600 --headless --path godot_f1 --script tests/test_x.gd
#>
param(
    [int]$Timeout = 900,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GodotArgs
)

$ErrorActionPreference = 'Stop'

$lockPath = Join-Path $env:TEMP 'apex_circuit_godot.lock'
$deadline = (Get-Date).AddSeconds($Timeout)
$handle = $null

while ($true) {
    try {
        $handle = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        break
    } catch {
        if ((Get-Date) -gt $deadline) {
            Write-Host "run_godot: timed out waiting for another Godot run to finish"
            exit 124
        }
        Start-Sleep -Milliseconds 400
    }
}

try {
    $writer = New-Object System.IO.StreamWriter($handle)
    $writer.WriteLine("pid=$PID started=$(Get-Date -Format o)")
    $writer.Flush()

    $exe = 'C:\Users\Mark Waldeis\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        $exe = 'godot'
    }
    & $exe @GodotArgs
    exit $LASTEXITCODE
} finally {
    if ($handle) {
        $handle.Dispose()
    }
}
