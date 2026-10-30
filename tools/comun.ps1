# comun.ps1 — constantes y funciones que comparten INSTALAR.ps1 y ACTUALIZAR.ps1.
# No se ejecuta solo: lo cargan los otros scripts con «. "$PSScriptRoot\comun.ps1"».

$NombreJuego   = 'Mario Tennis Power Tour'
$ExeJuego      = 'MarioTennisPowerTourRecomp.exe'
$RomSha1       = 'd61990974040d405b5bf8436ac8e1e0beb0f7964'
$RomTamano     = 16777216
$RomNombre     = 'mario_tennis_power_tour_eur.gba'
$ClaveRegistro = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\MarioTennisPowerTourRecomp'
$RaizProyecto  = Split-Path -Parent $PSScriptRoot
$EsWindows     = ($PSVersionTable.PSEdition -ne 'Core') -or ($IsWindows -eq $true)
# Solo para pruebas en Linux (MTP_PRUEBA_LINUX=1): se comporta como Windows en lo que se puede simular.
$PruebaLinux   = [bool]$env:MTP_PRUEBA_LINUX
if ($PruebaLinux) { $EsWindows = $true }
$LongitudMaxObra = 70       # Zig y CMake llevan mal las rutas largas de Windows
if ($PruebaLinux) { $LongitudMaxObra = 500 }

function Formatear-Tamano([double]$bytes) {
    # Sin separador de millares (en español «1,005» se lee como un decimal).
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($bytes -ge 1GB) { return ((($bytes / 1GB).ToString('0.0', $inv)).Replace('.', ',') + ' GB') }
    return (([int][Math]::Round($bytes / 1MB)).ToString($inv) + ' MB')
}

# ── La ROM ────────────────────────────────────────────────────────────────
function Probar-Rom([string]$ruta) {
    if ([string]::IsNullOrWhiteSpace($ruta)) {
        return @{ Ok = $false; Mensaje = 'Elige el archivo .gba de tu ROM.' }
    }
    $ruta = $ruta.Trim().Trim('"').Trim()
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) {
        return @{ Ok = $false; Mensaje = 'No existe ese archivo.' }
    }
    $tam = (Get-Item -LiteralPath $ruta).Length
    if ($tam -ne $RomTamano) {
        return @{ Ok = $false; Mensaje = "La ROM debe medir 16 MiB (16.777.216 bytes); este archivo mide $tam bytes." }
    }
    $sha = (Get-FileHash -LiteralPath $ruta -Algorithm SHA1).Hash.ToLower()
    if ($sha -ne $RomSha1) {
        return @{ Ok = $false; Mensaje = "Esta ROM no es la versión europea (BTMP, rev. 0).`nSHA-1 de tu archivo: $sha`nSHA-1 esperado:      $RomSha1" }
    }
    return @{ Ok = $true; Mensaje = 'ROM correcta (Mario Tennis: Power Tour, Europa).'; Ruta = (Resolve-Path -LiteralPath $ruta).ProviderPath }
}

# Busca una ROM válida en las carpetas habituales (y en las que se pasen como extra).
function Buscar-Rom([string[]]$extra) {
    $perfil = [Environment]::GetFolderPath('UserProfile')
    $carpetas = @($extra) + @(
        (Join-Path $RaizProyecto 'roms'),
        (Join-Path $perfil 'Downloads'),
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments')
    )
    foreach ($c in $carpetas) {
        if (-not $c -or -not (Test-Path -LiteralPath $c -PathType Container)) { continue }
        $candidatas = Get-ChildItem -LiteralPath $c -Filter '*.gba' -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.Length -eq $RomTamano }
        foreach ($f in $candidatas) {
            $r = Probar-Rom $f.FullName
            if ($r.Ok) { return $r.Ruta }
        }
    }
    return ''
}

# ── Instalaciones anteriores ──────────────────────────────────────────────
# Devuelve el contenido de instalacion.json de una carpeta (o $null).
function Leer-Manifiesto([string]$carpeta) {
    $ruta = Join-Path $carpeta 'instalacion.json'
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Es-Instalacion([string]$carpeta) {
    if (-not $carpeta -or -not (Test-Path -LiteralPath $carpeta -PathType Container)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $carpeta $ExeJuego) -PathType Leaf)
}

# Busca sola dónde está instalado el juego. Devuelve @{ Carpeta; Origen } o $null.
# Orden: «Aplicaciones» de Windows (registro) → carpeta por defecto → accesos directos
# (escritorio y menú Inicio) → carpetas típicas de cada disco.
function Buscar-Instalacion {
    $candidatas = New-Object System.Collections.ArrayList
    function Anadir([string]$carpeta, [string]$origen) {
        if ($carpeta) { [void]$candidatas.Add(@{ Carpeta = $carpeta; Origen = $origen }) }
    }
    if ($EsWindows) {
        try {
            $reg = Get-ItemProperty -Path $ClaveRegistro -ErrorAction Stop
            Anadir $reg.InstallLocation 'la lista de «Aplicaciones» de Windows'
        } catch { }
    }
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if ($base) { Anadir (Join-Path (Join-Path $base 'Programs') $NombreJuego) 'la carpeta por defecto' }

    if ($EsWindows) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $accesos = @()
            $escritorio = [Environment]::GetFolderPath('Desktop')
            if ($escritorio) { $accesos += (Join-Path $escritorio "$NombreJuego.lnk") }
            $inicio = [Environment]::GetFolderPath('Programs')
            if ($inicio) { $accesos += (Join-Path (Join-Path $inicio $NombreJuego) "$NombreJuego.lnk") }
            foreach ($a in $accesos) {
                if (Test-Path -LiteralPath $a -PathType Leaf) {
                    $destino = $ws.CreateShortcut($a).TargetPath
                    if ($destino) { Anadir (Split-Path -Parent $destino) 'un acceso directo' }
                }
            }
        } catch { }
        try {
            foreach ($unidad in [System.IO.DriveInfo]::GetDrives()) {
                if ($unidad.DriveType -ne 'Fixed' -or -not $unidad.IsReady) { continue }
                $r = $unidad.RootDirectory.FullName
                Anadir (Join-Path $r $NombreJuego) 'una búsqueda en tus discos'
                foreach ($sub in @('Juegos', 'Games', 'Program Files')) {
                    Anadir (Join-Path (Join-Path $r $sub) $NombreJuego) 'una búsqueda en tus discos'
                }
            }
        } catch { }
    }
    foreach ($c in $candidatas) {
        if (Es-Instalacion $c.Carpeta) {
            try { $c.Carpeta = (Resolve-Path -LiteralPath $c.Carpeta).ProviderPath } catch { }
            return $c
        }
    }
    return $null
}

# ── Versión del instalador (para saber si hay algo que actualizar) ─────────
function Leer-VersionProyecto([string]$raiz) {
    $v = Join-Path $raiz 'VERSION'
    if (Test-Path -LiteralPath $v -PathType Leaf) { return (Get-Content -LiteralPath $v -Raw).Trim() }
    return '0.0'
}

# Huella (SHA-256) de todo lo que decide cómo sale el juego compilado: si no cambia,
# no hay nada que actualizar. No incluye la interfaz del instalador ni la documentación.
function Calcular-Huella([string]$raiz) {
    $rel = New-Object System.Collections.ArrayList
    foreach ($f in @('game.toml', 'CMakeLists.txt', 'bios_libre/bios_libre.toml', 'bios_libre/bios_libre.bin',
                     'tools/construir.ps1', 'tools/construir.sh', 'tools/JUGAR.bat')) {
        if (Test-Path -LiteralPath (Join-Path $raiz $f) -PathType Leaf) { [void]$rel.Add($f) }
    }
    foreach ($carpeta in @('parches', 'src')) {
        $dir = Join-Path $raiz $carpeta
        if (Test-Path -LiteralPath $dir -PathType Container) {
            Get-ChildItem -LiteralPath $dir -File -Recurse | ForEach-Object {
                $r = $_.FullName.Substring($raiz.TrimEnd('\', '/').Length).TrimStart('\', '/') -replace '\\', '/'
                [void]$rel.Add($r)
            }
        }
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        # Los archivos de texto se leen sin los retornos de carro (CR): así la huella no cambia si el
        # mismo proyecto llega con finales de línea de Windows (CRLF) o de Unix (LF), por ejemplo
        # descargado como zip de GitHub o clonado con git en Windows.
        $lineas = foreach ($r in ($rel | Sort-Object -Unique)) {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $raiz $r))
            if ($r -notlike '*.bin') { $bytes = [byte[]]@($bytes | Where-Object { $_ -ne 13 }) }
            $r + ':' + ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLower()
        }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lineas -join "`n"))
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLower()
    } finally { $sha.Dispose() }
}

# ── Icono de los accesos directos ─────────────────────────────────────────
# Si junto a INSTALAR.bat hay un «icono.ico», se copia a la carpeta del juego y lo usan los
# accesos directos y la entrada de «Aplicaciones». No viene en el zip (la imagen del juego es de
# Nintendo): cada persona deja el suyo. Devuelve la ruta del icono instalado, o '' si no hay.
function Instalar-Icono([string]$carpetaJuego) {
    $origen = Join-Path $RaizProyecto 'icono.ico'
    $destino = Join-Path $carpetaJuego 'icono.ico'
    if (Test-Path -LiteralPath $origen -PathType Leaf) {
        try { Copy-Item -LiteralPath $origen -Destination $destino -Force } catch { }
    }
    if (Test-Path -LiteralPath $destino -PathType Leaf) { return $destino }
    return ''
}

# ¿Hay un icono nuevo que aún no está en la carpeta del juego (o cambió)?
function Icono-Distinto([string]$carpetaJuego) {
    $origen = Join-Path $RaizProyecto 'icono.ico'
    if (-not (Test-Path -LiteralPath $origen -PathType Leaf)) { return $false }
    $destino = Join-Path $carpetaJuego 'icono.ico'
    if (-not (Test-Path -LiteralPath $destino -PathType Leaf)) { return $true }
    return ((Get-FileHash -LiteralPath $origen -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $destino -Algorithm SHA256).Hash)
}

# Cambia el icono de los accesos directos que ya existen (los que guarda instalacion.json)
# y el de la entrada de «Aplicaciones». Devuelve cuántos accesos se han cambiado.
function Aplicar-IconoAccesos($manifiesto, [string]$icono) {
    if (-not $EsWindows -or -not $icono) { return 0 }
    $cambiados = 0
    try {
        $ws = New-Object -ComObject WScript.Shell
        foreach ($a in @($manifiesto.accesos)) {
            if (-not $a -or -not (Test-Path -LiteralPath $a -PathType Leaf)) { continue }
            $lnk = $ws.CreateShortcut($a)
            $lnk.IconLocation = "$icono,0"
            $lnk.Save()
            $cambiados++
        }
    } catch { }
    try {
        if (Test-Path -Path $ClaveRegistro) { Set-ItemProperty -Path $ClaveRegistro -Name 'DisplayIcon' -Value $icono }
    } catch { }
    return $cambiados
}
