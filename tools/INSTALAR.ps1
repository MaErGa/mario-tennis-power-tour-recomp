<#
.SYNOPSIS
    Instalador de Mario Tennis: Power Tour (versión nativa para PC, Windows 10/11).

.DESCRIPTION
    Abre una ventana donde eliges tu ROM europea y la carpeta donde quieres
    instalar el juego. Después, sin que tengas que hacer nada más:
      1. comprueba la ROM (tamaño y SHA-1),
      2. descarga unas herramientas de compilación ligeras (Zig, CMake, Ninja y SDL2:
         unos 150 MB) — o, si eso falla, usa MSYS2 como respaldo,
      3. recompila tu ROM y compila el juego (20-60 minutos la primera vez),
      4. copia el juego a la carpeta que elegiste (con tu ROM y la BIOS libre),
      5. crea los accesos directos y una entrada en «Aplicaciones» de Windows,
      6. deja un desinstalador en esa misma carpeta,
      7. borra todo lo temporal (salvo que pidas conservarlo para actualizar más rápido).

    No hace falta ser administrador (solo si el método de respaldo, MSYS2, lo pidiera).
    La ROM no se sube ni se envía a ningún sitio: se queda en tu equipo.
    Para actualizar una instalación existente sin repetir nada, usa ACTUALIZAR.bat.

.PARAMETER Destino
    Carpeta de instalación. Si no se indica, se pregunta (por defecto:
    %LOCALAPPDATA%\Programs\Mario Tennis Power Tour).

.PARAMETER Rom
    Ruta de tu ROM (.gba). Si no se indica, se busca en roms\, Descargas, Escritorio
    y Documentos, y si no aparece se pregunta.

.PARAMETER SinAccesos
    No crea accesos directos ni la entrada en «Aplicaciones».

.PARAMETER Silencioso
    No abre ventanas ni hace preguntas (usa los parámetros y los valores por defecto).

.PARAMETER ConservarObra
    No borra la carpeta temporal de compilación al terminar (ocupa ~1 GB, pero reinstalar o
    actualizar pasa a tardar minutos).

.PARAMETER Metodo
    auto (por defecto): compilación ligera con Zig y, si falla, MSYS2.
    ligero: solo Zig. msys2: solo MSYS2 (el método clásico).

.PARAMETER Actualizando
    Lo usa ACTUALIZAR.ps1: reinstala encima de una instalación existente sin tocar los
    accesos directos ni preguntar nada.

.PARAMETER Msys2
    Carpeta de MSYS2 para el método de respaldo (por defecto C:\msys64).

.PARAMETER PruebaSeca
    Solo para probar el instalador: no instala MSYS2 ni compila; usa -JuegoPrueba como
    si fuera la carpeta «juego» ya compilada.

.PARAMETER JuegoPrueba
    Con -PruebaSeca, carpeta que hace de «juego» compilado (debe contener el .exe).

.EXAMPLE
    .\INSTALAR.bat
    (doble clic: abre la ventana del instalador)

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\INSTALAR.ps1 -Rom D:\roms\mtpt.gba -Destino E:\Juegos\MarioTennis -Silencioso
#>
[CmdletBinding()]
param(
    [string]$Destino,
    [string]$Rom,
    [switch]$SinAccesos,
    [switch]$Silencioso,
    [switch]$ConservarObra,
    [ValidateSet('auto', 'ligero', 'msys2')][string]$Metodo = 'auto',
    [switch]$Actualizando,
    [string]$Msys2 = 'C:\msys64',
    [switch]$PruebaSeca,
    [string]$JuegoPrueba
)

$ErrorActionPreference = 'Stop'

# ── Constantes y funciones compartidas con ACTUALIZAR.ps1 ──────────────────
. (Join-Path $PSScriptRoot 'comun.ps1')
$EspacioLigeroGB   = 1.5    # herramientas (~0,5 GB) + fuentes y compilación (~0,6 GB) + margen
$EspacioMsys2ConGB = 1.5    # con MSYS2 ya instalado: solo fuentes y compilación
$EspacioMsys2SinGB = 4.0    # si hay que instalar también MSYS2 y sus paquetes
$EspacioDestinoMB  = 200

# Para que los acentos de los mensajes de bash se vean bien en la consola.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ── Mensajes ──────────────────────────────────────────────────────────────
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
        if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
            $script:HayVentanas = $true
        }
    } catch { $script:HayVentanas = $false }
}

function Mostrar-Mensaje([string]$texto, [string]$tipo = 'Info') {
    if ($script:HayVentanas) {
        $icono = switch ($tipo) {
            'Error' { [System.Windows.Forms.MessageBoxIcon]::Error }
            'Aviso' { [System.Windows.Forms.MessageBoxIcon]::Warning }
            default { [System.Windows.Forms.MessageBoxIcon]::Information }
        }
        [void][System.Windows.Forms.MessageBox]::Show($texto, $NombreJuego,
            [System.Windows.Forms.MessageBoxButtons]::OK, $icono)
    }
}

function Preguntar-SiNo([string]$texto, [bool]$porDefecto) {
    if ($Silencioso) { return $porDefecto }
    if ($script:HayVentanas) {
        $r = [System.Windows.Forms.MessageBox]::Show($texto, $NombreJuego,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    $sufijo = if ($porDefecto) { '[S/n]' } else { '[s/N]' }
    $resp = Read-Host "$texto $sufijo"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $porDefecto }
    return ($resp.Trim().ToLower() -in @('s', 'si', 'sí', 'y', 'yes'))
}

# ── Utilidades ────────────────────────────────────────────────────────────
function Espacio-Libre([string]$ruta) {
    try {
        $raiz = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($ruta))
        return ([System.IO.DriveInfo]::new($raiz)).AvailableFreeSpace
    } catch { return [long]::MaxValue }   # si no se puede saber, no se bloquea
}

function Tamano-Carpeta([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return 0 }
    $m = Get-ChildItem -LiteralPath $ruta -Recurse -Force -File -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum
    if ($m -and $m.Sum) { return [long]$m.Sum }
    return 0
}

function ConvertTo-RutaMsys([string]$ruta) {
    $r = $ruta -replace '\\', '/'
    if ($r -match '^([A-Za-z]):(.*)$') { $r = '/' + $matches[1].ToLower() + $matches[2] }
    return $r
}

function Misma-Ruta([string]$a, [string]$b) {
    $fa = [System.IO.Path]::GetFullPath($a).TrimEnd('\', '/')
    $fb = [System.IO.Path]::GetFullPath($b).TrimEnd('\', '/')
    return ($fa -ieq $fb)
}

function Esta-Dentro([string]$ruta, [string]$carpeta) {
    $fr = [System.IO.Path]::GetFullPath($ruta).TrimEnd('\', '/')
    $fc = [System.IO.Path]::GetFullPath($carpeta).TrimEnd('\', '/')
    if ($fr -ieq $fc) { return $true }
    return $fr.StartsWith($fc + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
           $fr.StartsWith($fc + '/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Copiar-Carpeta([string]$origen, [string]$destino, [string[]]$excluirCarpetas, [string[]]$excluirArchivos) {
    New-Item -ItemType Directory -Force -Path $destino | Out-Null
    if (Get-Command robocopy -ErrorAction SilentlyContinue) {
        $opciones = @($origen, $destino, '/E', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
        if ($excluirCarpetas) { $opciones += '/XD'; $opciones += $excluirCarpetas }
        if ($excluirArchivos) { $opciones += '/XF'; $opciones += $excluirArchivos }
        & robocopy @opciones | Out-Null
        if ($LASTEXITCODE -ge 8) { Fallo "No se pudo copiar «$origen» a «$destino» (robocopy devolvió $LASTEXITCODE)." }
        $global:LASTEXITCODE = 0
        return
    }
    # Sin robocopy (pruebas en Linux): copia recursiva con las mismas exclusiones.
    Get-ChildItem -LiteralPath $origen -Recurse -Force | ForEach-Object {
        $rel = $_.FullName.Substring($origen.TrimEnd('\', '/').Length).TrimStart('\', '/')
        $partes = $rel -split '[\\/]'
        if ($excluirCarpetas -and ($partes | Where-Object { $excluirCarpetas -contains $_ })) { return }
        if (-not $_.PSIsContainer) {
            foreach ($patron in $excluirArchivos) { if ($_.Name -like $patron) { return } }
        }
        $objetivo = Join-Path $destino $rel
        if ($_.PSIsContainer) { New-Item -ItemType Directory -Force -Path $objetivo | Out-Null }
        else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $objetivo) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $objetivo -Force
        }
    }
}

# ── La carpeta de instalación ─────────────────────────────────────────────
function Destino-Predeterminado {
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    return (Join-Path (Join-Path $base 'Programs') $NombreJuego)
}

# Devuelve @{ Ok; Mensaje; Ruta }. Si la carpeta elegida ya tiene cosas que no son
# de una instalación anterior, se instala en una subcarpeta con el nombre del juego.
function Resolver-Destino([string]$ruta) {
    if ([string]::IsNullOrWhiteSpace($ruta)) {
        return @{ Ok = $false; Mensaje = 'Elige la carpeta donde instalar el juego.' }
    }
    $ruta = $ruta.Trim().Trim('"').Trim()
    try { $ruta = [System.IO.Path]::GetFullPath($ruta) }
    catch { return @{ Ok = $false; Mensaje = 'La ruta no es válida.' } }

    $raiz = [System.IO.Path]::GetPathRoot($ruta)
    if ($ruta.TrimEnd('\', '/') -ieq $raiz.TrimEnd('\', '/')) {
        return @{ Ok = $false; Mensaje = 'Elige una carpeta, no la raíz de una unidad.' }
    }
    if (Test-Path -LiteralPath $ruta -PathType Leaf) {
        return @{ Ok = $false; Mensaje = 'Esa ruta es un archivo, no una carpeta.' }
    }
    if (Esta-Dentro $ruta $RaizProyecto) {
        return @{ Ok = $false; Mensaje = "No instales el juego dentro de la carpeta del instalador ($RaizProyecto). Elige otra." }
    }
    # El juego guarda partidas y ajustes junto al .exe: las carpetas protegidas no sirven.
    $protegidas = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:windir) | Where-Object { $_ }
    foreach ($p in $protegidas) {
        if (Esta-Dentro $ruta $p) {
            return @{ Ok = $false; Mensaje = "No instales el juego en «$p»: Windows no deja escribir ahí sin permisos de administrador y el juego no podría guardar tus partidas." }
        }
    }

    $nota = ''
    $manifiesto = Join-Path $ruta 'instalacion.json'
    if ((Test-Path -LiteralPath $ruta -PathType Container) -and -not (Test-Path -LiteralPath $manifiesto)) {
        $contenido = Get-ChildItem -LiteralPath $ruta -Force -ErrorAction SilentlyContinue
        if ($contenido) {
            $ruta = Join-Path $ruta $NombreJuego
            $nota = "La carpeta elegida no está vacía: se instalará en la subcarpeta «$NombreJuego»."
            $manifiesto = Join-Path $ruta 'instalacion.json'
            if ((Test-Path -LiteralPath $ruta) -and -not (Test-Path -LiteralPath $manifiesto) -and
                (Get-ChildItem -LiteralPath $ruta -Force -ErrorAction SilentlyContinue)) {
                return @{ Ok = $false; Mensaje = "Ya existe «$ruta» y no es una instalación anterior de este juego. Elige otra carpeta." }
            }
        }
    }
    if (Test-Path -LiteralPath $manifiesto) {
        $nota = 'Ya hay una instalación aquí: se actualizará (se conservan tus partidas y ajustes).'
    }

    # ¿Se puede escribir ahí y hay sitio?
    # Se prueba en la carpeta existente más cercana, sin crear carpetas por probar.
    try {
        $base = $ruta
        while ($base -and -not (Test-Path -LiteralPath $base -PathType Container)) { $base = Split-Path -Parent $base }
        if (-not $base) { throw 'sin carpeta base' }
        $prueba = Join-Path $base ('.escritura-' + [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $prueba -Value 'x'
        Remove-Item -LiteralPath $prueba -Force
    } catch {
        return @{ Ok = $false; Mensaje = "No puedo escribir en «$ruta». Elige otra carpeta." }
    }
    $libre = Espacio-Libre $ruta
    if ($libre -lt ($EspacioDestinoMB * 1MB)) {
        return @{ Ok = $false; Mensaje = "No hay espacio suficiente en esa unidad (hacen falta unos $EspacioDestinoMB MB y hay $(Formatear-Tamano $libre))." }
    }
    $msg = "Se instalará en: $ruta"
    if ($nota) { $msg += "`n$nota" }
    return @{ Ok = $true; Mensaje = $msg; Ruta = $ruta }
}

function Obtener-DirObra {
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    $dir = Join-Path (Join-Path $base 'MarioTennisPowerTour') 'obra'
    # gcc, Zig y CMake llevan mal las rutas con acentos, espacios o demasiado largas: en ese caso se usa C:\MTP-obra.
    if ($dir -match '^[\x21-\x7E]+$' -and $dir.Length -le $LongitudMaxObra) { return $dir }
    $unidad = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    return "$unidad\MTP-obra"
}

# ── Ventana de elección ───────────────────────────────────────────────────
function Mostrar-Ventana([string]$romInicial, [string]$destinoInicial) {
    $script:ui = @{}
    $script:resultado = $null

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Instalar $NombreJuego"
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(640, 520)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

    function Nuevo($tipo, [hashtable]$props) {
        $o = New-Object $tipo
        foreach ($k in $props.Keys) { $o.$k = $props[$k] }
        return $o
    }
    function Pt($x, $y) { return New-Object System.Drawing.Point($x, $y) }
    function Tam($w, $h) { return New-Object System.Drawing.Size($w, $h) }

    $titulo = Nuevo System.Windows.Forms.Label @{
        Text = 'Mario Tennis: Power Tour para PC'; Location = (Pt 20 14); Size = (Tam 600 30)
        Font = (New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)) }
    $sub = Nuevo System.Windows.Forms.Label @{
        Text = 'Versión nativa (no es un emulador). Necesitas tu propia ROM europea del juego. No hace falta la BIOS de Nintendo.'
        Location = (Pt 22 50); Size = (Tam 596 40) }

    # 1. ROM
    $g1 = Nuevo System.Windows.Forms.GroupBox @{ Text = '1. Tu ROM'; Location = (Pt 16 96); Size = (Tam 608 108) }
    $script:ui.Rom = Nuevo System.Windows.Forms.TextBox @{ Location = (Pt 14 30); Size = (Tam 482 26); Text = $romInicial }
    $bRom = Nuevo System.Windows.Forms.Button @{ Text = 'Examinar...'; Location = (Pt 504 28); Size = (Tam 92 28) }
    $script:ui.RomEstado = Nuevo System.Windows.Forms.Label @{ Location = (Pt 14 64); Size = (Tam 584 38); Text = '' }
    $g1.Controls.AddRange(@($script:ui.Rom, $bRom, $script:ui.RomEstado))

    # 2. Destino
    $g2 = Nuevo System.Windows.Forms.GroupBox @{ Text = '2. Dónde instalar el juego'; Location = (Pt 16 212); Size = (Tam 608 108) }
    $script:ui.Destino = Nuevo System.Windows.Forms.TextBox @{ Location = (Pt 14 30); Size = (Tam 482 26); Text = $destinoInicial }
    $bDestino = Nuevo System.Windows.Forms.Button @{ Text = 'Examinar...'; Location = (Pt 504 28); Size = (Tam 92 28) }
    $script:ui.DestinoEstado = Nuevo System.Windows.Forms.Label @{ Location = (Pt 14 64); Size = (Tam 584 38); Text = '' }
    $g2.Controls.AddRange(@($script:ui.Destino, $bDestino, $script:ui.DestinoEstado))

    # Accesos directos
    $script:ui.Escritorio = Nuevo System.Windows.Forms.CheckBox @{
        Text = 'Crear un acceso directo en el escritorio'; Location = (Pt 24 332); Size = (Tam 400 24); Checked = $true }
    $script:ui.Inicio = Nuevo System.Windows.Forms.CheckBox @{
        Text = 'Crear accesos directos en el menú Inicio (con el desinstalador)'; Location = (Pt 24 358); Size = (Tam 580 24); Checked = $true }

    $script:ui.Conservar = Nuevo System.Windows.Forms.CheckBox @{
        Text = 'Conservar los archivos de compilación (~1 GB) para actualizar mucho más rápido'; Location = (Pt 24 384); Size = (Tam 600 24); Checked = $false }

    $aviso = Nuevo System.Windows.Forms.Label @{
        Location = (Pt 22 416); Size = (Tam 596 62)
        Text = ("Se descargan unas herramientas de compilación ligeras (unos 150 MB, con internet) y se compila el juego a partir de tu ROM: " +
                "tarda de 20 a 60 minutos. Durante la instalación hacen falta unos 1,5 GB libres; al terminar se borra lo temporal y el juego " +
                "ocupa unos 60 MB. La ROM no sale de tu equipo.") }

    $bInstalar = Nuevo System.Windows.Forms.Button @{ Text = 'Instalar'; Location = (Pt 424 480); Size = (Tam 96 30) }
    $bCancelar = Nuevo System.Windows.Forms.Button @{ Text = 'Cancelar'; Location = (Pt 528 480); Size = (Tam 96 30) }
    $form.AcceptButton = $bInstalar
    $form.CancelButton = $bCancelar

    $form.Controls.AddRange(@($titulo, $sub, $g1, $g2, $script:ui.Escritorio, $script:ui.Inicio, $script:ui.Conservar, $aviso, $bInstalar, $bCancelar))

    $actualizarRom = {
        $r = Probar-Rom $script:ui.Rom.Text
        $script:ui.RomEstado.Text = $r.Mensaje
        $script:ui.RomEstado.ForeColor = if ($r.Ok) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Firebrick }
        return $r
    }
    $actualizarDestino = {
        $d = Resolver-Destino $script:ui.Destino.Text
        $script:ui.DestinoEstado.Text = $d.Mensaje
        $script:ui.DestinoEstado.ForeColor = if ($d.Ok) { [System.Drawing.Color]::DimGray } else { [System.Drawing.Color]::Firebrick }
        return $d
    }

    $bRom.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Elige tu ROM europea de Mario Tennis: Power Tour'
        $dlg.Filter = 'ROM de GBA (*.gba)|*.gba|Todos los archivos (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:ui.Rom.Text = $dlg.FileName
            [void](& $actualizarRom)
        }
    })
    $bDestino.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = 'Elige la carpeta donde instalar el juego'
        $dlg.ShowNewFolderButton = $true
        if ($script:ui.Destino.Text -and (Test-Path -LiteralPath $script:ui.Destino.Text -PathType Container)) {
            $dlg.SelectedPath = $script:ui.Destino.Text
        }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:ui.Destino.Text = $dlg.SelectedPath
            [void](& $actualizarDestino)
        }
    })
    $script:ui.Rom.Add_Leave({ [void](& $actualizarRom) })
    $script:ui.Destino.Add_Leave({ [void](& $actualizarDestino) })

    $bInstalar.Add_Click({
        $r = & $actualizarRom
        if (-not $r.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($r.Mensaje, $NombreJuego,
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $d = & $actualizarDestino
        if (-not $d.Ok) {
            [void][System.Windows.Forms.MessageBox]::Show($d.Mensaje, $NombreJuego,
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $script:resultado = @{
            Rom = $r.Ruta; Destino = $d.Ruta
            Escritorio = [bool]$script:ui.Escritorio.Checked; Inicio = [bool]$script:ui.Inicio.Checked
            ConservarObra = [bool]$script:ui.Conservar.Checked }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $form.Add_Shown({
        $form.Activate()
        if ($script:ui.Rom.Text) { [void](& $actualizarRom) }
        [void](& $actualizarDestino)
    })

    [void]$form.ShowDialog()
    $form.Dispose()
    return $script:resultado
}

# ── Elección sin ventana (consola o -Silencioso) ──────────────────────────
function Elegir-EnConsola([string]$romInicial, [string]$destinoInicial) {
    $rom = $romInicial
    while ($true) {
        if (-not $rom) {
            if ($Silencioso) { Fallo 'No encuentro tu ROM. Indícala con -Rom <ruta>.' }
            $rom = Read-Host 'Ruta de tu ROM europea de Mario Tennis: Power Tour (.gba)'
        }
        $r = Probar-Rom $rom
        if ($r.Ok) { $rom = $r.Ruta; break }
        if ($Silencioso) { Fallo $r.Mensaje }
        Escribir-Aviso $r.Mensaje
        $rom = ''
    }
    $dest = $destinoInicial
    while ($true) {
        if (-not $Silencioso) {
            $resp = Read-Host "Carpeta de instalación [$dest]"
            if (-not [string]::IsNullOrWhiteSpace($resp)) { $dest = $resp }
        }
        $d = Resolver-Destino $dest
        if ($d.Ok) { Escribir-Info $d.Mensaje; break }
        if ($Silencioso) { Fallo $d.Mensaje }
        Escribir-Aviso $d.Mensaje
    }
    $acc = -not $SinAccesos
    $conservar = [bool]$ConservarObra
    if (-not $Silencioso -and -not $conservar) {
        $conservar = Preguntar-SiNo 'Conservar los archivos de compilación (~1 GB) para actualizar mucho más rápido?' $false
    }
    return @{ Rom = $rom; Destino = $d.Ruta; Escritorio = $acc; Inicio = $acc; ConservarObra = $conservar }
}

# ── Requisitos y herramientas ─────────────────────────────────────────────
function Comprobar-Requisitos([string]$dirObra, [double]$espacioGB) {
    if (-not $EsWindows) { Fallo 'Este instalador es para Windows. En Linux usa tools/construir.sh.' }
    if (-not [Environment]::Is64BitOperatingSystem) { Fallo 'Hace falta un Windows de 64 bits.' }
    if (-not $PruebaLinux -and [Environment]::OSVersion.Version.Major -lt 10) { Fallo 'Hace falta Windows 10 u 11.' }
    Comprobar-Espacio $dirObra $espacioGB
    # Comprobación orientativa: si no se llega a ninguno de los dos sitios se avisa, pero se
    # sigue (un proxy puede bloquear solo la página principal); si la descarga falla, lo dirá.
    $hayRed = $false
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch { }
    foreach ($sitio in @('https://pypi.org', 'https://github.com')) {
        try {
            Invoke-WebRequest -Uri $sitio -Method Head -UseBasicParsing -TimeoutSec 20 | Out-Null
            $hayRed = $true
            break
        } catch { }
    }
    if (-not $hayRed) {
        Escribir-Aviso 'No consigo comprobar la conexión a internet (pypi.org y github.com no responden). Sigo; si hace falta descargar algo y no hay red, te lo diré.'
    }
}

function Comprobar-Espacio([string]$dirObra, [double]$espacioGB) {
    $libre = Espacio-Libre $dirObra
    if ($libre -lt ($espacioGB * 1GB)) {
        Fallo ("No hay espacio suficiente para compilar: hacen falta unos {0:N1} GB libres en la unidad de «{1}» y hay {2}." -f $espacioGB, $dirObra, (Formatear-Tamano $libre))
    }
}

function Invocar-Msys([string]$bash, [string]$orden, [switch]$IgnorarError) {
    $env:MSYSTEM = 'MINGW64'
    $env:CHERE_INVOKING = '1'
    & $bash -lc $orden | Out-Host
    $codigo = $LASTEXITCODE
    if ($codigo -ne 0 -and -not $IgnorarError) {
        Fallo "Ha fallado una orden de MSYS2 (código $codigo): $orden"
    }
    return $codigo
}

function Asegurar-Msys2 {
    $bash = Join-Path $Msys2 'usr\bin\bash.exe'
    if (Test-Path -LiteralPath $bash) {
        Escribir-Ok "MSYS2 ya está instalado en $Msys2"
        return $bash
    }
    Escribir-Info 'Instalando MSYS2 (el entorno de compilación)...'
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id MSYS2.MSYS2 -e --silent --accept-source-agreements --accept-package-agreements | Out-Host
        $global:LASTEXITCODE = 0
    } else {
        Escribir-Aviso 'No encuentro winget; uso el paquete oficial de MSYS2.'
    }
    if (-not (Test-Path -LiteralPath $bash) -and (Split-Path -Leaf $Msys2) -ieq 'msys64') {
        # Reserva: el paquete autoextraíble oficial (crea <carpeta>\msys64).
        $sfx = Join-Path ([System.IO.Path]::GetTempPath()) 'msys2-base-x86_64-latest.sfx.exe'
        $url = 'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
        Escribir-Info 'Descargando MSYS2...'
        Invoke-WebRequest -Uri $url -OutFile $sfx -UseBasicParsing
        $padre = Split-Path -Parent $Msys2
        Start-Process -FilePath $sfx -ArgumentList '-y', "-o$padre" -Wait
    }
    if (-not (Test-Path -LiteralPath $bash)) {
        Fallo "No he podido instalar MSYS2. Instálalo a mano desde https://www.msys2.org/ (en $Msys2) y vuelve a ejecutar este instalador."
    }
    [void](Invocar-Msys $bash 'exit' -IgnorarError)   # primer arranque: crea el perfil
    Escribir-Ok 'MSYS2 instalado.'
    return $bash
}

# Un bloqueo de pacman que se quedó a medias (db.lck) hace fallar TODAS sus órdenes con
# «no se pudo bloquear la base de datos». Pasa si hay otra ventana de MSYS2 actualizando
# o si un intento anterior se cortó. Se espera a que termine el pacman que haya en marcha
# y, si no queda ninguno, se quita el bloqueo antiguo.
function Preparar-Pacman {
    $lck = Join-Path $Msys2 'var\lib\pacman\db.lck'
    if (@(Get-Process -Name 'pacman' -ErrorAction SilentlyContinue).Count -gt 0) {
        Escribir-Aviso 'Hay un pacman en marcha (otra ventana de MSYS2 o un intento anterior). Espero hasta 2 minutos a que termine...'
        $limite = (Get-Date).AddMinutes(2)
        while (@(Get-Process -Name 'pacman' -ErrorAction SilentlyContinue).Count -gt 0 -and (Get-Date) -lt $limite) {
            Start-Sleep -Seconds 3
        }
        $enMarcha = @(Get-Process -Name 'pacman' -ErrorAction SilentlyContinue)
        if ($enMarcha.Count -gt 0) {
            $texto = "Sigue habiendo un pacman en marcha (probablemente de un intento anterior que se cortó).`n" +
                     "Si lo cierro y continúo, no pasa nada: el instalador repasa los paquetes.`n`n" +
                     "¿Lo cierro?"
            if (Preguntar-SiNo $texto $true) {
                $enMarcha | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
            } else {
                Fallo 'Hay otro pacman en marcha. Cierra las ventanas de MSYS2 y vuelve a ejecutar el instalador.'
            }
        }
    }
    if (Test-Path -LiteralPath $lck) {
        Remove-Item -LiteralPath $lck -Force -ErrorAction SilentlyContinue
        Escribir-Aviso 'Quité un bloqueo antiguo de pacman (db.lck) que impedía instalar paquetes.'
    }
}

function Instalar-Herramientas([string]$bash) {
    Preparar-Pacman
    Escribir-Info 'Actualizando MSYS2 (se ejecuta dos veces a propósito: la primera puede reiniciarse sola)...'
    [void](Invocar-Msys $bash 'pacman -Syu --noconfirm' -IgnorarError)
    Preparar-Pacman
    [void](Invocar-Msys $bash 'pacman -Syu --noconfirm' -IgnorarError)
    Escribir-Info 'Instalando gcc, cmake, ninja, SDL2, git y python...'
    $paquetes = 'git mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-SDL2 mingw-w64-x86_64-python'
    for ($intento = 1; $intento -le 2; $intento++) {
        Preparar-Pacman
        $codigo = Invocar-Msys $bash "pacman -S --needed --noconfirm $paquetes" -IgnorarError
        if ($codigo -eq 0) { break }
        if ($intento -eq 2) {
            Fallo "No se pudieron instalar los paquetes de MSYS2 (pacman devolvió $codigo). Mira los mensajes de arriba."
        }
        Escribir-Aviso 'Falló la instalación de paquetes; lo intento una vez más...'
    }
    Escribir-Ok 'Herramientas listas.'
}

function Calcular-Nucleos {
    $nucleos = [Environment]::ProcessorCount
    try {
        $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        # Cada proceso del compilador puede usar más de 1 GiB: se limita para no agotar la RAM.
        $porRam = [Math]::Floor($ram / 1.5GB)
        $nucleos = [Math]::Min($nucleos, $porRam)
    } catch { }
    return [Math]::Max(1, [int]$nucleos)
}

# ── Instalación ───────────────────────────────────────────────────────────
function Crear-Acceso([string]$ruta, [string]$objetivo, [string]$argumentos, [string]$trabajo, [string]$icono, [string]$descripcion) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ruta) | Out-Null
    $ws = New-Object -ComObject WScript.Shell
    $a = $ws.CreateShortcut($ruta)
    $a.TargetPath = $objetivo
    $a.Arguments = $argumentos
    $a.WorkingDirectory = $trabajo
    $a.IconLocation = "$icono,0"
    $a.Description = $descripcion
    $a.Save()
}

function Borrar-Carpeta([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return }
    try { [System.IO.Directory]::Delete($ruta, $true) }
    catch { Remove-Item -LiteralPath $ruta -Recurse -Force -ErrorAction SilentlyContinue }
}

# Copia los archivos del proyecto a la carpeta de trabajo (sin lo generado) y coloca tu ROM.
# Si la carpeta ya existe de una instalación anterior que se conservó, solo se tocan los archivos
# que han cambiado, y se les pone la fecha de ahora: Ninja decide qué recompilar comparando fechas
# y un archivo nuevo con fecha antigua (la del zip) se ignoraría.
function Preparar-Obra([string]$dirObra, [string]$rom) {
    $excluidas = @('generated', 'generated_bios', 'juego', 'build', 'externo', '.git', 'herramientas', 'descargas', 'cache-zig')
    if (-not (Misma-Ruta $RaizProyecto $dirObra)) {
        $origen = [System.IO.Path]::GetFullPath($RaizProyecto).TrimEnd('\', '/')
        New-Item -ItemType Directory -Force -Path $dirObra | Out-Null
        foreach ($f in (Get-ChildItem -LiteralPath $origen -Recurse -Force -File)) {
            $rel = $f.FullName.Substring($origen.Length).TrimStart('\', '/')
            $partes = $rel -split '[\\/]'
            if ($partes.Count -gt 1 -and ($excluidas -contains $partes[0])) { continue }
            if ($f.Extension -in @('.gba', '.sav')) { continue }
            $objetivo = Join-Path $dirObra $rel
            if (Test-Path -LiteralPath $objetivo -PathType Leaf) {
                $o = Get-Item -LiteralPath $objetivo -Force
                if ($o.Length -eq $f.Length -and (Get-FileHash -LiteralPath $objetivo -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash) { continue }
            } else {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $objetivo) | Out-Null
            }
            Copy-Item -LiteralPath $f.FullName -Destination $objetivo -Force
            (Get-Item -LiteralPath $objetivo -Force).LastWriteTime = Get-Date
        }
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $dirObra 'roms') | Out-Null
    $destinoRom = Join-Path $dirObra (Join-Path 'roms' $RomNombre)
    if (-not (Test-Path -LiteralPath $destinoRom) -or (Get-Item -LiteralPath $destinoRom).Length -ne (Get-Item -LiteralPath $rom).Length) {
        Copy-Item -LiteralPath $rom -Destination $destinoRom -Force
    }
}

# Método ligero: Zig + CMake + Ninja + SDL2 (unos 150 MB), sin MSYS2 ni git.
function Compilar-Ligero([string]$dirObra, [string]$rom) {
    $script = Join-Path $dirObra 'tools\construir.ps1'
    if (-not (Test-Path -LiteralPath $script)) { Fallo "Falta $script" }
    & $script -Rom $rom -Raiz $dirObra -Nucleos (Calcular-Nucleos) | Out-Host
    $carpetaJuego = Join-Path $dirObra 'juego'
    if (-not (Test-Path -LiteralPath (Join-Path $carpetaJuego $ExeJuego))) {
        Fallo "La compilación ligera terminó sin generar $ExeJuego."
    }
    return $carpetaJuego
}

# Método clásico (respaldo): MSYS2 con gcc.
function Compilar-Msys2([string]$dirObra, [string]$rom) {
    $espacio = $EspacioMsys2SinGB
    if (Test-Path -LiteralPath (Join-Path $Msys2 'usr\bin\bash.exe')) { $espacio = $EspacioMsys2ConGB }
    Comprobar-Espacio $dirObra $espacio
    Escribir-Info 'Preparando MSYS2 y las herramientas de compilación...'
    $bash = Asegurar-Msys2
    Instalar-Herramientas $bash
    $env:MTP_NUCLEOS = [string](Calcular-Nucleos)
    Escribir-Info "Procesos de compilación en paralelo: $($env:MTP_NUCLEOS)"
    $obraMsys = ConvertTo-RutaMsys $dirObra
    # sed: por si los scripts llegaron con finales de línea de Windows.
    $orden = "set -o pipefail; cd '$obraMsys' && sed -i 's/\r$//' tools/*.sh && bash ./tools/construir.sh 2>&1 | tee '$obraMsys/instalacion.log'"
    [void](Invocar-Msys $bash $orden)
    $carpetaJuego = Join-Path $dirObra 'juego'
    if (-not (Test-Path -LiteralPath (Join-Path $carpetaJuego $ExeJuego))) {
        Fallo "La compilación terminó sin generar $ExeJuego. Mira el registro: $(Join-Path $dirObra 'instalacion.log')"
    }
    return $carpetaJuego
}

function Instalar-Juego($eleccion) {
    $rom = $eleccion.Rom
    $destino = $eleccion.Destino
    $dirObra = Obtener-DirObra
    $conservar = ([bool]$eleccion.ConservarObra) -or [bool]$ConservarObra
    $log = ''
    $carpetaJuego = ''
    $metodoUsado = ''
    $anterior = Leer-Manifiesto $destino

    if ($PruebaSeca) {
        Escribir-Paso 'Prueba en seco: se salta la descarga de herramientas y la compilación'
        if (-not $JuegoPrueba -or -not (Test-Path -LiteralPath (Join-Path $JuegoPrueba $ExeJuego))) {
            Fallo "Con -PruebaSeca hay que indicar -JuegoPrueba con una carpeta que contenga $ExeJuego."
        }
        $carpetaJuego = (Resolve-Path -LiteralPath $JuegoPrueba).ProviderPath
        $metodoUsado = 'prueba'
    } else {
        Escribir-Paso '1/4 Comprobando el equipo'
        $espacioInicial = $EspacioLigeroGB
        if ($Metodo -eq 'msys2') {
            $espacioInicial = $EspacioMsys2SinGB
            if (Test-Path -LiteralPath (Join-Path $Msys2 'usr\bin\bash.exe')) { $espacioInicial = $EspacioMsys2ConGB }
        }
        Comprobar-Requisitos $dirObra $espacioInicial
        Escribir-Ok 'Windows de 64 bits, espacio libre y conexión a internet.'

        Escribir-Paso '2/4 Preparando los archivos de compilación'
        Preparar-Obra $dirObra $rom
        Escribir-Ok "Carpeta de trabajo (temporal): $dirObra"

        Escribir-Paso '3/4 Recompilando tu ROM y compilando el juego (20-60 minutos; no cierres esta ventana)'
        if ($Metodo -ne 'msys2') {
            try {
                Escribir-Info 'Método ligero: Zig + CMake + Ninja (sin MSYS2).'
                $carpetaJuego = Compilar-Ligero $dirObra $rom
                $metodoUsado = 'ligero'
            } catch {
                $motivo = $_.Exception.Message
                Escribir-Aviso "La compilación ligera ha fallado: $motivo"
                # Al actualizar (sin ventanas) no se instala MSYS2 a escondidas: se avisa y se para.
                if ($Metodo -eq 'ligero' -or $Actualizando) { throw }
                $texto = "La compilación ligera no ha funcionado:`n`n$motivo`n`n" +
                         "Puedo probar con el método clásico (MSYS2), que descarga bastante más y tarda más. ¿Lo pruebo?"
                if (-not (Preguntar-SiNo $texto $true)) { throw }
                # El método clásico parte de cero: se borra lo que dejó el ligero.
                Borrar-Carpeta $dirObra
                Preparar-Obra $dirObra $rom
            }
        }
        if (-not $metodoUsado) {
            Escribir-Info 'Método clásico: MSYS2 con gcc.'
            $carpetaJuego = Compilar-Msys2 $dirObra $rom
            $metodoUsado = 'msys2'
            $log = Join-Path $dirObra 'instalacion.log'
        }
        Escribir-Ok 'Juego compilado.'
    }

    Escribir-Paso "4/4 Instalando en $destino"
    # Se conservan las partidas y los ajustes de una instalación anterior.
    Copiar-Carpeta $carpetaJuego $destino @('recomp_cache') @('rom.cfg', 'bios.cfg', 'config.ini', 'keybinds.ini', '*.sav', 'recomp_master_misses_*', 'recomp_coverage_*')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'DESINSTALAR.ps1') -Destination (Join-Path $destino 'Desinstalar.ps1') -Force
    Set-Content -LiteralPath (Join-Path $destino 'Desinstalar.bat') -Encoding ASCII -Value @(
        '@echo off',
        'rem Desinstala Mario Tennis: Power Tour.',
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Desinstalar.ps1" %*')
    if (-not $log -or -not (Test-Path -LiteralPath $log)) {
        $log = Join-Path ([System.IO.Path]::GetTempPath()) 'mario-tennis-instalador.log'
    }
    if (Test-Path -LiteralPath $log) { try { Copy-Item -LiteralPath $log -Destination (Join-Path $destino 'instalacion.log') -Force } catch { } }
    $exe = Join-Path $destino $ExeJuego
    Escribir-Ok 'Archivos copiados (con tu ROM y la BIOS libre).'
    $icono = Instalar-Icono $destino
    $iconoAccesos = $exe
    if ($icono) { $iconoAccesos = $icono; Escribir-Ok 'Icono personalizado (icono.ico) instalado.' }

    $version = Leer-VersionProyecto $RaizProyecto
    $huella = Calcular-Huella $RaizProyecto

    # Accesos directos y entrada en «Aplicaciones»
    $accesos = @()
    $registro = $false
    if ($anterior) {
        if ($anterior.accesos) { $accesos = @($anterior.accesos) }
        if ($anterior.registro) { $registro = $true }
    }
    $powershell = ''
    if ($EsWindows -and $env:SystemRoot) { $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
    $argDes = "-NoProfile -ExecutionPolicy Bypass -STA -File `"$(Join-Path $destino 'Desinstalar.ps1')`""
    $crearAccesos = $EsWindows -and -not $SinAccesos -and -not $PruebaSeca -and -not $Actualizando
    if ($crearAccesos) {
        try {
            if ($eleccion.Escritorio) {
                $ruta = Join-Path ([Environment]::GetFolderPath('Desktop')) "$NombreJuego.lnk"
                Crear-Acceso $ruta $exe '' $destino $iconoAccesos 'Mario Tennis: Power Tour (versión nativa para PC)'
                if ($accesos -notcontains $ruta) { $accesos += $ruta }
            }
            if ($eleccion.Inicio) {
                $carpetaInicio = Join-Path ([Environment]::GetFolderPath('Programs')) $NombreJuego
                $ruta1 = Join-Path $carpetaInicio "$NombreJuego.lnk"
                $ruta2 = Join-Path $carpetaInicio "Desinstalar $NombreJuego.lnk"
                Crear-Acceso $ruta1 $exe '' $destino $iconoAccesos 'Mario Tennis: Power Tour (versión nativa para PC)'
                Crear-Acceso $ruta2 $powershell $argDes $destino $iconoAccesos "Desinstalar $NombreJuego"
                if ($accesos -notcontains $ruta1) { $accesos += $ruta1 }
                if ($accesos -notcontains $ruta2) { $accesos += $ruta2 }
            }
            $registro = $true
            Escribir-Ok 'Accesos directos creados.'
        } catch {
            Escribir-Aviso "No pude crear algún acceso directo ($($_.Exception.Message)). El juego está instalado igualmente."
        }
    }
    # Al actualizar los accesos no se recrean, pero sí se les pone el icono si hay uno.
    if ($Actualizando -and $icono -and $anterior) {
        $n = Aplicar-IconoAccesos $anterior $icono
        if ($n -gt 0) { Escribir-Ok "Icono aplicado a $n acceso(s) directo(s)." }
    }
    # La entrada de «Aplicaciones» se crea al instalar y se refresca al actualizar.
    if ($EsWindows -and -not $PruebaSeca -and ($crearAccesos -or ($Actualizando -and $registro))) {
        try {
            New-Item -Path $ClaveRegistro -Force | Out-Null
            Set-ItemProperty -Path $ClaveRegistro -Name 'DisplayName' -Value $NombreJuego
            Set-ItemProperty -Path $ClaveRegistro -Name 'DisplayVersion' -Value $version
            Set-ItemProperty -Path $ClaveRegistro -Name 'Publisher' -Value 'Proyecto no oficial (gbarecomp)'
            Set-ItemProperty -Path $ClaveRegistro -Name 'InstallLocation' -Value $destino
            Set-ItemProperty -Path $ClaveRegistro -Name 'DisplayIcon' -Value $iconoAccesos
            Set-ItemProperty -Path $ClaveRegistro -Name 'UninstallString' -Value "`"$powershell`" $argDes"
            [void](New-ItemProperty -Path $ClaveRegistro -Name 'NoModify' -Value 1 -PropertyType DWord -Force)
            [void](New-ItemProperty -Path $ClaveRegistro -Name 'NoRepair' -Value 1 -PropertyType DWord -Force)
            [void](New-ItemProperty -Path $ClaveRegistro -Name 'EstimatedSize' -Value ([int]((Tamano-Carpeta $destino) / 1KB)) -PropertyType DWord -Force)
            $registro = $true
            Escribir-Ok 'Juego registrado en «Aplicaciones» de Windows.'
        } catch {
            Escribir-Aviso "No pude registrar el juego en «Aplicaciones» ($($_.Exception.Message)). Está instalado igualmente."
        }
    }

    # Manifiesto (lo leen el desinstalador y ACTUALIZAR)
    $manifiesto = @{
        producto      = 'MarioTennisPowerTourRecomp'
        version       = $version
        huella        = $huella
        metodo        = $metodoUsado
        fecha         = (Get-Date).ToString('s')
        destino       = $destino
        accesos       = @($accesos)
        registro      = $(if ($registro) { $ClaveRegistro } else { '' })
        obra          = $(if ($PruebaSeca) { '' } else { $dirObra })
        conservarObra = [bool]$conservar
    }
    Set-Content -LiteralPath (Join-Path $destino 'instalacion.json') -Encoding UTF8 -Value ($manifiesto | ConvertTo-Json -Depth 4)

    # Carpeta temporal de compilación: se borra salvo que se haya pedido conservarla.
    if (-not $PruebaSeca -and (Test-Path -LiteralPath $dirObra)) {
        if ($conservar) {
            Escribir-Info "Se conservan los archivos de compilación ($(Formatear-Tamano (Tamano-Carpeta $dirObra))) en $dirObra para actualizar más rápido."
        } else {
            Borrar-Carpeta $dirObra
            if (Test-Path -LiteralPath $dirObra) { Escribir-Aviso "No pude borrar $dirObra por completo; puedes borrarla a mano." }
            else { Escribir-Ok 'Archivos temporales borrados.' }
        }
    }
    return @{ Destino = $destino; Exe = $exe }
}

# ── Programa principal ────────────────────────────────────────────────────
$transcripcion = $false
try {
    try {
        Start-Transcript -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'mario-tennis-instalador.log') -Force | Out-Null
        $transcripcion = $true
    } catch { }

    Write-Host ''
    Write-Host "  $NombreJuego - instalador" -ForegroundColor White
    Write-Host '  Versión nativa para PC (no es un emulador). Proyecto no oficial.' -ForegroundColor DarkGray

    $romInicial = ''
    if ($Rom) {
        $r = Probar-Rom $Rom
        if (-not $r.Ok) { Fallo $r.Mensaje }
        $romInicial = $r.Ruta
    } else {
        $romInicial = Buscar-Rom
    }
    $destinoInicial = if ($Destino) { $Destino } else { Destino-Predeterminado }

    $eleccion = $null
    if ($script:HayVentanas) {
        $ventanaFallo = $false
        try {
            $eleccion = Mostrar-Ventana $romInicial $destinoInicial
        } catch {
            # Si la ventana no se puede abrir, se sigue en la consola en vez de abandonar.
            $ventanaFallo = $true
            $script:HayVentanas = $false
            Escribir-Aviso "No he podido abrir la ventana ($($_.Exception.Message)). Sigo en esta consola."
        }
        if (-not $ventanaFallo) {
            if (-not $eleccion) {
                Write-Host '  Instalación cancelada.'
                return
            }
            if ($SinAccesos) { $eleccion.Escritorio = $false; $eleccion.Inicio = $false }
        }
    }
    if (-not $eleccion) {
        $eleccion = Elegir-EnConsola $romInicial $destinoInicial
    }

    $inicio = Get-Date
    $res = Instalar-Juego $eleccion
    $minutos = [int]((Get-Date) - $inicio).TotalMinutes

    Escribir-Paso 'Listo'
    if ($Actualizando) { Escribir-Info "El juego se ha actualizado en: $($res.Destino) (tus partidas y ajustes siguen ahí)" }
    else { Escribir-Info "El juego está instalado en: $($res.Destino)" }
    Escribir-Info 'Se abre con el acceso directo, o con JUGAR.bat dentro de esa carpeta.'
    Escribir-Info "Para desinstalarlo: «Aplicaciones» de Windows, el menú Inicio o Desinstalar.bat. (Duración: $minutos min)"
    if (-not $Silencioso -and -not $PruebaSeca) {
        $textoFin = '¡Instalación terminada! ¿Quieres abrir el juego ahora?'
        if ($Actualizando) { $textoFin = '¡Actualización terminada! ¿Quieres abrir el juego ahora?' }
        if (Preguntar-SiNo $textoFin $true) {
            Start-Process -FilePath $res.Exe -WorkingDirectory $res.Destino
        }
    }
    if ($transcripcion) { try { Stop-Transcript | Out-Null } catch { } }
    exit 0
}
catch {
    $mensaje = $_.Exception.Message
    Write-Host ''
    Write-Host "ERROR: $mensaje" -ForegroundColor Red
    Write-Host '  El registro de esta sesión está en: ' -NoNewline
    Write-Host (Join-Path ([System.IO.Path]::GetTempPath()) 'mario-tennis-instalador.log')
    Mostrar-Mensaje "La instalación no se pudo completar:`n`n$mensaje" 'Error'
    if ($transcripcion) { try { Stop-Transcript | Out-Null } catch { } }
    if (-not $Silencioso) { [void](Read-Host 'Pulsa Intro para cerrar') }
    exit 1
}
