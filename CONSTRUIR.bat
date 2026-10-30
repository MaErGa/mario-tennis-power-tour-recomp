@echo off
setlocal
chcp 65001 >nul
rem ---------------------------------------------------------------------
rem  CONSTRUIR.bat - de tu ROM al juego, dentro de esta carpeta (Windows 10/11).
rem  Metodo ligero: descarga Zig, CMake, Ninja y SDL2 (unos 150 MB), recompila tu
rem  ROM y compila el juego. No instala nada en Windows: todo queda en esta carpeta
rem  (herramientas\, externo\, build\...) y el juego en "juego\".
rem  Necesita internet y unos 1,5 GB libres. Tarda 20-60 minutos la primera vez.
rem  Deja tu ROM europea (16 MiB, .gba) en la carpeta "roms" antes de empezar,
rem  o pasala asi:  CONSTRUIR.bat -Rom D:\ruta\mi_rom.gba
rem  Si esta carpeta tiene espacios o acentos en la ruta, usa INSTALAR.bat (compila en
rem  un sitio seguro) o CONSTRUIR-MSYS2.bat (el metodo clasico).
rem ---------------------------------------------------------------------
cd /d "%~dp0"
title Mario Tennis Power Tour - construir
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\construir.ps1" %*
if errorlevel 1 (
    echo.
    echo La construccion ha fallado. Lee el mensaje de arriba.
    echo Si no consigues arreglarlo, prueba CONSTRUIR-MSYS2.bat (metodo clasico).
    pause
    exit /b 1
)
echo.
echo Listo. Abre la carpeta "juego" y ejecuta JUGAR.bat
pause
