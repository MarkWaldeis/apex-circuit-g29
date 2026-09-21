@echo off
rem Exportiert das Spiel UND liefert es an den Desktop-Start aus.
rem
rem Der Export allein reichte nicht: "Apex Circuit.lnk" auf dem Desktop zeigt
rem auf "Desktop\Apex Circuit\", der Export schrieb nach "grok f1 try\
rem ApexCircuit\". Beide Kopien liefen auseinander, der Spieler haette eine
rem alte Version gestartet (gemessen am 21.09.2026: ausgeliefert 18:58,
rem Export 19:06). tools\export_and_deliver.ps1 kopiert, vergleicht die
rem SHA256-Summen und prueft das Alter gegen die neueste Quelldatei.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\export_and_deliver.ps1" %*
echo EXIT=%ERRORLEVEL%
