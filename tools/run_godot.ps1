<#
    Serialised Godot runner.

    Godot rewrites its import/cache folder (`.godot/`) while it runs. Two
    instances on the same project at the same time can therefore read a
    half-written cache, which shows up as nonsense like
    "Nonexistent function 'new' in base 'GDScript'" and fake PASS lines.
    Everyone on this project runs Godot through this wrapper instead: the lock
    makes the runs queue up, so parallel agents cannot corrupt each other.

    Gemessen am 21.09.2026 (18:56) reicht die Sperre allein nicht:

      * Die README zeigt `godot --headless ...` direkt. Wer das tippt, umgeht
        die Sperre. test_lap_drive.gd lief gleichzeitig mit einem fremden Lauf
        und meldete "Could not preload resource script res://scripts/
        ffb_link.gd", "Nonexistent function 'new' in base 'GDScript'" - und
        trotzdem exit=0 und "LAP_DRIVE PASS".
      * Ein so kaputter SceneTree-Test erreicht sein quit() nie. Godot laeuft
        dann endlos weiter: der Wrapper gab nach dem Timeout auf und liess die
        verwaiste Instanz stehen (gemessen: PID 32524, sechs Minuten lang,
        Elternprozess weg) - die naechste Messung war damit ebenfalls
        vergiftet.

    Deshalb tut der Wrapper drei Dinge: sperren, Fremdlaeufer erkennen (und
    lieber mit Exit 125 abbrechen als erfundene Messwerte liefern), und den
    eigenen Godot beim Timeout wirklich beenden.

    Exit-Codes:
        0..n  Exit-Code von Godot
        124   Sperre war laenger als -Timeout belegt
        125   fremde Godot-Instanz am selben Projekt (-AllowStray uebergeht das)
        126   Godot haengte und wurde nach -Timeout beendet

    Usage:
        powershell -File tools/run_godot.ps1 --headless --path godot_f1 --script tests/test_x.gd
        powershell -File tools/run_godot.ps1 -Timeout 600 --headless --path godot_f1 --script tests/test_x.gd
#>
param(
    [int]$Timeout = 900,
    [switch]$AllowStray,
    [int]$StrayGraceSeconds = 30,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GodotArgs
)

$ErrorActionPreference = 'Stop'

$lockPath = Join-Path $env:TEMP 'apex_circuit_godot.lock'
$deadline = (Get-Date).AddSeconds($Timeout)
$handle = $null

# Projektordner aus den Argumenten ("--path godot_f1" -> "godot_f1"): daran
# erkennt der Wrapper fremde Instanzen, egal ob relativ oder absolut gestartet.
$projectToken = $null
for ($i = 0; $i -lt $GodotArgs.Count - 1; $i++) {
    if ($GodotArgs[$i] -eq '--path') {
        $leaf = Split-Path -Path $GodotArgs[$i + 1] -Leaf
        if ($leaf) { $projectToken = $leaf }
    }
}

function Find-StrayGodot {
    param([string]$Token)
    $found = @()
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name like '%Godot%'" -ErrorAction SilentlyContinue)) {
        $cmd = $p.CommandLine
        if (-not $cmd) { continue }
        if ($Token -and $cmd -notlike "*$Token*") { continue }
        $found += $p
    }
    return $found
}

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

$stdout = Join-Path $env:TEMP ("apex_godot_{0}.out" -f $PID)
$stderr = Join-Path $env:TEMP ("apex_godot_{0}.err" -f $PID)

function Write-NewLines {
    param([string]$Path, [string]$Key, $Positions)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    } catch {
        return
    }
    try {
        if ($Positions[$Key] -gt $stream.Length) { $Positions[$Key] = 0 }
        $stream.Seek($Positions[$Key], 'Begin') | Out-Null
        $reader = New-Object System.IO.StreamReader($stream)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($null -ne $line) { Write-Output $line }
        }
        $Positions[$Key] = $stream.Position
    } finally {
        $stream.Dispose()
    }
}

try {
    $writer = New-Object System.IO.StreamWriter($handle)
    $writer.WriteLine("pid=$PID started=$(Get-Date -Format o)")
    $writer.Flush()

    # Fremdlaeufer: nur warnen und warten, nicht toeten - der andere Agent
    # koennte mitten in einer Messung sein. Wer trotzdem will, nimmt -AllowStray.
    $stray = @(Find-StrayGodot $projectToken)
    if ($stray.Count -gt 0 -and -not $AllowStray) {
        $graceEnd = (Get-Date).AddSeconds($StrayGraceSeconds)
        while ($stray.Count -gt 0 -and (Get-Date) -lt $graceEnd) {
            Write-Host ("run_godot: fremde Godot-Instanz laeuft (pid {0}), warte bis zu {1} s - sonst zerfaellt der .godot-Cache" -f $stray[0].ProcessId, $StrayGraceSeconds)
            Start-Sleep -Seconds 2
            $stray = @(Find-StrayGodot $projectToken)
        }
    }
    if ($stray.Count -gt 0) {
        foreach ($p in $stray) {
            Write-Host ("run_godot: STRAY pid={0} cmd={1}" -f $p.ProcessId, $p.CommandLine)
        }
        Write-Host "run_godot: ABBRUCH - eine andere Godot-Instanz arbeitet am selben Projekt. Messwerte waeren erfunden; -AllowStray erzwingt den Start."
        exit 125
    }

    $exe = 'C:\Users\Mark Waldeis\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe'
    if (-not (Test-Path -LiteralPath $exe)) {
        $exe = 'godot'
    }

    Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue

    # Start-Process zerlegt eine Liste selbst; Argumente mit Leerzeichen muessen
    # deshalb vorher gequotet werden (Projektpfad "Mark Waldeis").
    $quoted = @()
    foreach ($a in $GodotArgs) {
        if ($a -match '\s' -and -not ($a.StartsWith('"') -and $a.EndsWith('"'))) {
            $quoted += '"' + $a + '"'
        } else {
            $quoted += $a
        }
    }

    $proc = Start-Process -FilePath $exe -ArgumentList $quoted -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    $positions = @{ out = [long]0; err = [long]0 }
    $killed = $false
    $killDeadline = (Get-Date).AddSeconds($Timeout)
    while (-not $proc.HasExited) {
        Write-NewLines -Path $stdout -Key 'out' -Positions $positions
        Write-NewLines -Path $stderr -Key 'err' -Positions $positions
        if ((Get-Date) -gt $killDeadline) {
            Write-Host ("run_godot: Godot haengt seit {0} s (pid {1}) - wird beendet" -f $Timeout, $proc.Id)
            try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch { }
            $killed = $true
            break
        }
        Start-Sleep -Milliseconds 150
    }

    if (-not $killed) {
        $proc.WaitForExit()
    }
    Write-NewLines -Path $stdout -Key 'out' -Positions $positions
    Write-NewLines -Path $stderr -Key 'err' -Positions $positions
    Remove-Item -LiteralPath $stdout, $stderr -ErrorAction SilentlyContinue

    if ($killed) {
        exit 126
    }
    exit $proc.ExitCode
} finally {
    if ($handle) {
        $handle.Dispose()
    }
}
