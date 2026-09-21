@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==== Logitech G29 Hardware-Pruefung ====
echo.
echo Liest beide Wege gleichzeitig: die rohen HID-Reports (die das Spiel
echo braucht) und die DirectInput-Achse (die die Kraft braucht). Das Rad wird
echo dabei kurz mit Kraft gedreht - HAENDE WEG.
echo.
python tools\hid_vs_dinput.py --seconds 1.5 --force 0.3
echo.
echo ----------------------------------------------------------------
echo Kommt KEINE Kraft an (Rad steht still bei "plus"/"minus"):
echo   1. Spiel neu starten, dann den Kraft-Helfer (das Spiel muss das Lenkrad
echo      zuerst oeffnen - sonst steht das Rad still; siehe
echo      docs/reviews/ffb_wave7_ownership.md)
echo   2. Netzteil des G29 anschliessen
echo   3. Pedalkabel am Lenkrad festziehen
echo   4. anderes USB-Port (direkt hinten am PC, kein Hub)
echo.
echo Wichtig: "report timeout" im Einzelpruefer tools\hid_probe.py beweist
echo NICHTS - das G29 sendet nur, wenn sich etwas bewegt. Deshalb dreht dieses
echo Skript das Rad erst und liest dann.
echo ----------------------------------------------------------------
pause
