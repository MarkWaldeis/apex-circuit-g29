@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ==== Logitech G29 Hardware-Pruefung ====
echo.
echo Liest die rohen HID-Reports des Lenkrads direkt von Windows.
echo Kommt hier "report timeout ... (no data)", sendet das Lenkrad selbst nichts.
echo.
python tools\hid_probe.py 046d:c24f 3 1500
echo.
echo ----------------------------------------------------------------
echo Wenn oben nur "report timeout" steht:
echo   1. Netzteil des G29 anschliessen (ohne Netzteil kommen keine Daten)
echo   2. Pedalkabel am Lenkrad festziehen
echo   3. anderes USB-Port (direkt hinten am PC, kein Hub)
echo   4. Modusschalter am Lenkrad auf "PC" stellen
echo Danach erneut pruefen und im Spiel: Esc - Einstellungen - Gas kalibrieren
echo ----------------------------------------------------------------
pause
