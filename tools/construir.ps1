<#
.SYNOPSIS
    Compilación ligera de Mario Tennis: Power Tour en Windows (sin MSYS2, sin git, sin Python).

.DESCRIPTION
    De tu ROM al juego, con unas pocas descargas pequeñas en vez de un entorno de
    desarrollo entero:

      - Zig (trae un compilador de C/C++ completo), CMake y Ninja: ruedas oficiales de PyPI
        (~140 MB de descarga, ~0,5 GB descomprimidos). Se comprueba su SHA-256.
      - SDL2 (la biblioteca de ventana y mando): paquete de desarrollo oficial de GitHub (7 MB).
      - Las fuentes de gbarecomp, arm-recomp-core y recomp-ui, en el commit fijado (~8 MB).

    Después aplica los parches de parches/ (con un aplicador propio, sin git), recompila
    la BIOS libre y TU ROM a C++, compila el juego y monta la carpeta juego\.

    Todo lo que se descarga y se genera queda dentro de -Raiz (herramientas\, externo\, build\,
    generated\...), así que al acabar se puede borrar esa carpeta entera sin dejar rastro.
    Si se vuelve a ejecutar, reutiliza lo ya descargado y compilado (por eso actualizar es rápido).

    El ejecutable resultante solo necesita SDL2.dll (no depende de libstdc++, libgcc ni winpthread).

.PARAMETER Rom
    Tu ROM europea (.gba). Si no se indica, se busca en <Raiz>\roms.

.PARAMETER Raiz
    Carpeta del proyecto donde se construye (por defecto, la carpeta que contiene tools\).
    Debe tener una ruta sin espacios ni acentos (el instalador lo cuida).

.PARAMETER Herramientas
    Dónde se dejan Zig, CMake, Ninja y SDL2 (por defecto <Raiz>\herramientas).

.PARAMETER Nucleos
    Procesos de compilación en paralelo (0 = automático según núcleos y memoria).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\construir.ps1 -Rom D:\roms\mtpt.gba
#>
[CmdletBinding()]
param(
    [string]$Rom,
    [string]$Raiz,
    [string]$Herramientas,
    [int]$Nucleos = 0
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # sin la barra de Invoke-WebRequest (en PowerShell 5.1 la hace 10 veces más lenta)

# ── Versiones fijadas (las que se han probado) ─────────────────────────────
$RomSha1   = 'd61990974040d405b5bf8436ac8e1e0beb0f7964'
$RomTamano = 16777216
$RomNombre = 'mario_tennis_power_tour_eur.gba'
$ExeJuego  = 'MarioTennisPowerTourRecomp.exe'
$EspacioMinimoGB = 1.5

# Ruedas de PyPI: son archivos .zip con el programa de Windows dentro.
$Ruedas = @(
    @{ Nombre = 'zig';   Archivo = 'ziglang-0.16.0-py3-none-win_amd64.whl'; Version = '0.16.0'
       Sha256 = '089a16a4eb5a2f45151993342f8fabad24ff1a0723dc146642895c29208a3939'
       Url = 'https://files.pythonhosted.org/packages/a6/3c/baff40b3fc8ab4e83530246a52e8f3a5186c3606562712dfb58483b04f79/ziglang-0.16.0-py3-none-win_amd64.whl'
       Paquete = 'ziglang'; Interior = 'ziglang'; Programa = 'zig.exe'; MB = 99 },
    @{ Nombre = 'cmake'; Archivo = 'cmake-4.4.4-py3-none-win_amd64.whl'; Version = '4.4.4'
       Sha256 = 'ad8e0a38b5707e27882701146bdfffecacd80e7703fa0fc36c77528518d545af'
       Url = 'https://files.pythonhosted.org/packages/87/9c/a7918eeeed09b34aa5dc1b767367fb1a2dcbb56171be00be0fd1280fe752/cmake-4.4.4-py3-none-win_amd64.whl'
       Paquete = 'cmake'; Interior = 'cmake/data'; Programa = 'bin/cmake.exe'; MB = 42 },
    @{ Nombre = 'ninja'; Archivo = 'ninja-1.13.2-py3-none-win_amd64.whl'; Version = '1.13.2'
       Sha256 = '1293f4078278b70d0ee4b6cc8f3a9e030656c9b2f59909970343c4fe76070118'
       Url = 'https://files.pythonhosted.org/packages/3f/dd/3766b5f4d32e8a9b97d195496b0b01fbbe2e1a41669dab0cd6492a6ce199/ninja-1.13.2-py3-none-win_amd64.whl'
       Paquete = 'ninja'; Interior = 'ninja-1.13.2.data/scripts'; Programa = 'ninja.exe'; MB = 1 }
)
$Sdl = @{
    Nombre = 'sdl2'; Archivo = 'SDL2-devel-2.30.9-mingw.tar.gz'
    Sha256 = 'b188d165dc4a0372042bff3d0c18e9bb90772581e92a7b8b47b521b47714f75c'
    Url = 'https://github.com/libsdl-org/SDL/releases/download/release-2.30.9/SDL2-devel-2.30.9-mingw.tar.gz'
    Interior = 'SDL2-2.30.9/x86_64-w64-mingw32'
}
# Fuentes: archivos .zip de GitHub en el commit exacto (sin git). Los submódulos no vienen
# dentro, por eso arm-recomp-core (el único que hace falta) se trae aparte.
$Fuentes = @(
    @{ Nombre = 'gbarecomp';       Repo = 'mstan/gbarecomp';       Commit = 'edc2b80c73d83a2f35b9cfedaea0ea8d14647697'; Destino = 'externo/gbarecomp' },
    @{ Nombre = 'arm-recomp-core'; Repo = 'mstan/arm-recomp-core'; Commit = '1f13cdfd3b437a7a3919285f381987bd43f5234a'; Destino = 'externo/gbarecomp/external/arm-recomp-core' },
    # toml++ (lector de game.toml): gbarecomp lo clonaría con git al configurar; si ya está en
    # third_party/tomlpp (justo donde lo busca su CMakeLists.txt) no hace falta git.
    @{ Nombre = 'tomlplusplus';    Repo = 'marzer/tomlplusplus';   Commit = '30172438cee64926dc41fdd9c11fb3ba5b2ba9de'; Destino = 'externo/gbarecomp/third_party/tomlpp' },
    @{ Nombre = 'recomp-ui';       Repo = 'mstan/recomp-ui';       Commit = '0546fbcb0126bb14bf88d2128b4fe8a4229570a3'; Destino = 'externo/recomp-ui' }
)

# Solo para pruebas en Linux (no se usan en Windows):
#   MTP_WINE=<ruta de wine>  ejecuta los programas de Windows con Wine.
#   MTP_PRUEBA_LINUX=1       usa herramientas de Linux colocadas como si fueran las de Windows
#                            (herramientas\zig\zig.exe, etc.) y compila el recompilador para Linux.
$script:Wine = $env:MTP_WINE
$script:PruebaLinux = [bool]$env:MTP_PRUEBA_LINUX

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch { }
Add-Type -AssemblyName System.IO.Compression.FileSystem

# ── Mensajes ──────────────────────────────────────────────────────────────
function Escribir-Paso([string]$texto) { Write-Host ''; Write-Host "== $texto" -ForegroundColor Cyan }
function Escribir-Info([string]$texto) { Write-Host "   $texto" }
function Escribir-Ok([string]$texto)   { Write-Host "   [OK] $texto" -ForegroundColor Green }
function Fallo([string]$texto)         { throw $texto }

# ── Rutas ─────────────────────────────────────────────────────────────────
# Con Wine (pruebas) las rutas Unix se pasan a los programas de Windows como Z:\...
function Ruta-Win([string]$ruta) {
    $r = [System.IO.Path]::GetFullPath($ruta)
    if ($script:Wine) {
        if ($r.StartsWith('/')) { $r = 'Z:' + $r }
        return ($r -replace '/', '\')
    }
    return $r
}
function Ruta-Barra([string]$ruta) { return ((Ruta-Win $ruta) -replace '\\', '/') }
function Unir([string]$a, [string]$b) { return [System.IO.Path]::Combine($a, ($b -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)) }

function Borrar-Carpeta([string]$ruta) {
    if (-not (Test-Path -LiteralPath $ruta)) { return }
    try { [System.IO.Directory]::Delete($ruta, $true) }
    catch { Remove-Item -LiteralPath $ruta -Recurse -Force -ErrorAction SilentlyContinue }
}

function Sha256-De([string]$ruta) { return (Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash.ToLower() }
function Sha1-De([string]$ruta)   { return (Get-FileHash -LiteralPath $ruta -Algorithm SHA1).Hash.ToLower() }

function Sha256-Texto([string]$texto) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($texto))) -replace '-', '').ToLower() }
    finally { $sha.Dispose() }
}

# Ejecuta un programa, enseña su salida y devuelve el código de salida.
function Ejecutar([string]$programa, [string[]]$argumentos, [string]$carpeta, [bool]$nativo = $false) {
    if ($carpeta) { Push-Location -LiteralPath $carpeta }
    try {
        if ($script:Wine -and -not $nativo) {
            $todo = @($programa) + $argumentos
            & $script:Wine @todo | Out-Host
        } else {
            & $programa @argumentos | Out-Host
        }
        return $LASTEXITCODE
    } finally {
        if ($carpeta) { Pop-Location }
    }
}
function Ejecutar-Ok([string]$programa, [string[]]$argumentos, [string]$carpeta, [string]$que) {
    $codigo = Ejecutar $programa $argumentos $carpeta
    if ($codigo -ne 0) { Fallo "Ha fallado: $que (código $codigo). Mira los mensajes de arriba." }
}

# ── Descargas ─────────────────────────────────────────────────────────────
# Reutiliza el archivo si ya está descargado (y su SHA-256 coincide, si se conoce).
function Descargar([string[]]$urls, [string]$destino, [string]$sha256, [string]$nombre) {
    if (Test-Path -LiteralPath $destino) {
        if (-not $sha256 -or (Sha256-De $destino) -eq $sha256) {
            Escribir-Info "${nombre}: ya descargado."
            return
        }
        Remove-Item -LiteralPath $destino -Force
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destino) | Out-Null
    $parcial = "$destino.parte"
    $ultimo = ''
    foreach ($url in $urls) {
        for ($intento = 1; $intento -le 3; $intento++) {
            try {
                Escribir-Info "Descargando $nombre..."
                Invoke-WebRequest -Uri $url -OutFile $parcial -UseBasicParsing
                if ($sha256 -and (Sha256-De $parcial) -ne $sha256) {
                    throw 'el archivo descargado no coincide con la huella SHA-256 esperada'
                }
                Move-Item -LiteralPath $parcial -Destination $destino -Force
                return
            } catch {
                $ultimo = $_.Exception.Message
                Remove-Item -LiteralPath $parcial -Force -ErrorAction SilentlyContinue
                if ($intento -lt 3) { Start-Sleep -Seconds (2 * $intento) }
            }
        }
    }
    Fallo "No he podido descargar $nombre ($ultimo)."
}

# Descomprime un .zip/.whl y mueve la subcarpeta $interior a $destino.
function Extraer-Zip([string]$zip, [string]$interior, [string]$destino, [string]$temporal) {
    Borrar-Carpeta $temporal
    Borrar-Carpeta $destino
    New-Item -ItemType Directory -Force -Path $temporal | Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $temporal)
    $origen = Unir $temporal $interior
    if (-not (Test-Path -LiteralPath $origen -PathType Container)) {
        Fallo "El archivo $(Split-Path -Leaf $zip) no tiene la carpeta esperada («$interior»)."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destino) | Out-Null
    Move-Item -LiteralPath $origen -Destination $destino
    Borrar-Carpeta $temporal
}

# ── Programa principal ────────────────────────────────────────────────────
if (-not $Raiz) { $Raiz = Split-Path -Parent $PSScriptRoot }
$Raiz = [System.IO.Path]::GetFullPath($Raiz)
if (-not $Herramientas) { $Herramientas = Unir $Raiz 'herramientas' }
$Herramientas = [System.IO.Path]::GetFullPath($Herramientas)
$Descargas = Unir $Raiz 'descargas'

if ($Raiz -notmatch '^[\x21-\x7E]+$' -and -not $script:Wine) {
    Fallo "La carpeta de trabajo no puede tener espacios ni acentos: $Raiz`nUsa otra (por ejemplo C:\MTP-obra)."
}
if ($Nucleos -le 0) {
    $Nucleos = [Environment]::ProcessorCount
    try {
        $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        $Nucleos = [Math]::Min($Nucleos, [Math]::Floor($ram / 1.5GB))
    } catch { }
    $Nucleos = [Math]::Max(1, [int]$Nucleos)
}

# 1. La ROM ─────────────────────────────────────────────────────────────────
Escribir-Paso '1/7 Comprobando tu ROM'
$romOrigen = $Rom
if (-not $romOrigen) { $romOrigen = Unir $Raiz ('roms/' + $RomNombre) }
if (-not (Test-Path -LiteralPath $romOrigen -PathType Leaf)) { Fallo "No encuentro tu ROM: $romOrigen" }
$romOrigen = (Resolve-Path -LiteralPath $romOrigen).ProviderPath
if ((Get-Item -LiteralPath $romOrigen).Length -ne $RomTamano) { Fallo "La ROM debe medir 16 MiB (16777216 bytes)." }
$shaRom = Sha1-De $romOrigen
if ($shaRom -ne $RomSha1) {
    Fallo "Esta ROM no es la versión europea (BTMP, rev. 0).`n  SHA-1 de tu archivo: $shaRom`n  SHA-1 esperado     : $RomSha1"
}
New-Item -ItemType Directory -Force -Path (Unir $Raiz 'roms') | Out-Null
$romDestino = Unir $Raiz ('roms/' + $RomNombre)
if ($romOrigen -ne [System.IO.Path]::GetFullPath($romDestino)) { Copy-Item -LiteralPath $romOrigen -Destination $romDestino -Force }
Escribir-Ok "ROM correcta (SHA-1 $shaRom)."

try {
    $libre = ([System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($Raiz))).AvailableFreeSpace
    if ($libre -lt ($EspacioMinimoGB * 1GB)) {
        Fallo ("No hay espacio suficiente: la compilación necesita unos {0} GB temporales y quedan {1:N1} GB libres en la unidad de {2}." -f $EspacioMinimoGB, ($libre / 1GB), $Raiz)
    }
} catch [System.IO.IOException] { } catch [System.ArgumentException] { }

# 2. Herramientas ───────────────────────────────────────────────────────────
Escribir-Paso '2/7 Descargando las herramientas (Zig, CMake, Ninja y SDL2; unos 150 MB)'
New-Item -ItemType Directory -Force -Path $Herramientas | Out-Null
foreach ($r in $Ruedas) {
    $destino = Unir $Herramientas $r.Nombre
    $marca = Unir $destino '.mtp-sha256'
    $programa = Unir $destino $r.Programa
    if ((Test-Path -LiteralPath $programa) -and (Test-Path -LiteralPath $marca) -and ((Get-Content -LiteralPath $marca -Raw).Trim() -eq $r.Sha256)) {
        Escribir-Ok "$($r.Nombre) $($r.Version) ya está preparado."
        continue
    }
    $rueda = Unir $Descargas $r.Archivo
    $urls = @($r.Url)
    Descargar $urls $rueda $r.Sha256 "$($r.Nombre) $($r.Version) (~$($r.MB) MB)"
    Escribir-Info "Descomprimiendo $($r.Nombre)..."
    Extraer-Zip $rueda $r.Interior $destino (Unir $Herramientas ('_tmp_' + $r.Nombre))
    if (-not (Test-Path -LiteralPath $programa)) { Fallo "Tras descomprimir $($r.Nombre) no aparece $($r.Programa)." }
    Set-Content -LiteralPath $marca -Value $r.Sha256 -Encoding ASCII
    Escribir-Ok "$($r.Nombre) $($r.Version) preparado."
}
# SDL2 (tar.gz: lo abre tar.exe, que trae Windows 10/11)
$sdlDestino = Unir $Herramientas 'sdl2'
$sdlMarca = Unir $sdlDestino '.mtp-sha256'
$sdlPrefijo = Unir $sdlDestino 'x86_64-w64-mingw32'
if ((Test-Path -LiteralPath (Unir $sdlPrefijo 'bin/SDL2.dll')) -and (Test-Path -LiteralPath $sdlMarca) -and ((Get-Content -LiteralPath $sdlMarca -Raw).Trim() -eq $Sdl.Sha256)) {
    Escribir-Ok 'SDL2 ya está preparado.'
} else {
    $tgz = Unir $Descargas $Sdl.Archivo
    Descargar @($Sdl.Url) $tgz $Sdl.Sha256 'SDL2 2.30.9 (~7 MB)'
    Escribir-Info 'Descomprimiendo SDL2...'
    Borrar-Carpeta $sdlDestino
    New-Item -ItemType Directory -Force -Path $sdlDestino | Out-Null
    if ($script:Wine) { $tar = 'tar' }
    else {
        $tar = ''
        if ($env:SystemRoot) { $tar = Join-Path $env:SystemRoot 'System32\tar.exe' }
        if (-not $tar -or -not (Test-Path -LiteralPath $tar)) {
            $cmd = Get-Command tar -ErrorAction SilentlyContinue
            if (-not $cmd) { Fallo 'No encuentro tar.exe (viene con Windows 10 versión 1803 o posterior).' }
            $tar = $cmd.Source
        }
    }
    # Se ejecuta desde «descargas» con el nombre del archivo a secas: algunas versiones de tar
    # interpretan «C:» en un nombre de archivo como un equipo remoto.
    $codigo = Ejecutar $tar @('-xzf', $Sdl.Archivo, '-C', $sdlDestino, $Sdl.Interior) $Descargas ([bool]$script:Wine)
    if ($codigo -ne 0) { Fallo "tar no ha podido descomprimir SDL2 (código $codigo)." }
    $extraido = Unir $sdlDestino $Sdl.Interior
    if (-not (Test-Path -LiteralPath $extraido)) { Fallo 'No he podido descomprimir SDL2.' }
    Move-Item -LiteralPath $extraido -Destination $sdlPrefijo
    Borrar-Carpeta (Unir $sdlDestino 'SDL2-2.30.9')
    Set-Content -LiteralPath $sdlMarca -Value $Sdl.Sha256 -Encoding ASCII
    Escribir-Ok 'SDL2 preparado.'
}

$zig   = Unir $Herramientas 'zig/zig.exe'
$cmake = Unir $Herramientas 'cmake/bin/cmake.exe'
$ninja = Unir $Herramientas 'ninja/ninja.exe'

# 3. Fuentes ────────────────────────────────────────────────────────────────
Escribir-Paso '3/7 Descargando las fuentes de gbarecomp, toml++ y recomp-ui (unos 10 MB)'
$carpetaParches = Unir $Raiz 'parches'
$parches = @(Get-ChildItem -LiteralPath $carpetaParches -Filter 'gbarecomp-*.patch' -File | Sort-Object Name)
if ($parches.Count -eq 0) { Fallo "No hay parches en $carpetaParches" }
$huellaParches = Sha256-Texto (($parches | ForEach-Object { $_.Name + ':' + (Sha256-De $_.FullName) }) -join ';')
$gbarecomp = Unir $Raiz 'externo/gbarecomp'
$recompUi  = Unir $Raiz 'externo/recomp-ui'
$marcaParches = Unir $gbarecomp '.mtp-parches'
foreach ($f in $Fuentes) {
    $destino = Unir $Raiz $f.Destino
    $marca = Unir $destino '.mtp-commit'
    $vigente = (Test-Path -LiteralPath $marca) -and ((Get-Content -LiteralPath $marca -Raw).Trim() -eq $f.Commit)
    # Si los parches han cambiado desde que se aplicaron, se parte de las fuentes limpias.
    if ($vigente -and $f.Nombre -eq 'gbarecomp' -and (Test-Path -LiteralPath $marcaParches) -and
        ((Get-Content -LiteralPath $marcaParches -Raw).Trim() -ne $huellaParches)) {
        Escribir-Info 'Los parches han cambiado: vuelvo a extraer gbarecomp limpio.'
        $vigente = $false
    }
    if ($vigente) {
        Escribir-Ok "$($f.Nombre) ya está en el commit $($f.Commit.Substring(0, 8))."
        continue
    }
    $zip = Unir $Descargas ("$($f.Nombre)-$($f.Commit).zip")
    $urls = @("https://github.com/$($f.Repo)/archive/$($f.Commit).zip", "https://codeload.github.com/$($f.Repo)/zip/$($f.Commit)")
    Descargar $urls $zip '' "$($f.Nombre) $($f.Commit.Substring(0, 8))"
    $temporal = Unir $Descargas ('_x_' + $f.Nombre)
    Extraer-Zip $zip ("$($f.Nombre)-$($f.Commit)") $destino $temporal
    if (-not (Test-Path -LiteralPath (Unir $destino 'CMakeLists.txt'))) { Fallo "Las fuentes de $($f.Nombre) no parecen correctas (falta CMakeLists.txt)." }
    Set-Content -LiteralPath $marca -Value $f.Commit -Encoding ASCII
    Escribir-Ok "$($f.Nombre) listo."
}
# El submódulo se trae después de gbarecomp: si gbarecomp se ha vuelto a extraer, la marca de
# arm-recomp-core ya no existe y se repite (el orden de $Fuentes lo garantiza).

# 4. Parches ────────────────────────────────────────────────────────────────
Escribir-Paso '4/7 Aplicando los parches de parches/ a gbarecomp'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)   # 1 byte = 1 carácter: no toca la codificación de los archivos

function Analizar-Parche([string]$texto) {
    $lineas = $texto -split "`n"
    $archivos = New-Object System.Collections.ArrayList
    $actual = $null
    $i = 0
    while ($i -lt $lineas.Count) {
        $l = $lineas[$i].TrimEnd("`r")
        if ($l -match '^diff --git a/(\S+) b/(\S+)$') {
            $actual = @{ Archivo = $matches[2]; Hunks = (New-Object System.Collections.ArrayList) }
            [void]$archivos.Add($actual)
            $i++
        }
        elseif ($l -match '^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@') {
            if (-not $actual) { Fallo 'Parche mal formado: un bloque sin archivo.' }
            $viejoLen = 1; if ($matches[2]) { $viejoLen = [int]$matches[2] }
            $nuevoLen = 1; if ($matches[4]) { $nuevoLen = [int]$matches[4] }
            $hunk = @{ ViejoIni = [int]$matches[1]; Lineas = (New-Object System.Collections.ArrayList) }
            $i++
            $v = 0; $n = 0
            while ($v -lt $viejoLen -or $n -lt $nuevoLen) {
                if ($i -ge $lineas.Count) { Fallo 'Parche mal formado: termina a mitad de un bloque.' }
                $t = $lineas[$i].TrimEnd("`r")
                $tipo = ' '; $contenido = ''
                if ($t.Length -gt 0) { $tipo = $t.Substring(0, 1); $contenido = $t.Substring(1) }
                switch ($tipo) {
                    ' ' { $v++; $n++ }
                    '-' { $v++ }
                    '+' { $n++ }
                    default { Fallo "Parche con una línea no admitida: «$t»." }
                }
                [void]$hunk.Lineas.Add(@{ Tipo = $tipo; Texto = $contenido })
                $i++
            }
            [void]$actual.Hunks.Add($hunk)
        }
        else { $i++ }
    }
    return $archivos
}

# Busca la secuencia de líneas $buscada en $lineas, empezando por $esperada y alejándose.
function Buscar-Secuencia($lineas, [string[]]$buscada, [int]$esperada) {
    $n = $lineas.Count
    $m = $buscada.Count
    if ($m -eq 0) { return -1 }
    for ($d = 0; $d -le $n; $d++) {
        foreach ($p in @(($esperada - $d), ($esperada + $d))) {
            if ($p -lt 0 -or $p + $m -gt $n) { continue }
            $ok = $true
            for ($k = 0; $k -lt $m; $k++) {
                if ($lineas[$p + $k].TrimEnd("`r") -cne $buscada[$k]) { $ok = $false; break }
            }
            if ($ok) { return $p }
            if ($d -eq 0) { break }
        }
    }
    return -1
}

function Aplicar-ParcheArchivo([string]$raizFuentes, $archivo) {
    $ruta = Unir $raizFuentes $archivo.Archivo
    if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { Fallo "El parche toca un archivo que no existe: $($archivo.Archivo)" }
    $texto = $Latin1.GetString([System.IO.File]::ReadAllBytes($ruta))
    $lineas = New-Object 'System.Collections.Generic.List[string]'
    $lineas.AddRange([string[]]($texto -split "`n"))
    $desfase = 0
    $hechos = 0
    foreach ($h in $archivo.Hunks) {
        $viejo = New-Object System.Collections.ArrayList
        $nuevo = New-Object System.Collections.ArrayList
        foreach ($l in $h.Lineas) {
            if ($l.Tipo -ne '+') { [void]$viejo.Add($l.Texto) }
            if ($l.Tipo -ne '-') { [void]$nuevo.Add($l.Texto) }
        }
        $esperada = $h.ViejoIni - 1 + $desfase
        $pos = Buscar-Secuencia $lineas ([string[]]$viejo.ToArray()) $esperada
        if ($pos -lt 0) {
            # ¿Ya estaba aplicado este bloque?
            $yaEsta = Buscar-Secuencia $lineas ([string[]]$nuevo.ToArray()) $esperada
            if ($yaEsta -ge 0) { continue }
            Fallo "El parche no encaja en $($archivo.Archivo) (bloque que empieza en la línea $($h.ViejoIni)). ¿Es la versión de gbarecomp que toca?"
        }
        $conCr = $lineas[$pos].EndsWith("`r")
        $reemplazo = New-Object System.Collections.ArrayList
        foreach ($t in $nuevo) { if ($conCr) { [void]$reemplazo.Add($t + "`r") } else { [void]$reemplazo.Add($t) } }
        $lineas.RemoveRange($pos, $viejo.Count)
        $lineas.InsertRange($pos, [string[]]$reemplazo.ToArray())
        $desfase += ($nuevo.Count - $viejo.Count)
        $hechos++
    }
    if ($hechos -gt 0) {
        [System.IO.File]::WriteAllBytes($ruta, $Latin1.GetBytes([string]::Join("`n", $lineas)))
    }
    return $hechos
}

if ((Test-Path -LiteralPath $marcaParches) -and ((Get-Content -LiteralPath $marcaParches -Raw).Trim() -eq $huellaParches)) {
    Escribir-Ok 'Los parches ya estaban aplicados.'
} else {
    foreach ($p in $parches) {
        $archivos = Analizar-Parche ($Latin1.GetString([System.IO.File]::ReadAllBytes($p.FullName)))
        $bloques = 0
        foreach ($a in $archivos) { $bloques += (Aplicar-ParcheArchivo $gbarecomp $a) }
        Escribir-Info ("{0}: {1} archivo(s), {2} bloque(s) aplicados" -f $p.Name, $archivos.Count, $bloques)
    }
    Set-Content -LiteralPath $marcaParches -Value $huellaParches -Encoding ASCII
    Escribir-Ok 'Parches aplicados.'
}

# 5. Compilador ─────────────────────────────────────────────────────────────
Escribir-Paso '5/7 Preparando el compilador'
$envoltorios = Unir $Herramientas 'envoltorios'
New-Item -ItemType Directory -Force -Path $envoltorios | Out-Null
$zigWin = Ruta-Win $zig
# Zig se usa como si fuera gcc/clang: cada envoltorio es un .cmd que llama a «zig cc», «zig c++»...
# (el objetivo x86_64-windows-gnu enlaza solo con la biblioteca de C que trae Zig: el .exe no
#  necesita DLL de MinGW).
$definiciones = @{
    'zig-cc'     = @('cc', '-target x86_64-windows-gnu')
    'zig-cxx'    = @('c++', '-target x86_64-windows-gnu')
    'zig-ar'     = @('ar', '')
    'zig-ranlib' = @('ranlib', '')
}
$extEnvoltorio = '.cmd'
if ($script:PruebaLinux) { $extEnvoltorio = '.sh' }
foreach ($nombre in $definiciones.Keys) {
    $orden = (("$($definiciones[$nombre][0]) $($definiciones[$nombre][1])").Trim())
    $archivo = Unir $envoltorios ($nombre + $extEnvoltorio)
    if ($script:PruebaLinux) {
        [System.IO.File]::WriteAllText($archivo, "#!/bin/sh`nexec `"$zigWin`" $orden `"`$@`"`n", (New-Object System.Text.UTF8Encoding($false)))
        & chmod +x $archivo
    } else {
        [System.IO.File]::WriteAllText($archivo, "@echo off`r`n`"$zigWin`" $orden %*`r`n", [System.Text.Encoding]::ASCII)
    }
}
$sdlBarra = Ruta-Barra $sdlPrefijo
$cadenaHerramientas = Unir $Herramientas 'zig-windows.cmake'
$envBarra = Ruta-Barra $envoltorios
# -w: sin avisos del compilador (el código recompilado genera miles y solo estorban).
# -fno-sanitize=undefined: «zig cc» activa por defecto una comprobación de comportamiento
#  indefinido que aquí no se quiere (ni en velocidad ni en comportamiento).
$cmakeTexto = @"
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER "$envBarra/zig-cc$extEnvoltorio")
set(CMAKE_CXX_COMPILER "$envBarra/zig-cxx$extEnvoltorio")
set(CMAKE_AR "$envBarra/zig-ar$extEnvoltorio")
set(CMAKE_RANLIB "$envBarra/zig-ranlib$extEnvoltorio")
set(CMAKE_C_FLAGS_INIT "-w -fno-sanitize=undefined")
set(CMAKE_CXX_FLAGS_INIT "-w -fno-sanitize=undefined")
set(CMAKE_PREFIX_PATH "$sdlBarra")
set(SDL2_DIR "$sdlBarra/lib/cmake/SDL2" CACHE PATH "SDL2 para Windows (MinGW)")
set(CMAKE_FIND_ROOT_PATH "$sdlBarra")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
"@
[System.IO.File]::WriteAllText($cadenaHerramientas, ($cmakeTexto -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))

# La caché de Zig (bibliotecas de C y C++ ya compiladas) se queda dentro de la carpeta de trabajo.
$cacheZig = Unir $Raiz 'cache-zig'
New-Item -ItemType Directory -Force -Path $cacheZig | Out-Null
$env:ZIG_GLOBAL_CACHE_DIR = Ruta-Win $cacheZig
$env:ZIG_LOCAL_CACHE_DIR = Ruta-Win $cacheZig
Escribir-Ok 'Compilador listo (Zig).'

$argsCmakeBase = @('-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$(Ruta-Barra $ninja)",
                   "-DCMAKE_TOOLCHAIN_FILE=$(Ruta-Barra $cadenaHerramientas)", '-DCMAKE_BUILD_TYPE=Release')

# 6. Recompilador, BIOS libre y tu ROM ───────────────────────────────────────
Escribir-Paso '6/7 Recompilando la BIOS libre y tu ROM (de ARM/Thumb a C++)'
$compRecomp = Unir $Raiz 'build/recompilador'
Escribir-Info 'Compilando el recompilador (gba_recompile)...'
$argsRecomp = $argsCmakeBase
if ($script:PruebaLinux) { $argsRecomp = @('-G', 'Ninja', "-DCMAKE_MAKE_PROGRAM=$(Ruta-Barra $ninja)", '-DCMAKE_BUILD_TYPE=Release') }
Ejecutar-Ok $cmake (@('-S', (Ruta-Win $gbarecomp), '-B', (Ruta-Win $compRecomp)) + $argsRecomp) $Raiz 'configurar el recompilador'
Ejecutar-Ok $cmake @('--build', (Ruta-Win $compRecomp), '--target', 'gba_recompile', '-j', [string]$Nucleos) $Raiz 'compilar el recompilador'
$nombreRecomp = 'gba_recompile.exe'
if ($script:PruebaLinux) { $nombreRecomp = 'gba_recompile' }
$recompilador = Get-ChildItem -LiteralPath $compRecomp -Recurse -Filter $nombreRecomp -File | Select-Object -First 1
if (-not $recompilador) { Fallo "No encuentro $nombreRecomp tras compilarlo." }

# Solo se regenera el C++ si ha cambiado algo de lo que depende (así actualizar no recompila todo).
$huellaGen = Sha256-Texto ((@(
    (Sha256-De (Unir $Raiz 'game.toml')),
    (Sha256-De (Unir $Raiz 'bios_libre/bios_libre.toml')),
    (Sha256-De (Unir $Raiz 'bios_libre/bios_libre.bin')),
    (Sha256-De $recompilador.FullName), $RomSha1, $huellaParches) -join ';'))
$generado = Unir $Raiz 'generated'
$generadoBios = Unir $Raiz 'generated_bios'
$marcaGen = Unir $generado '.mtp-huella'
if ((Test-Path -LiteralPath $marcaGen) -and ((Get-Content -LiteralPath $marcaGen -Raw).Trim() -eq $huellaGen) -and
    (Test-Path -LiteralPath (Unir $generadoBios 'bios_recompiled.cpp'))) {
    Escribir-Ok 'El código generado ya estaba al día.'
} else {
    Borrar-Carpeta $generado
    Borrar-Carpeta $generadoBios
    Escribir-Info 'Recompilando la BIOS libre...'
    Ejecutar-Ok $recompilador.FullName @('--bios', (Ruta-Win (Unir $Raiz 'bios_libre/bios_libre.bin')),
        '--config', (Ruta-Win (Unir $Raiz 'bios_libre/bios_libre.toml')), '--out', (Ruta-Win $generadoBios)) $Raiz 'recompilar la BIOS libre'
    Escribir-Info 'Recompilando tu ROM...'
    Ejecutar-Ok $recompilador.FullName @('--rom', (Ruta-Win $romDestino),
        '--config', (Ruta-Win (Unir $Raiz 'game.toml')), '--out', (Ruta-Win $generado)) $Raiz 'recompilar tu ROM'
    Set-Content -LiteralPath $marcaGen -Value $huellaGen -Encoding ASCII
    Escribir-Ok 'Código generado.'
}

# 7. El juego ───────────────────────────────────────────────────────────────
Escribir-Paso "7/7 Compilando el juego (20-60 minutos la primera vez; $Nucleos procesos en paralelo)"
$compJuego = Unir $Raiz 'build/juego'
# --log-level=ERROR: gbarecomp avisa de que no encuentra las DLL de MinGW en C:/msys64; aquí no
# hacen falta (el .exe solo usa SDL2.dll, que se copia más abajo) y el aviso asusta sin motivo.
Ejecutar-Ok $cmake (@('-S', (Ruta-Win $Raiz), '-B', (Ruta-Win $compJuego), '--log-level=ERROR') + $argsCmakeBase +
    @("-DGBARECOMP_ROOT=$(Ruta-Barra $gbarecomp)", "-DRECOMP_UI_ROOT=$(Ruta-Barra $recompUi)")) $Raiz 'configurar el juego'
Ejecutar-Ok $cmake @('--build', (Ruta-Win $compJuego), '--target', 'MarioTennisPowerTourRecomp', '-j', [string]$Nucleos) $Raiz 'compilar el juego'

Escribir-Info 'Montando la carpeta juego\...'
$salida = Unir $Raiz 'juego'
Borrar-Carpeta $salida
New-Item -ItemType Directory -Force -Path (Unir $salida 'roms') | Out-Null
New-Item -ItemType Directory -Force -Path (Unir $salida 'bios_libre') | Out-Null
$exe = Unir $compJuego $ExeJuego
if (-not (Test-Path -LiteralPath $exe)) { Fallo "No encuentro el ejecutable compilado: $exe" }
Copy-Item -LiteralPath $exe -Destination $salida
Copy-Item -LiteralPath (Unir $sdlPrefijo 'bin/SDL2.dll') -Destination $salida
$assets = Unir $compJuego 'assets'
if (Test-Path -LiteralPath $assets -PathType Container) { Copy-Item -LiteralPath $assets -Destination (Unir $salida 'assets') -Recurse }
Copy-Item -LiteralPath (Unir $Raiz 'game.toml') -Destination $salida
Copy-Item -LiteralPath (Unir $Raiz 'bios_libre/bios_libre.bin') -Destination (Unir $salida 'bios_libre')
Copy-Item -LiteralPath (Unir $Raiz 'bios_libre/LICENSE-Cult-of-GBA-BIOS.txt') -Destination (Unir $salida 'bios_libre')
Copy-Item -LiteralPath $romDestino -Destination (Unir $salida 'roms')
Copy-Item -LiteralPath (Unir $Raiz 'tools/JUGAR.bat') -Destination (Unir $salida 'JUGAR.bat')

# Las descargas ya están extraídas (cada herramienta y cada fuente lleva su marca): se borran.
Borrar-Carpeta $Descargas

Escribir-Paso 'Listo'
Escribir-Info "El juego está en: $salida"
Escribir-Info 'Ejecútalo con JUGAR.bat o con MarioTennisPowerTourRecomp.exe.'
