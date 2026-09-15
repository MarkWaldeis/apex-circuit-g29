@echo off
set GODOT=C:\Users\Mark Waldeis\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe
set PROJ=C:\Users\Mark Waldeis\Desktop\grok f1 try\godot_f1
set OUT=C:\Users\Mark Waldeis\Desktop\grok f1 try\ApexCircuit\ApexCircuit.exe
echo Using %GODOT%
"%GODOT%" --headless --path "%PROJ%" --export-release ApexWin "%OUT%"
echo EXIT=%ERRORLEVEL%
dir "C:\Users\Mark Waldeis\Desktop\grok f1 try\ApexCircuit"
