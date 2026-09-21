@echo off
rem Exportiert das Spiel UND liefert es an den Desktop-Start aus.
rem
rem Der Export allein reichte nicht: "Apex Circuit.lnk" auf dem Desktop zeigt
rem auf "Desktop\Apex Circuit\", der Export schrieb nach "grok f1 try\
rem ApexCircuit\". Beide Kopien liefen auseinander, der Spieler haette eine
rem alte Version gestartet (gemessen am 21.09.2026: ausgeliefert 18:58,
rem Export 19:06). tools\export_and_deliver.ps1 kopiert, vergleicht die
rem SHA256-Summen und prueft das Alter gegen die neueste Quelldatei.
rem Windows PowerShell 5.1 bekommt hier einen sauberen Modulpfad: wird dieses
rem Skript aus einem PowerShell-7-Fenster gestartet, erbt das 5.1-Kind dessen
rem PSModulePath - und laedt dann Microsoft.PowerShell.Utility aus dem
rem .NET-7-Modulordner, was fehlschlaegt. Gemessen am 21.09.2026 brach damit
rem die Auslieferung ab ("Get-FileHash wurde nicht als Name eines Cmdlet
rem erkannt"), waehrend der Export selbst durchlief.
set "PSModulePath=%ProgramFiles%\WindowsPowerShell\Modules;%SystemRoot%\system32\WindowsPowerShell\v1.0\Modules"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\export_and_deliver.ps1" %*
echo EXIT=%ERRORLEVEL%
