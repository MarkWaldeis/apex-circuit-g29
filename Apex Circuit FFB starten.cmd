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
echo WICHTIG:
echo   * Das Lenkrad braucht sein NETZTEIL - ohne Netzteil gibt es keine Kraft
echo     und keine Achsendaten.
echo   * Im Logitech G HUB: Betriebsbereich 900 Grad, Zentrierfeder AUS.
echo   * Dieses Fenster waehrend des Fahrens offen lassen. Esc oder Strg+C
echo     beendet es und laesst das Lenkrad los.
echo   * Anderes Lenkrad als G29/G920/G923: --name NAME mitgeben.
echo.

if /I "%~1"=="--demo" goto :demo
if /I "%~1"=="--sign" goto :sign
if /I "%~1"=="--dry" goto :dry
if /I "%~1"=="--help" goto :help

:run
echo [Start] Helfer laeuft. Spiel starten und fahren.
echo.
python tools\g29_ffb.py --verbose
goto :done

:demo
echo [Demo] Fuehltest: alle Fahrsituationen einmal am Lenkrad, ohne Spiel.
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
echo   "Apex Circuit FFB starten.cmd"            Helfer fuer das Spiel starten
echo   "Apex Circuit FFB starten.cmd" --demo     Fuehltest am Lenkrad, ohne Spiel
echo   "Apex Circuit FFB starten.cmd" --sign     Kraftrichtung messen
echo   "Apex Circuit FFB starten.cmd" --dry      Trockenlauf ohne Lenkrad
echo   python tools\g29_ffb.py --name G923        anderes Lenkrad suchen
goto :done

:done
echo.
echo ----------------------------------------------------------------
echo Wenn keine Kraft ankommt:
echo   1. Netzteil am G29 (ohne Netzteil: keine Kraft)
echo   2. G HUB: Zentrierfeder aus, Daempfung niedrig, Bereich 900 Grad
echo   3. "Lenkrad pruefen.cmd" ausfuehren - sendet das Lenkrad ueberhaupt Daten?
echo   4. Im Spiel: Esc - Einstellungen - Force Feedback - Kraftrichtung umdrehen
echo ----------------------------------------------------------------
pause
