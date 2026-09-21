@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Apex Circuit - Lenkrad-Kraft (G29/G920/G923)

echo ==== Apex Circuit: echtes Force Feedback fuer G29/G920/G923 ====
echo.
echo Godot kann am Lenkrad keine Kraft erzeugen. Dieses Fenster ist der Uebersetzer:
echo das Spiel schickt, was der Fahrer fuehlen muesste, hier wird daraus echte
echo Kraft ueber DirectInput.
echo.
echo STARTREIHENFOLGE (gemessen, docs/reviews/ffb_wave7_ownership.md):
echo   Das SPIEL muss das Lenkrad zuerst oeffnen. Uebernimmt der Helfer es
echo   zuerst, bekommt das Spiel keine Achsendaten mehr und das Rad steht still
echo   - auch fuer den Helfer. Dieser Aufruf startet deshalb erst das Spiel und
echo   dann die Kraft; faengt der Helfer zuerst an, wartet er von selbst auf
echo   das Spiel (er oeffnet das Lenkrad erst nach dem ersten Paket).
echo.
echo WICHTIG:
echo   * Das Lenkrad braucht sein NETZTEIL - ohne Netzteil gibt es keine Kraft.
echo   * Im Logitech G HUB: Betriebsbereich 900 Grad, Zentrierfeder AUS.
echo   * Dieses Fenster waehrend des Fahrens offen lassen. Esc oder Strg+C
echo     beendet es und laesst das Lenkrad los.
echo   * Kein Spiel mehr? Nach 30 s gibt der Helfer das Lenkrad von allein frei
echo     und holt es sich zurueck, sobald das Spiel wieder sendet. Ein Neustart
echo     des Spiels braucht also keinen Neustart des Helfers.
echo   * Anderes Lenkrad als G29/G920/G923: --name NAME mitgeben.
echo.

where python >nul 2>nul
if errorlevel 1 (
    echo [FEHLER] Python wurde nicht gefunden. Installation: https://www.python.org/downloads/
    echo          ^(beim Installieren "Add python.exe to PATH" anhaken^)
    echo.
    pause
    exit /b 1
)

if /I "%~1"=="--nur-helfer" goto :helper
if /I "%~1"=="--demo" goto :demo
if /I "%~1"=="--sign" goto :sign
if /I "%~1"=="--dry" goto :dry
if /I "%~1"=="--help" goto :help

:run
echo [Start] Erst das Spiel, dann die Kraft.
if exist "%USERPROFILE%\Desktop\Apex Circuit\Apex Circuit.exe" (
    start "" "%USERPROFILE%\Desktop\Apex Circuit\Apex Circuit.exe"
    echo [Start] Spiel gestartet: Apex Circuit
) else if exist "%~dp0ApexCircuit\ApexCircuit.exe" (
    start "" "%~dp0ApexCircuit\ApexCircuit.exe"
    echo [Start] Spiel gestartet: ApexCircuit.exe
) else (
    echo [Start] Spiel nicht gefunden - bitte selbst starten ^(Apex Circuit^).
)
echo [Start] Die Kraft kommt von allein, sobald du ins Rennen gehst.
echo.
python tools\g29_ffb.py --verbose
goto :done

:helper
echo [Helfer] Nur die Kraft - das Spiel laeuft schon.
echo [Helfer] Wartet, bis das Spiel Pakete schickt, und oeffnet erst dann das Lenkrad.
python tools\g29_ffb.py --verbose
goto :done

:demo
echo [Demo] Fuehltest: alle Fahrsituationen einmal am Lenkrad, ohne Spiel.
echo [Demo] Die Zahlen sind das, was das Spiel bei Standard-Einstellungen
echo [Demo] sendet (gemessen, 18 Stationen). Kraftrichtung wie im Spiel.
echo [Demo] Haende weg vom Lenkrad.
echo.
python tools\g29_ffb.py --demo
goto :done

:sign
echo [Sign] Misst, in welche Richtung eine positive Kraft das Lenkrad dreht.
python tools\g29_ffb.py --sign-check
goto :done

:dry
echo [Dry] Trockenlauf ohne Lenkrad: prueft die Kette und die Rampe.
python tools\g29_ffb.py --dry-run
goto :done

:help
echo Aufrufe:
echo   "Apex Circuit FFB starten.cmd"            Spiel + Kraft (empfohlen)
echo   "Apex Circuit FFB starten.cmd" --nur-helfer  nur die Kraft (Spiel laeuft schon)
echo   "Apex Circuit FFB starten.cmd" --demo     Fuehltest am Lenkrad, ohne Spiel
echo   "Apex Circuit FFB starten.cmd" --sign     Kraftrichtung messen
echo   "Apex Circuit FFB starten.cmd" --dry      Trockenlauf ohne Lenkrad
echo   python tools\g29_ffb.py --wait-game 0      nicht auf das Spiel warten (Diagnose)
echo   python tools\g29_ffb.py --release-wheel-after 0   Lenkrad nie freigeben
echo   python tools\g29_ffb.py --name G923        anderes Lenkrad suchen
goto :done

:done
echo.
echo ----------------------------------------------------------------
echo Wenn keine Kraft ankommt:
echo   1. Spiel neu starten, dann diesen Helfer (das Spiel muss das Lenkrad
echo      zuerst oeffnen - sonst liest es keine Achse mehr)
echo   2. Netzteil am G29 (ohne Netzteil: keine Kraft)
echo   3. G HUB: Zentrierfeder aus, Daempfung niedrig, Bereich 900 Grad
echo   4. "Lenkrad pruefen.cmd" ausfuehren - liefert das Lenkrad Daten?
echo      ^(Es dreht das Rad dabei kurz mit Kraft: Haende weg.^)
echo   5. Im Spiel: Esc - Einstellungen - Force Feedback - Kraftrichtung umdrehen
echo ----------------------------------------------------------------
pause
