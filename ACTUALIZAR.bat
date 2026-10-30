@echo off
rem ACTUALIZAR.bat - actualiza Mario Tennis: Power Tour sin instalar todo desde cero.
rem Encuentra solo donde esta instalado el juego, reutiliza tu ROM y conserva tus partidas.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0tools\ACTUALIZAR.ps1" %*
if errorlevel 1 pause
