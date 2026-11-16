@echo off
rem PARTIDAS.bat - importa y exporta partidas de emuladores (.sav) y guarda copias de seguridad.
rem Busca solo donde esta instalado el juego (o usa la carpeta donde estes).
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0tools\PARTIDAS.ps1" %*
if errorlevel 1 pause
