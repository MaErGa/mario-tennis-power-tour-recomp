@echo off
setlocal
chcp 65001 >nul
rem ---------------------------------------------------------------------
rem  CONSTRUIR-MSYS2.bat - de tu ROM al juego con el metodo clasico (MSYS2 + gcc).
rem  Es el respaldo de CONSTRUIR.bat (que es mucho mas ligero). Windows 10/11.
rem  Instala MSYS2 (con winget) y las herramientas la primera vez, recompila
rem  tu ROM y compila el juego. Necesita internet. Tarda 20-60 minutos.
rem  Deja tu ROM europea (16 MiB, .gba) en la carpeta "roms" antes de empezar.
rem ---------------------------------------------------------------------
cd /d "%~dp0"
title Mario Tennis Power Tour - construir (MSYS2)

set "MSYS=C:\msys64"
if not exist "%MSYS%\usr\bin\bash.exe" (
    echo.
    echo [1/3] Instalando MSYS2 con winget...
    winget install --id MSYS2.MSYS2 -e --accept-source-agreements --accept-package-agreements
    if not exist "%MSYS%\usr\bin\bash.exe" (
        echo.
        echo No se ha podido instalar MSYS2 automaticamente.
        echo Instalalo a mano desde https://www.msys2.org/ en C:\msys64 y vuelve a ejecutar este archivo.
        pause
        exit /b 1
    )
)

echo.
echo [2/3] Instalando herramientas de compilacion (gcc, cmake, ninja, SDL2, git, python)...
"%MSYS%\usr\bin\bash.exe" -lc "pacman -Sy --noconfirm --needed git mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-SDL2 mingw-w64-x86_64-python"
if errorlevel 1 (
    echo.
    echo Fallo al instalar las herramientas. Revisa la conexion a internet y vuelve a intentarlo.
    pause
    exit /b 1
)

echo.
echo [3/3] Recompilando tu ROM y compilando el juego...
set "MSYSTEM=MINGW64"
set "CHERE_INVOKING=1"
"%MSYS%\usr\bin\bash.exe" -lc "./tools/construir.sh %*"
if errorlevel 1 (
    echo.
    echo La construccion ha fallado. Lee el mensaje de arriba.
    pause
    exit /b 1
)

echo.
echo Listo. Abre la carpeta "juego" y ejecuta JUGAR.bat
pause
