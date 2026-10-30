<#
.SYNOPSIS
    Desinstalador de Mario Tennis: Power Tour (versión nativa para PC).

.DESCRIPTION
    Se copia a la carpeta de instalación como «Desinstalar.ps1». Lee instalacion.json
    (que dejó el instalador) y quita los accesos directos, la entrada de «Aplicaciones»
    de Windows y los archivos del juego. Te pregunta si quieres conservar tus partidas
    guardadas y tus ajustes. No toca MSYS2 (otros programas pueden usarlo).

.PARAMETER Silencioso
    No pregunta nada. Borra todo salvo que se pase -ConservarPartidas.

.PARAMETER ConservarPartidas
    Deja los archivos .sav (partidas), config.ini y keybinds.ini.

.PARAMETER PruebaSeca
    Solo para probar: no toca el registro de Windows ni espera para borrarse a sí mismo.
#>
[CmdletBinding()]
param(
    [switch]$Silencioso,
    [switch]$ConservarPartidas,
    [switch]$PruebaSeca
)

$ErrorActionPreference = 'Stop'
$NombreJuego = 'Mario Tennis Power Tour'
$ExeJuego    = 'MarioTennisPowerTourRecomp.exe'
$EsWindows   = ($PSVersionTable.PSEdition -ne 'Core') -or ($IsWindows -eq $true)
$carpeta     = $PSScriptRoot

$HayVentanas = $false
if ($EsWindows -and -not $Silencioso) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') { $HayVentanas = $true }
    } catch { $HayVentanas = $false }
}

function Preguntar-SiNo([string]$texto, [bool]$porDefecto) {
    if ($Silencioso) { return $porDefecto }
    if ($HayVentanas) {
        $r = [System.Windows.Forms.MessageBox]::Show($texto, "Desinstalar $NombreJuego",
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    $sufijo = if ($porDefecto) { '[S/n]' } else { '[s/N]' }
    $resp = Read-Host "$texto $sufijo"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $porDefecto }
    return ($resp.Trim().ToLower() -in @('s', 'si', 'sí', 'y', 'yes'))
}

function Avisar([string]$texto, [string]$tipo = 'Info') {
    Write-Host $texto
    if ($HayVentanas) {
        $icono = if ($tipo -eq 'Error') { [System.Windows.Forms.MessageBoxIcon]::Error } else { [System.Windows.Forms.MessageBoxIcon]::Information }
        [void][System.Windows.Forms.MessageBox]::Show($texto, "Desinstalar $NombreJuego",
            [System.Windows.Forms.MessageBoxButtons]::OK, $icono)
    }
}

try {
    $manifiesto = Join-Path $carpeta 'instalacion.json'
    if (-not (Test-Path -LiteralPath $manifiesto)) {
        throw 'No encuentro instalacion.json. Este script debe estar en la carpeta donde se instaló el juego.'
    }
    $m = Get-Content -LiteralPath $manifiesto -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($m.producto -ne 'MarioTennisPowerTourRecomp') {
        throw 'instalacion.json no es de este juego; no borro nada.'
    }
    # Salvaguarda: solo se borra una carpeta que parezca de verdad una instalación nuestra.
    $raiz = [System.IO.Path]::GetPathRoot($carpeta)
    if ($carpeta.TrimEnd('\', '/') -ieq $raiz.TrimEnd('\', '/')) {
        throw 'Estoy en la raíz de una unidad; no borro nada.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $carpeta $ExeJuego)) -and -not (Test-Path -LiteralPath (Join-Path $carpeta 'game.toml'))) {
        throw "En «$carpeta» no está el juego (falta $ExeJuego); no borro nada."
    }

    if (-not $Silencioso) {
        if (-not (Preguntar-SiNo "¿Desinstalar $NombreJuego de:`n$carpeta ?" $true)) {
            Write-Host 'Cancelado. No se ha borrado nada.'
            return
        }
        if (-not $ConservarPartidas) {
            $ConservarPartidas = Preguntar-SiNo "¿Quieres conservar tus partidas guardadas y tus ajustes (archivos .sav, config.ini, keybinds.ini)?`n`n(Si más adelante vuelves a instalar el juego en esta carpeta, las recuperarás.)" $true
        }
    }

    # Accesos directos
    foreach ($a in @($m.accesos)) {
        if ($a -and (Test-Path -LiteralPath $a)) { Remove-Item -LiteralPath $a -Force -ErrorAction SilentlyContinue }
        if ($a) {
            $padre = Split-Path -Parent $a
            # La carpeta del menú Inicio se quita si se queda vacía.
            if ((Split-Path -Leaf $padre) -eq $NombreJuego -and (Test-Path -LiteralPath $padre) -and
                -not (Get-ChildItem -LiteralPath $padre -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $padre -Force -ErrorAction SilentlyContinue
            }
        }
    }
    # Entrada de «Aplicaciones» de Windows
    if ($m.registro -and -not $PruebaSeca -and $EsWindows) {
        Remove-Item -LiteralPath $m.registro -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Archivos: todo menos este script (y, si se piden, las partidas y los ajustes).
    $yo = $MyInvocation.MyCommand.Path
    $conservados = 0
    Get-ChildItem -LiteralPath $carpeta -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.FullName -ieq $yo) { return }
        $guardar = $ConservarPartidas -and (
            $_.Extension -ieq '.sav' -or
            ($_.DirectoryName.TrimEnd('\', '/') -ieq $carpeta.TrimEnd('\', '/') -and $_.Name -in @('config.ini', 'keybinds.ini', 'instalacion.json')))
        if ($guardar) { $conservados++; return }
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
    }
    # Carpetas vacías (de dentro hacia fuera)
    Get-ChildItem -LiteralPath $carpeta -Force -Recurse -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }

    # Este script y la carpeta se borran al terminar (no se puede borrar un script en ejecución).
    if ($EsWindows -and -not $PruebaSeca) {
        $orden = "ping 127.0.0.1 -n 3 >nul & del /f /q `"$yo`" & rmdir `"$carpeta`""
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $orden -WindowStyle Hidden
    } elseif ($PruebaSeca) {
        Remove-Item -LiteralPath $yo -Force -ErrorAction SilentlyContinue
        if (-not (Get-ChildItem -LiteralPath $carpeta -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $carpeta -Force -ErrorAction SilentlyContinue
        }
    }

    $final = "$NombreJuego se ha desinstalado."
    if ($conservados -gt 0) { $final += " Se han conservado tus partidas y ajustes en:`n$carpeta" }
    if ($m.obra) { $final += "`n(MSYS2 no se ha tocado; puedes quitarlo desde «Aplicaciones» si ya no lo necesitas.)" }
    Avisar $final
    exit 0
}
catch {
    Avisar "No se pudo desinstalar: $($_.Exception.Message)" 'Error'
    exit 1
}
