<#
.SYNOPSIS
    Actualiza Mario Tennis: Power Tour sin tener que instalar todo desde cero.

.DESCRIPTION
    Úsalo cuando te llegue una versión nueva del proyecto (un zip nuevo): descomprímelo y
    ejecuta ACTUALIZAR.bat. Hace por ti lo que en una instalación tendrías que elegir a mano:

      1. encuentra solo dónde está instalado el juego («Aplicaciones» de Windows, la carpeta
         por defecto, los accesos directos o tus discos; si no lo encuentra, te lo pregunta),
      2. mira si la versión nueva trae algo distinto de la que tienes (si no, no hace nada),
      3. reutiliza la ROM que ya está en la carpeta del juego (no la vuelve a pedir),
      4. vuelve a compilar el juego con el mismo método de la instalación,
      5. lo copia encima de la instalación conservando tus partidas, ajustes y accesos directos.

    Si en la instalación marcaste «Conservar los archivos de compilación», la actualización
    solo recompila lo que ha cambiado y tarda minutos en vez de 20-60 minutos.

.PARAMETER Destino
    Carpeta donde está instalado el juego (si no se indica, se busca sola).

.PARAMETER Rom
    ROM europea, solo si no está ya en la carpeta del juego.

.PARAMETER Forzar
    Actualiza aunque la versión nueva sea idéntica a la instalada (útil para reparar).

.PARAMETER Silencioso
    No abre ventanas ni hace preguntas.

.PARAMETER ConservarObra
    Conserva los archivos de compilación al terminar (la próxima actualización será más rápida).

.PARAMETER Metodo
    auto (por defecto), ligero o msys2. Ver INSTALAR.ps1.

.EXAMPLE
    .\ACTUALIZAR.bat
    (doble clic)
#>
[CmdletBinding()]
param(
    [string]$Destino,
    [string]$Rom,
    [switch]$Forzar,
    [switch]$Silencioso,
    [switch]$ConservarObra,
    [ValidateSet('auto', 'ligero', 'msys2')][string]$Metodo = 'auto',
    [switch]$PruebaSeca,       # solo para probar el script: no compila (ver INSTALAR.ps1)
    [string]$JuegoPrueba
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comun.ps1')

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Escribir-Paso([string]$texto)  { Write-Host ''; Write-Host "== $texto" -ForegroundColor Cyan }
function Escribir-Info([string]$texto)  { Write-Host "   $texto" }
function Escribir-Ok([string]$texto)    { Write-Host "   [OK] $texto" -ForegroundColor Green }
function Escribir-Aviso([string]$texto) { Write-Host "   [!] $texto" -ForegroundColor Yellow }
function Fallo([string]$texto)          { throw $texto }

# ── Ventanas (solo Windows, con hilo STA) ─────────────────────────────────
$script:HayVentanas = $false
if ($EsWindows -and -not $Silencioso) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        [System.Windows.Forms.Application]::EnableVisualStyles()
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') { $script:HayVentanas = $true }
    } catch { $script:HayVentanas = $false }
}

function Mostrar-Mensaje([string]$texto, [string]$tipo = 'Info') {
    if (-not $script:HayVentanas) { return }
    $icono = switch ($tipo) {
        'Error' { [System.Windows.Forms.MessageBoxIcon]::Error }
        'Aviso' { [System.Windows.Forms.MessageBoxIcon]::Warning }
        default { [System.Windows.Forms.MessageBoxIcon]::Information }
    }
    [void][System.Windows.Forms.MessageBox]::Show($texto, "$NombreJuego - actualizar",
        [System.Windows.Forms.MessageBoxButtons]::OK, $icono)
}

function Preguntar-SiNo([string]$texto, [bool]$porDefecto) {
    if ($Silencioso) { return $porDefecto }
    if ($script:HayVentanas) {
        $r = [System.Windows.Forms.MessageBox]::Show($texto, "$NombreJuego - actualizar",
            [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    $sufijo = if ($porDefecto) { '[S/n]' } else { '[s/N]' }
    $resp = Read-Host "$texto $sufijo"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $porDefecto }
    return ($resp.Trim().ToLower() -in @('s', 'si', 'sí', 'y', 'yes'))
}

function Elegir-Carpeta([string]$descripcion) {
    if ($script:HayVentanas) {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = $descripcion
        $dlg.ShowNewFolderButton = $false
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
        return ''
    }
    if ($Silencioso) { return '' }
    return (Read-Host "$descripcion (vacío para cancelar)")
}

function Elegir-Rom {
    if ($script:HayVentanas) {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Elige tu ROM europea de Mario Tennis: Power Tour'
        $dlg.Filter = 'ROM de GBA (*.gba)|*.gba|Todos los archivos (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
        return ''
    }
    if ($Silencioso) { return '' }
    return (Read-Host 'Ruta de tu ROM europea (.gba)')
}

# ¿Está el juego abierto? No se puede sustituir el .exe mientras corre.
function Juego-Abierto([string]$carpeta) {
    $exe = [System.IO.Path]::GetFullPath((Join-Path $carpeta $ExeJuego))
    foreach ($p in @(Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($ExeJuego)) -ErrorAction SilentlyContinue)) {
        try { if ($p.Path -and ([System.IO.Path]::GetFullPath($p.Path) -ieq $exe)) { return $true } } catch { }
    }
    return $false
}

# ── Programa principal ────────────────────────────────────────────────────
try {
    Write-Host ''
    Write-Host "  $NombreJuego - actualizar" -ForegroundColor White
    Write-Host '  Reinstala la versión nueva encima de la tuya, sin empezar de cero.' -ForegroundColor DarkGray

    # 1. ¿Dónde está instalado?
    Escribir-Paso '1/4 Buscando tu instalación'
    $carpeta = ''
    $origen = ''
    if ($Destino) {
        $carpeta = [System.IO.Path]::GetFullPath($Destino.Trim().Trim('"'))
        $origen = 'el parámetro -Destino'
        if (-not (Es-Instalacion $carpeta)) { Fallo "En «$carpeta» no hay una instalación del juego (falta $ExeJuego)." }
    } else {
        $inst = Buscar-Instalacion
        if ($inst) { $carpeta = $inst.Carpeta; $origen = $inst.Origen }
    }
    while (-not $carpeta) {
        $texto = "No encuentro dónde está instalado $NombreJuego.`n`nElige la carpeta donde lo instalaste (la que contiene $ExeJuego)."
        if ($Silencioso) { Fallo 'No encuentro la instalación del juego. Indícala con -Destino <carpeta>.' }
        Escribir-Aviso 'No he encontrado la instalación sola.'
        Mostrar-Mensaje $texto 'Aviso'
        $elegida = Elegir-Carpeta 'Carpeta donde está instalado el juego'
        if ([string]::IsNullOrWhiteSpace($elegida)) {
            if (Preguntar-SiNo 'No hay nada que actualizar si no está instalado. ¿Quieres instalarlo ahora desde cero?' $true) {
                & (Join-Path $PSScriptRoot 'INSTALAR.ps1')
                return
            }
            Write-Host '  Actualización cancelada.'
            return
        }
        if (Es-Instalacion $elegida) { $carpeta = [System.IO.Path]::GetFullPath($elegida); $origen = 'tu elección' }
        else { Mostrar-Mensaje "En «$elegida» no está $ExeJuego. Prueba con otra carpeta." 'Aviso' }
    }
    $m = Leer-Manifiesto $carpeta
    Escribir-Ok "Instalación encontrada en $carpeta (por $origen)."
    $versionVieja = '(desconocida)'
    if ($m -and $m.version) { $versionVieja = [string]$m.version }
    $versionNueva = Leer-VersionProyecto $RaizProyecto
    Escribir-Info "Versión instalada: $versionVieja. Versión nueva: $versionNueva."

    # 2. ¿Hay algo nuevo?
    Escribir-Paso '2/4 Comparando con la versión nueva'
    $huellaNueva = Calcular-Huella $RaizProyecto
    $igual = ($m -and $m.huella -and ([string]$m.huella -eq $huellaNueva))
    if ($igual -and -not $Forzar -and (Icono-Distinto $carpeta)) {
        # Lo único nuevo es el icono: se aplica sin recompilar nada.
        $icono = Instalar-Icono $carpeta
        $n = Aplicar-IconoAccesos $m $icono
        Escribir-Ok "Icono nuevo aplicado ($n acceso(s) directo(s) cambiados). El juego no necesitaba más cambios."
        Mostrar-Mensaje "Icono actualizado.`nEl juego ya estaba en la última versión (v$versionVieja); no ha hecho falta recompilar nada.`n`nSi Windows sigue mostrando el icono anterior, cierra sesión o reinicia el Explorador de archivos." 'Info'
        exit 0
    }
    if ($igual -and -not $Forzar) {
        Escribir-Ok 'Ya tienes la última versión: no hay nada que actualizar.'
        Mostrar-Mensaje "Ya tienes la última versión instalada (v$versionVieja).`nNo hay nada que actualizar." 'Info'
        exit 0
    }
    if ($igual) { Escribir-Info 'La versión es idéntica, pero se reinstala porque has pedido forzarlo.' }
    else { Escribir-Ok 'Hay cambios respecto a lo que tienes instalado.' }

    $rapida = $false
    if ($m -and $m.obra -and (Test-Path -LiteralPath (Join-Path ([string]$m.obra) 'build'))) { $rapida = $true }
    $duracion = '20 a 60 minutos (hay que descargar las herramientas y compilar el juego entero)'
    if ($rapida) { $duracion = 'bastante menos que la primera vez (se reutilizan las herramientas y lo ya compilado que conservaste; si solo cambian cosas pequeñas, unos minutos)' }
    $texto = "Se va a actualizar $NombreJuego`n  de la versión $versionVieja a la $versionNueva`n  en $carpeta`n`n" +
             "Se conservan tus partidas, ajustes y accesos directos. Tardará $duracion.`n`n¿Actualizo ahora?"
    if (-not (Preguntar-SiNo $texto $true)) {
        Write-Host '  Actualización cancelada.'
        return
    }

    # 3. La ROM: la que ya está en la carpeta del juego
    Escribir-Paso '3/4 Preparando la actualización'
    $romRuta = ''
    $candidatas = @($Rom, (Join-Path $carpeta ('roms\' + $RomNombre)))
    foreach ($c in $candidatas) {
        if (-not $c) { continue }
        $r = Probar-Rom $c
        if ($r.Ok) { $romRuta = $r.Ruta; break }
        if ($c -eq $Rom) { Fallo $r.Mensaje }
    }
    if (-not $romRuta) { $romRuta = Buscar-Rom @((Join-Path $carpeta 'roms')) }
    while (-not $romRuta) {
        if ($Silencioso) { Fallo 'No encuentro tu ROM. Indícala con -Rom <ruta>.' }
        Mostrar-Mensaje 'No encuentro tu ROM en la carpeta del juego. Elige el archivo .gba europeo.' 'Aviso'
        $elegida = Elegir-Rom
        if ([string]::IsNullOrWhiteSpace($elegida)) { Write-Host '  Actualización cancelada.'; return }
        $r = Probar-Rom $elegida
        if ($r.Ok) { $romRuta = $r.Ruta } else { Mostrar-Mensaje $r.Mensaje 'Aviso' }
    }
    Escribir-Ok "ROM: $romRuta"

    if (Juego-Abierto $carpeta) {
        Mostrar-Mensaje 'El juego está abierto. Ciérralo y pulsa Aceptar para continuar.' 'Aviso'
        if (Juego-Abierto $carpeta) { Fallo 'El juego sigue abierto: ciérralo y vuelve a ejecutar ACTUALIZAR.' }
    }

    # 4. Reinstalar encima (INSTALAR.ps1 hace la compilación y la copia)
    Escribir-Paso '4/4 Compilando y actualizando (no cierres esta ventana)'
    $metodoUsar = $Metodo
    if ($metodoUsar -eq 'auto' -and $m -and $m.metodo -in @('ligero', 'msys2')) { $metodoUsar = [string]$m.metodo }
    $conservar = [bool]$ConservarObra -or [bool]($m -and $m.conservarObra)
    $argumentos = @{ Destino = $carpeta; Rom = $romRuta; Silencioso = $true; Actualizando = $true; Metodo = $metodoUsar }
    if ($conservar) { $argumentos['ConservarObra'] = $true }
    if ($PruebaSeca) { $argumentos['PruebaSeca'] = $true; $argumentos['JuegoPrueba'] = $JuegoPrueba }
    $inicio = Get-Date
    & (Join-Path $PSScriptRoot 'INSTALAR.ps1') @argumentos
    $codigo = $LASTEXITCODE
    if ($codigo -and $codigo -ne 0) { Fallo 'La actualización no se ha podido completar (mira los mensajes de arriba). Tu instalación anterior sigue como estaba.' }
    $minutos = [int]((Get-Date) - $inicio).TotalMinutes

    Escribir-Paso 'Listo'
    Escribir-Info "Actualizado a la versión $versionNueva en $carpeta (duración: $minutos min)."
    if (-not $Silencioso -and (Preguntar-SiNo '¡Actualización terminada! ¿Quieres abrir el juego ahora?' $true)) {
        Start-Process -FilePath (Join-Path $carpeta $ExeJuego) -WorkingDirectory $carpeta
    }
    exit 0
}
catch {
    $mensaje = $_.Exception.Message
    Write-Host ''
    Write-Host "ERROR: $mensaje" -ForegroundColor Red
    Mostrar-Mensaje "La actualización no se pudo completar:`n`n$mensaje" 'Error'
    if (-not $Silencioso) { [void](Read-Host 'Pulsa Intro para cerrar') }
    exit 1
}
