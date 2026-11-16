<#
.SYNOPSIS
    Importa, exporta y guarda copias de las partidas de Mario Tennis: Power Tour.

.DESCRIPTION
    La partida del juego es un archivo .sav de 32 KiB (SRAM), el mismo formato que usan
    mGBA, VisualBoyAdvance-M, RetroArch (.srm), BizHawk, no$gba, los flashcarts, etc.
    Este script permite pasar partidas de un emulador al juego y del juego a un emulador.
    Antes de sustituir tu partida actual siempre guarda una copia en «copias-de-partidas».

    Sin parámetros abre un menú. También se puede usar desde la línea de órdenes.

    NO sirve para «estados rápidos» (save states) de un emulador: son volcados de la memoria
    de ESE emulador y no se pueden convertir. Hay que usar la partida normal del juego
    (la que se guarda desde el propio juego, el archivo .sav / .srm).

.PARAMETER Accion
    Importar | Exportar | Copia | Restaurar | Abrir. Si se omite, se muestra un menú.

.PARAMETER Archivo
    Importar: archivo .sav/.srm que se quiere traer. Exportar: dónde se guarda la copia.
    Restaurar: copia concreta de «copias-de-partidas».

.PARAMETER Carpeta
    Carpeta donde está instalado el juego. Si no se indica, se busca sola.

.PARAMETER Silencioso
    No pregunta nada ni abre ventanas (da por buenas las confirmaciones).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File Partidas.ps1 -Accion Importar -Archivo D:\mgba\mario.sav
#>
[CmdletBinding()]
param(
    [ValidateSet('', 'Importar', 'Exportar', 'Copia', 'Restaurar', 'Abrir')]
    [string]$Accion = '',
    [string]$Archivo = '',
    [string]$Carpeta = '',
    [switch]$Silencioso
)

$ErrorActionPreference = 'Stop'
$NombreJuego   = 'Mario Tennis Power Tour'
$ExeJuego      = 'MarioTennisPowerTourRecomp.exe'
$RomNombre     = 'mario_tennis_power_tour_eur.gba'
$ClaveRegistro = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MarioTennisPowerTourRecomp'
$TamanoSram    = 32768
$CarpetaCopias = 'copias-de-partidas'
$EsWindows     = ($PSVersionTable.PSEdition -ne 'Core') -or ($IsWindows -eq $true)

$HayVentanas = $false
if ($EsWindows -and -not $Silencioso) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') { $HayVentanas = $true }
    } catch { $HayVentanas = $false }
}

# ── Mensajes y preguntas (ventanas si se puede, consola si no) ─────────────
function Avisar([string]$texto, [string]$tipo = 'Info') {
    Write-Host $texto
    if ($HayVentanas) {
        $icono = [System.Windows.Forms.MessageBoxIcon]::Information
        if ($tipo -eq 'Error') { $icono = [System.Windows.Forms.MessageBoxIcon]::Error }
        if ($tipo -eq 'Aviso') { $icono = [System.Windows.Forms.MessageBoxIcon]::Warning }
        [void][System.Windows.Forms.MessageBox]::Show($texto, "Partidas de $NombreJuego",
            [System.Windows.Forms.MessageBoxButtons]::OK, $icono)
    }
}

function Preguntar-SiNo([string]$texto, [bool]$porDefecto) {
    if ($Silencioso) { return $true }
    if ($HayVentanas) {
        $r = [System.Windows.Forms.MessageBox]::Show($texto, "Partidas de $NombreJuego",
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    $sufijo = '[s/N]'
    if ($porDefecto) { $sufijo = '[S/n]' }
    $resp = Read-Host "$texto $sufijo"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $porDefecto }
    return ($resp.Trim().ToLower() -in @('s', 'si', 'sí', 'y', 'yes'))
}

function Elegir-ArchivoAbrir([string]$titulo, [string]$filtro, [string]$inicial) {
    if ($HayVentanas) {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = $titulo
        $dlg.Filter = $filtro
        if ($inicial -and (Test-Path -LiteralPath $inicial -PathType Container)) { $dlg.InitialDirectory = $inicial }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
        return ''
    }
    return (Read-Host "$titulo (ruta del archivo, vacío para cancelar)").Trim().Trim('"')
}

function Elegir-ArchivoGuardar([string]$titulo, [string]$nombre, [string]$inicial) {
    if ($HayVentanas) {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = $titulo
        $dlg.Filter = 'Partida de GBA (*.sav)|*.sav|Partida de RetroArch (*.srm)|*.srm|Todos los archivos (*.*)|*.*'
        $dlg.FileName = $nombre
        if ($inicial -and (Test-Path -LiteralPath $inicial -PathType Container)) { $dlg.InitialDirectory = $inicial }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
        return ''
    }
    return (Read-Host "$titulo (ruta del archivo de destino, vacío para cancelar)").Trim().Trim('"')
}

# ── Dónde está el juego y su partida ───────────────────────────────────────
function Es-Instalacion([string]$ruta) {
    if (-not $ruta -or -not (Test-Path -LiteralPath $ruta -PathType Container)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $ruta $ExeJuego) -PathType Leaf) -or
           (Test-Path -LiteralPath (Join-Path $ruta 'game.toml') -PathType Leaf)
}

function Buscar-Carpeta([string]$indicada) {
    $candidatas = @()
    if ($indicada) { $candidatas += $indicada }
    $candidatas += $PSScriptRoot
    if ($EsWindows) {
        try { $candidatas += (Get-ItemProperty -Path $ClaveRegistro -ErrorAction Stop).InstallLocation } catch { }
    }
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    if ($local) { $candidatas += (Join-Path (Join-Path $local 'Programs') $NombreJuego) }
    foreach ($c in $candidatas) {
        if (Es-Instalacion $c) { return (Resolve-Path -LiteralPath $c).ProviderPath }
    }
    return ''
}

# La partida es el .sav que está junto a la ROM que usa el juego (rom.cfg, o roms\ por defecto).
function Ruta-Partida([string]$carpeta) {
    $rom = Join-Path (Join-Path $carpeta 'roms') $RomNombre
    $cfg = Join-Path $carpeta 'rom.cfg'
    if (Test-Path -LiteralPath $cfg -PathType Leaf) {
        $linea = (Get-Content -LiteralPath $cfg -TotalCount 1 -ErrorAction SilentlyContinue)
        if ($linea) {
            $linea = ([string]$linea).Trim().Trim('"')
            if ($linea) {
                if (-not [System.IO.Path]::IsPathRooted($linea)) { $linea = Join-Path $carpeta $linea }
                $rom = $linea
            }
        }
    }
    return [System.IO.Path]::ChangeExtension($rom, '.sav')
}

function Juego-Abierto {
    $p = Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($ExeJuego)) -ErrorAction SilentlyContinue
    return [bool]$p
}

# ── Comprobación de una partida ────────────────────────────────────────────
# Devuelve @{ Ok; Datos; Notas; Error }. Datos son los bytes que se usarían (recortados a 32 KiB
# si el archivo traía relleno de más).
function Probar-Sav([byte[]]$datos, [string]$nombreArchivo) {
    $notas = New-Object System.Collections.ArrayList
    $ext = [System.IO.Path]::GetExtension($nombreArchivo).ToLower()
    $explicacionEstado = "Eso parece un estado rápido (save state) de un emulador, no una partida. Los estados rápidos son volcados de la memoria de ESE emulador y no valen aquí.`nUsa la partida normal del juego: guarda desde el propio juego dentro del emulador y busca el archivo .sav (mGBA, VBA-M, no`$gba) o .srm (RetroArch) junto a la ROM o en su carpeta de partidas."
    if ($ext -match '^\.(state|ss\d|st\d|sgm|sps|oops|gqs)$') {
        return @{ Ok = $false; Error = $explicacionEstado }
    }
    if ($datos.Length -eq 0) {
        return @{ Ok = $false; Error = 'El archivo está vacío.' }
    }
    if ($datos.Length -ge 8 -and $datos.Length -ne $TamanoSram) {
        # (Un archivo de exactamente 32 KiB es una partida en bruto: no se mira su cabecera.)
        $cab = [System.Text.Encoding]::ASCII.GetString($datos, 0, 7)
        if ($cab.StartsWith('PK') -or ($datos[0] -eq 0x1F -and $datos[1] -eq 0x8B) -or $cab.StartsWith('RASTATE') -or
            ($datos[0] -eq 0x89 -and $cab.Substring(1).StartsWith('PNG'))) {
            return @{ Ok = $false; Error = $explicacionEstado + "`n(El archivo está comprimido o es un estado de RetroArch/mGBA: descomprímelo o elige el .sav.)" }
        }
    }
    $resultado = $datos
    if ($datos.Length -gt $TamanoSram) {
        # ¿Lo que sobra es relleno (todo 0x00 o todo 0xFF) o una copia repetida de los primeros 32 KiB?
        $primero = $datos[$TamanoSram]
        $relleno = ($primero -eq 0x00 -or $primero -eq 0xFF)
        $espejo = (($datos.Length % $TamanoSram) -eq 0)
        for ($i = $TamanoSram; $i -lt $datos.Length -and ($relleno -or $espejo); $i++) {
            if ($relleno -and $datos[$i] -ne $primero) { $relleno = $false }
            if ($espejo -and $datos[$i] -ne $datos[($i % $TamanoSram)]) { $espejo = $false }
        }
        if (-not $relleno -and -not $espejo) {
            return @{ Ok = $false; Error = ("El archivo mide $($datos.Length) bytes y esta partida debería medir $TamanoSram (32 KiB), pero lo que sobra no es relleno: " +
                "parece de otro tipo de guardado (Flash o EEPROM), de otro juego o de un programa que guarda en otro formato.`n" +
                "Este juego guarda en SRAM de 32 KiB. Comprueba que el archivo es de Mario Tennis: Power Tour y no un estado rápido.") }
        }
        $resultado = New-Object byte[] $TamanoSram
        [Array]::Copy($datos, $resultado, $TamanoSram)
        [void]$notas.Add("El archivo medía $($datos.Length) bytes: lo que sobraba era relleno, así que se han usado los primeros $TamanoSram (32 KiB).")
    }
    elseif ($datos.Length -lt $TamanoSram) {
        # Una SRAM sin escribir vale 0xFF en cualquier emulador: se completa así hasta los 32 KiB estándar.
        $resultado = New-Object byte[] $TamanoSram
        for ($i = 0; $i -lt $TamanoSram; $i++) { $resultado[$i] = 0xFF }
        [Array]::Copy($datos, $resultado, $datos.Length)
        [void]$notas.Add("El archivo medía solo $($datos.Length) bytes (lo normal son $TamanoSram): se ha completado hasta los 32 KiB.")
    }
    $vacia = $true
    foreach ($b in $resultado) { if ($b -ne 0x00 -and $b -ne 0xFF) { $vacia = $false; break } }
    if ($vacia) { [void]$notas.Add('Ojo: esta partida está vacía (solo bytes 0x00 o 0xFF): no contiene ningún progreso.') }
    return @{ Ok = $true; Datos = $resultado; Notas = @($notas); Vacia = $vacia }
}

# ── Acciones ───────────────────────────────────────────────────────────────
function Escribir-Atomico([string]$ruta, [byte[]]$datos) {
    $tmp = "$ruta.nueva"
    [System.IO.File]::WriteAllBytes($tmp, $datos)
    if (Test-Path -LiteralPath $ruta) { Remove-Item -LiteralPath $ruta -Force }
    Move-Item -LiteralPath $tmp -Destination $ruta -Force
}

function Hacer-Copia([string]$carpeta, [string]$partida, [string]$motivo) {
    if (-not (Test-Path -LiteralPath $partida -PathType Leaf)) { return '' }
    $dir = Join-Path $carpeta $CarpetaCopias
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $sello = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $destino = Join-Path $dir "partida_${sello}_$motivo.sav"
    $n = 2
    while (Test-Path -LiteralPath $destino) { $destino = Join-Path $dir "partida_${sello}_${motivo}_$n.sav"; $n++ }
    Copy-Item -LiteralPath $partida -Destination $destino
    return $destino
}

function Comprobar-JuegoCerrado {
    if (Juego-Abierto) {
        throw 'El juego está abierto. Ciérralo antes de tocar las partidas (si no, al cerrarse volvería a guardar la partida anterior).'
    }
}

function Importar-Partida([string]$carpeta, [string]$origen, [string]$titulo, [bool]$restaurando = $false) {
    Comprobar-JuegoCerrado
    if (-not $origen) {
        $origen = Elegir-ArchivoAbrir $titulo 'Partidas de GBA (*.sav;*.srm)|*.sav;*.srm|Todos los archivos (*.*)|*.*' ''
        if (-not $origen) { Write-Host 'Cancelado. No se ha cambiado nada.'; return }
    }
    $origen = $origen.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $origen -PathType Leaf)) { throw "No existe el archivo: $origen" }
    $r = Probar-Sav ([System.IO.File]::ReadAllBytes($origen)) $origen
    if (-not $r.Ok) { throw $r.Error }
    $partida = Ruta-Partida $carpeta
    $texto = "Se va a usar esta partida:`n$origen`n"
    if ($restaurando) { $texto = "Se va a recuperar esta copia:`n$origen`n" }
    foreach ($n in $r.Notas) { $texto += "`n• $n" }
    if (Test-Path -LiteralPath $partida -PathType Leaf) {
        $texto += "`n`nTu partida actual se guardará antes en «$CarpetaCopias» (no se pierde)."
    }
    $texto += "`n`n¿Continuar?"
    if (-not (Preguntar-SiNo $texto $true)) { Write-Host 'Cancelado. No se ha cambiado nada.'; return }
    $copia = Hacer-Copia $carpeta $partida 'antes-de-importar'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $partida) | Out-Null
    Escribir-Atomico $partida $r.Datos
    $mensaje = 'Partida importada. Al abrir el juego aparecerá tu progreso.'
    if ($restaurando) { $mensaje = 'Copia recuperada. Al abrir el juego aparecerá tu progreso.' }
    if ($copia) { $mensaje += "`nTu partida anterior está en: $copia" }
    foreach ($n in $r.Notas) { $mensaje += "`n• $n" }
    Avisar $mensaje
}

function Exportar-Partida([string]$carpeta, [string]$destino) {
    $partida = Ruta-Partida $carpeta
    if (-not (Test-Path -LiteralPath $partida -PathType Leaf)) {
        throw 'Todavía no hay ninguna partida guardada. Juega y guarda dentro del juego primero.'
    }
    if (-not $destino) {
        $escritorio = [Environment]::GetFolderPath('Desktop')
        $destino = Elegir-ArchivoGuardar 'Guardar la partida para un emulador' 'Mario Tennis - Power Tour (Europe).sav' $escritorio
        if (-not $destino) { Write-Host 'Cancelado.'; return }
    }
    $destino = $destino.Trim().Trim('"')
    $dir = Split-Path -Parent $destino
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    # Siempre se exportan los 32 KiB estándar (aunque el archivo del juego traiga relleno de más).
    $r = Probar-Sav ([System.IO.File]::ReadAllBytes($partida)) $partida
    if (-not $r.Ok) { throw $r.Error }
    [System.IO.File]::WriteAllBytes($destino, $r.Datos)
    Avisar ("Partida exportada a:`n$destino`n`n" +
        "Para usarla en un emulador, ponla junto a tu ROM con EL MISMO NOMBRE que la ROM y la extensión .sav " +
        "(RetroArch: carpeta «saves», extensión .srm). Ejemplo: «Mario Tennis - Power Tour (Europe).gba» → «Mario Tennis - Power Tour (Europe).sav».")
}

function Crear-CopiaAhora([string]$carpeta) {
    $partida = Ruta-Partida $carpeta
    if (-not (Test-Path -LiteralPath $partida -PathType Leaf)) {
        throw 'Todavía no hay ninguna partida guardada. Juega y guarda dentro del juego primero.'
    }
    $copia = Hacer-Copia $carpeta $partida 'manual'
    Avisar "Copia de seguridad creada:`n$copia"
}

function Restaurar-Copia([string]$carpeta, [string]$elegida) {
    Comprobar-JuegoCerrado
    $dir = Join-Path $carpeta $CarpetaCopias
    if ($elegida -and -not (Test-Path -LiteralPath $elegida -PathType Leaf)) { throw "No existe la copia: $elegida" }
    if (-not $elegida) {
        $copias = @()
        if (Test-Path -LiteralPath $dir -PathType Container) {
            $copias = @(Get-ChildItem -LiteralPath $dir -Filter '*.sav' -File | Sort-Object LastWriteTime -Descending)
        }
        if ($copias.Count -eq 0) { throw 'No hay copias de seguridad todavía.' }
        if ($HayVentanas) {
            $elegida = Elegir-ArchivoAbrir 'Elige la copia que quieres recuperar' 'Copias de partidas (*.sav)|*.sav' $dir
        } else {
            for ($i = 0; $i -lt $copias.Count; $i++) {
                Write-Host ("  {0,2}) {1}  ({2})" -f ($i + 1), $copias[$i].Name, $copias[$i].LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
            }
            $n = Read-Host 'Número de la copia que quieres recuperar (vacío para cancelar)'
            if ([string]::IsNullOrWhiteSpace($n)) { $elegida = '' }
            else {
                $k = 0
                if (-not [int]::TryParse($n.Trim(), [ref]$k) -or $k -lt 1 -or $k -gt $copias.Count) { throw 'Número no válido.' }
                $elegida = $copias[$k - 1].FullName
            }
        }
        if (-not $elegida) { Write-Host 'Cancelado. No se ha cambiado nada.'; return }
    }
    Importar-Partida $carpeta $elegida 'Elige la copia que quieres recuperar' $true
}

function Abrir-Carpeta([string]$carpeta) {
    $dir = Split-Path -Parent (Ruta-Partida $carpeta)
    if ($EsWindows) { Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$dir`"" }
    else { Write-Host $dir }
}

function Ejecutar([string]$que, [string]$carpeta) {
    switch ($que) {
        'Importar'  { Importar-Partida $carpeta $Archivo 'Elige la partida (.sav / .srm) de tu emulador' }
        'Exportar'  { Exportar-Partida $carpeta $Archivo }
        'Copia'     { Crear-CopiaAhora $carpeta }
        'Restaurar' { Restaurar-Copia $carpeta $Archivo }
        'Abrir'     { Abrir-Carpeta $carpeta }
    }
}

# ── Programa ───────────────────────────────────────────────────────────────
try {
    $carpeta = Buscar-Carpeta $Carpeta
    if (-not $carpeta) {
        throw 'No encuentro dónde está instalado el juego. Ejecuta este programa desde la carpeta del juego o indica -Carpeta <ruta>.'
    }
    if ($Accion) {
        Ejecutar $Accion $carpeta
        exit 0
    }
    # Menú de consola (se abre desde Partidas.bat).
    while ($true) {
        Write-Host ''
        Write-Host "  Partidas de $NombreJuego"
        Write-Host "  Partida actual: $(Ruta-Partida $carpeta)"
        Write-Host ''
        Write-Host '   1) Importar una partida de un emulador (.sav / .srm)'
        Write-Host '   2) Exportar mi partida para usarla en un emulador'
        Write-Host '   3) Crear una copia de seguridad ahora'
        Write-Host '   4) Recuperar una copia de seguridad'
        Write-Host '   5) Abrir la carpeta de la partida'
        Write-Host '   0) Salir'
        $op = (Read-Host 'Elige una opción').Trim()
        $que = ''
        switch ($op) { '1' { $que = 'Importar' } '2' { $que = 'Exportar' } '3' { $que = 'Copia' } '4' { $que = 'Restaurar' } '5' { $que = 'Abrir' } '0' { exit 0 } default { Write-Host 'Opción no válida.' } }
        if ($que) {
            try { Ejecutar $que $carpeta } catch { Avisar "No se pudo: $($_.Exception.Message)" 'Error' }
        }
    }
}
catch {
    Avisar "No se pudo: $($_.Exception.Message)" 'Error'
    exit 1
}
