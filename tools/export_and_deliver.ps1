<#
    Baut das Spiel und liefert es an die Stelle, die der Desktop-Start benutzt.

    Warum das ein eigenes Skript ist (gemessen am 21.09.2026, 19:10):

      * Der Export schrieb nach `grok f1 try\ApexCircuit\`.
      * Der Desktop-Start `Apex Circuit.lnk` zeigt aber auf
        `Desktop\Apex Circuit\Apex Circuit.exe`.
      * Beide Kopien liefen auseinander: die ausgelieferte `.pck` war vom
        18:58, der frische Export vom 19:06. Der Spieler haette also eine
        aeltere Version gespielt, und `tools/ship_check.ps1` haette das nicht
        gemerkt, weil es nur gegen die ausgelieferte Kopie prueft - die war
        zufaellig "neu genug", um die neuen Testfaelle zu bestehen.

    Dieses Skript exportiert, kopiert beide Dateien an den Auslieferungsort,
    vergleicht die SHA256-Summen der beiden Kopien und prueft, dass die
    ausgelieferte `.pck` **nicht aelter als die neueste Quelldatei** ist.

        powershell -File tools/export_and_deliver.ps1
        powershell -File tools/export_and_deliver.ps1 -SkipDelivery
#>
param(
    [string]$Delivered = "$env:USERPROFILE\Desktop\Apex Circuit",
    [switch]$SkipDelivery
)

$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $project 'godot_f1'
$repoOut = Join-Path $project 'ApexCircuit'
$repoExe = Join-Path $repoOut 'ApexCircuit.exe'
$repoPck = Join-Path $repoOut 'ApexCircuit.pck'
$destExe = Join-Path $Delivered 'Apex Circuit.exe'
$destPck = Join-Path $Delivered 'Apex Circuit.pck'

$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    $godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
}
if (-not $godot) {
    Write-Host "export: kein Godot gefunden"
    exit 1
}

New-Item -ItemType Directory -Path $repoOut -Force | Out-Null

# Godot ist ein GUI-Programm: PowerShell wartet bei `& $godot ...` NICHT darauf
# und $LASTEXITCODE bleibt leer (gemessen am 21.09.2026: die Pruefung schlug
# fehl, waehrend der Export im Hintergrund noch lief - und die Diagnose lautete
# "exit " ohne Zahl). Start-Process -Wait wartet wirklich und liefert den Code.
Write-Host "[export] $godot --export-release ApexWin $repoExe"
$exportArgs = @('--headless', '--path', ('"' + $proj + '"'), '--export-release', 'ApexWin', ('"' + $repoExe + '"'))
$export = Start-Process -FilePath $godot -ArgumentList $exportArgs -NoNewWindow -PassThru -Wait
if ($export.ExitCode -ne 0) {
    Write-Host "export: FEHLGESCHLAGEN (exit $($export.ExitCode))"
    exit 1
}
if (-not (Test-Path -LiteralPath $repoExe) -or -not (Test-Path -LiteralPath $repoPck)) {
    Write-Host "export: Build unvollstaendig - $repoExe / $repoPck fehlen"
    exit 1
}

# Neueste Quelldatei: das ist der Massstab fuer "ausgeliefert ist aktuell".
$sources = @(
    Get-ChildItem -Path $proj -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike "*\.godot\*" -and $_.Extension -in '.gd', '.tscn', '.cfg', '.godotjson', '.json' }
    Get-Item (Join-Path $proj 'project.godot')
)
$newest = $sources | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $SkipDelivery) {
    New-Item -ItemType Directory -Path $Delivered -Force | Out-Null
    Copy-Item -LiteralPath $repoExe -Destination $destExe -Force
    Copy-Item -LiteralPath $repoPck -Destination $destPck -Force
}

$hashRepo = (Get-FileHash -LiteralPath $repoPck -Algorithm SHA256).Hash
$ok = $true

if (Test-Path -LiteralPath $destPck) {
    $hashDest = (Get-FileHash -LiteralPath $destPck -Algorithm SHA256).Hash
    if ($hashDest -ne $hashRepo) {
        Write-Host "[export] FAIL: ausgelieferte .pck unterscheidet sich vom Export ($destPck)"
        $ok = $false
    } else {
        Write-Host "[export] OK beide Kopien sind identisch (SHA256 $($hashRepo.Substring(0,16))...)"
    }
    $deliveredTime = (Get-Item -LiteralPath $destPck).LastWriteTime
    if ($deliveredTime -lt $newest.LastWriteTime) {
        Write-Host ("[export] FAIL: ausgeliefert ist aelter als die Quelle ({0} < {1} {2})" -f
            $deliveredTime, $newest.LastWriteTime, $newest.Name)
        $ok = $false
    } else {
        Write-Host ("[export] OK ausgeliefert {0} ist nicht aelter als die neueste Quelle {1} ({2})" -f
            $deliveredTime.ToString('HH:mm:ss'), $newest.LastWriteTime.ToString('HH:mm:ss'), $newest.Name)
    }
} else {
    Write-Host "[export] Hinweis: kein Auslieferungsort unter $Delivered"
}

if (-not $ok) {
    exit 1
}
Write-Host "EXPORT_OK $repoPck"
