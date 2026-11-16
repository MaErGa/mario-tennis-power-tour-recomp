<#
.SYNOPSIS
    Pruebas del desinstalador (tools/DESINSTALAR.ps1) en modo «PruebaSeca»: qué borra y qué conserva.

.DESCRIPTION
    Monta una instalación falsa en una carpeta temporal (sin tocar el registro ni el sistema),
    ejecuta el desinstalador de verdad y comprueba que:
      - con -ConservarPartidas quedan las partidas (.sav y sus copias), config.ini, keybinds.ini y
        la carpeta capturas, y se borra todo lo demás;
      - sin -ConservarPartidas no queda nada.
    Funciona con PowerShell 5.1 (Windows) y con PowerShell 7 (Windows, Linux, macOS).
#>
$ErrorActionPreference = 'Stop'
$tools = Split-Path -Parent $PSScriptRoot
$desinstalador = Join-Path $tools 'DESINSTALAR.ps1'
$pwsh = (Get-Process -Id $PID).Path
$fallos = 0
function Comprobar([string]$nombre, [bool]$condicion) {
    if ($condicion) { Write-Host "  ok    $nombre" }
    else { Write-Host "  FALLA $nombre"; $script:fallos++ }
}

function Montar-Instalacion {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ('mtp-desinst-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $carpeta = Join-Path $base 'Mario Tennis Power Tour'
    New-Item -ItemType Directory -Force -Path (Join-Path $carpeta 'roms') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $carpeta 'capturas') | Out-Null
    Copy-Item -LiteralPath $desinstalador -Destination (Join-Path $carpeta 'Desinstalar.ps1')
    Set-Content -LiteralPath (Join-Path $carpeta 'instalacion.json') -Value '{ "producto": "MarioTennisPowerTourRecomp", "accesos": [], "registro": null, "obra": null }'
    foreach ($f in @('MarioTennisPowerTourRecomp.exe', 'SDL2.dll', 'roms/mario_tennis.sav', 'roms/mario_tennis.sav.copia1',
                     'config.ini', 'keybinds.ini', 'capturas/MarioTennis_2026-11-11_10-00-00.png', 'capturas/otra.png')) {
        Set-Content -LiteralPath (Join-Path $carpeta $f) -Value 'x'
    }
    return $carpeta
}

function Ejecutar([string]$carpeta, [string[]]$extra) {
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $carpeta 'Desinstalar.ps1') -Silencioso -PruebaSeca @extra | Out-Null
    return $LASTEXITCODE
}

Write-Host 'Desinstalar conservando partidas, ajustes y capturas'
$c = Montar-Instalacion
$codigo = Ejecutar $c @('-ConservarPartidas')
Comprobar 'termina bien' ($codigo -eq 0)
Comprobar 'conserva la partida' (Test-Path -LiteralPath (Join-Path $c 'roms/mario_tennis.sav'))
Comprobar 'conserva la copia de la partida' (Test-Path -LiteralPath (Join-Path $c 'roms/mario_tennis.sav.copia1'))
Comprobar 'conserva config.ini y keybinds.ini' ((Test-Path -LiteralPath (Join-Path $c 'config.ini')) -and (Test-Path -LiteralPath (Join-Path $c 'keybinds.ini')))
Comprobar 'conserva las capturas' ((Test-Path -LiteralPath (Join-Path $c 'capturas/MarioTennis_2026-11-11_10-00-00.png')) -and (Test-Path -LiteralPath (Join-Path $c 'capturas/otra.png')))
Comprobar 'borra el ejecutable y las DLL' (-not (Test-Path -LiteralPath (Join-Path $c 'MarioTennisPowerTourRecomp.exe')) -and -not (Test-Path -LiteralPath (Join-Path $c 'SDL2.dll')))
Remove-Item -LiteralPath (Split-Path -Parent $c) -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Desinstalar sin conservar nada'
$c = Montar-Instalacion
$codigo = Ejecutar $c @()
Comprobar 'termina bien' ($codigo -eq 0)
Comprobar 'no queda ninguna partida ni captura' (-not (Test-Path -LiteralPath (Join-Path $c 'roms/mario_tennis.sav')) -and -not (Test-Path -LiteralPath (Join-Path $c 'capturas/otra.png')))
Comprobar 'no queda la configuración' (-not (Test-Path -LiteralPath (Join-Path $c 'config.ini')))
Remove-Item -LiteralPath (Split-Path -Parent $c) -Recurse -Force -ErrorAction SilentlyContinue

if ($fallos -gt 0) { Write-Host "`n$fallos prueba(s) fallida(s)."; exit 1 }
Write-Host "`nTodas las pruebas del desinstalador han pasado."
