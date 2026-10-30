@echo off
rem INSTALAR.bat - abre el instalador de Mario Tennis: Power Tour (Windows 10/11).
rem Elige tu ROM y la carpeta de instalacion; instala las herramientas, compila y copia el juego.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0tools\INSTALAR.ps1" %*
if errorlevel 1 pause
