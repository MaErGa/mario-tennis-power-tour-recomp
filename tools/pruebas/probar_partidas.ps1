<#
.SYNOPSIS
    Pruebas de tools/PARTIDAS.ps1 (importar, exportar y copias de partidas).

.DESCRIPTION
    Crea una instalación falsa en una carpeta temporal (sin ROM ni juego) y prueba la herramienta con
    archivos inventados: partidas con relleno, con espejo, estados rápidos, archivos vacíos, etc.
    Funciona con PowerShell 5.1 (Windows) y con PowerShell 7 (Windows, Linux, macOS).
#>
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'PARTIDAS.ps1'
$base = Join-Path ([System.IO.Path]::GetTempPath()) ("probar-partidas-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$inst = Join-Path $base 'instalacion'
New-Item -ItemType Directory -Force -Path (Join-Path $inst 'roms') | Out-Null
[System.IO.File]::WriteAllBytes((Join-Path $inst 'MarioTennisPowerTourRecomp.exe'), [byte[]]@())
$sav = Join-Path $inst 'roms\mario_tennis_power_tour_eur.sav'
$copias = Join-Path $inst 'copias-de-partidas'

$fallos = 0
function Comprobar([bool]$condicion, [string]$texto) {
    if ($condicion) { Write-Host "  ok     $texto" }
    else { Write-Host "  FALLO  $texto"; $script:fallos++ }
}
function Bytes-Azar([int]$n, [int]$semilla) {
    $r = New-Object System.Random($semilla)
    $b = New-Object byte[] $n
    $r.NextBytes($b)
    return $b
}
function Bytes-Fijos([int]$n, [byte]$valor) {
    $b = New-Object byte[] $n
    for ($i = 0; $i -lt $n; $i++) { $b[$i] = $valor }
    return $b
}
function Unir-Bytes([byte[]]$a, [byte[]]$b) {
    $r = New-Object byte[] ($a.Length + $b.Length)
    [Array]::Copy($a, 0, $r, 0, $a.Length)
    [Array]::Copy($b, 0, $r, $a.Length, $b.Length)
    return $r
}
function Iguales([byte[]]$a, [byte[]]$b) {
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
    return $true
}
function Archivo([string]$nombre, [byte[]]$datos) {
    $ruta = Join-Path $base $nombre
    [System.IO.File]::WriteAllBytes($ruta, $datos)
    return $ruta
}
# Ejecuta la herramienta y devuelve su código de salida.
function Lanzar([string]$accion, [string]$archivo = '') {
    $global:LASTEXITCODE = 0
    & $script -Carpeta $inst -Silencioso -Accion $accion -Archivo $archivo *> $null
    return [int]$global:LASTEXITCODE
}
function Contar-Copias { if (Test-Path -LiteralPath $copias) { return @(Get-ChildItem -LiteralPath $copias -Filter '*.sav').Count } return 0 }

try {
    $a = Bytes-Azar 32768 1
    $b = Bytes-Azar 32768 2

    Write-Host 'Importar'
    Comprobar ((Lanzar 'Importar' ((Archivo 'a.sav' $a))) -eq 0) 'una partida de 32 KiB se importa'
    Comprobar (Iguales ([System.IO.File]::ReadAllBytes($sav)) $a) 'la partida queda idéntica'
    Comprobar ((Contar-Copias) -eq 0) 'sin partida anterior no hay copia'
    Comprobar ((Lanzar 'Importar' ((Archivo 'b.sav' $b))) -eq 0) 'una segunda se importa'
    Comprobar (Iguales ([System.IO.File]::ReadAllBytes($sav)) $b) 'la partida actual es la nueva'
    Comprobar ((Contar-Copias) -eq 1) 'la anterior se guardó en copias-de-partidas'
    $copia1 = (Get-ChildItem -LiteralPath $copias -Filter '*.sav' | Select-Object -First 1).FullName
    Comprobar (Iguales ([System.IO.File]::ReadAllBytes($copia1)) $a) 'la copia es la partida anterior'

    Write-Host 'Relleno y espejo (otros emuladores y flashcarts)'
    $r = Lanzar 'Importar' ((Archivo 'ff128.sav' (Unir-Bytes $a (Bytes-Fijos 98304 255))))
    Comprobar ($r -eq 0 -and (Iguales ([System.IO.File]::ReadAllBytes($sav)) $a)) '128 KiB con relleno 0xFF se recorta a 32 KiB'
    $r = Lanzar 'Importar' ((Archivo 'cero64.sav' (Unir-Bytes $b (Bytes-Fijos 32768 0))))
    Comprobar ($r -eq 0 -and (Iguales ([System.IO.File]::ReadAllBytes($sav)) $b)) '64 KiB con relleno 0x00 se recorta a 32 KiB'
    $r = Lanzar 'Importar' ((Archivo 'espejo.sav' (Unir-Bytes (Unir-Bytes $a $a) (Unir-Bytes $a $a))))
    Comprobar ($r -eq 0 -and (Iguales ([System.IO.File]::ReadAllBytes($sav)) $a)) '128 KiB con 4 copias iguales se recorta a 32 KiB'
    $corta = New-Object byte[] 8192
    [Array]::Copy($a, $corta, 8192)
    $r = Lanzar 'Importar' ((Archivo 'corta.sav' $corta))
    $esperada = Unir-Bytes $corta (Bytes-Fijos (32768 - 8192) 255)
    Comprobar ($r -eq 0 -and (Iguales ([System.IO.File]::ReadAllBytes($sav)) $esperada)) 'una partida de 8 KiB se completa con 0xFF hasta 32 KiB'
    [void](Lanzar 'Importar' ((Archivo 'a2.sav' $a)))

    Write-Host 'Archivos que no valen (no deben tocar la partida)'
    $antes = [System.IO.File]::ReadAllBytes($sav)
    $n0 = Contar-Copias
    $malos = @(
        @('datos distintos tras los 32 KiB', (Unir-Bytes $a (Bytes-Azar 32768 9)), 'x1.sav'),
        @('relleno con un byte distinto al final', (Unir-Bytes (Unir-Bytes $a (Bytes-Fijos 98303 255)) ([byte[]]@(1))), 'x2.sav'),
        @('archivo vacío', ([byte[]]@()), 'x3.sav'),
        @('estado rápido por la extensión (.state)', $a, 'x4.state'),
        @('estado rápido por la extensión (.ss0)', $a, 'x5.ss0'),
        @('archivo comprimido (zip)', (Unir-Bytes ([byte[]]@(0x50, 0x4B, 3, 4)) (Bytes-Fijos 500 0)), 'x6.bin'),
        @('estado de mGBA (PNG)', (Unir-Bytes ([byte[]]@(0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10)) (Bytes-Fijos 5000 0)), 'x7.bin'),
        @('estado de RetroArch (RASTATE)', (Unir-Bytes ([System.Text.Encoding]::ASCII.GetBytes('RASTATE')) (Bytes-Fijos 5000 0)), 'x8.bin')
    )
    foreach ($m in $malos) {
        $r = Lanzar 'Importar' ((Archivo $m[2] $m[1]))
        Comprobar ($r -eq 1) "se rechaza: $($m[0])"
    }
    Comprobar (Iguales ([System.IO.File]::ReadAllBytes($sav)) $antes) 'la partida no ha cambiado tras los rechazos'
    Comprobar ((Contar-Copias) -eq $n0) 'los rechazos no crean copias'
    Comprobar ((Lanzar 'Importar' ((Join-Path $base 'no-existe.sav'))) -eq 1) 'un archivo que no existe da error'
    # Una partida de exactamente 32 KiB es SRAM en bruto: no se interpreta su cabecera aunque parezca «PK».
    $casiZip = Bytes-Azar 32768 5
    $casiZip[0] = 0x50; $casiZip[1] = 0x4B
    $r = Lanzar 'Importar' ((Archivo 'pk.sav' $casiZip))
    Comprobar ($r -eq 0 -and (Iguales ([System.IO.File]::ReadAllBytes($sav)) $casiZip)) 'una partida de 32 KiB que empieza por «PK» se acepta'
    [void](Lanzar 'Importar' ((Archivo 'a3.sav' $a)))

    Write-Host 'Exportar'
    $destino = Join-Path $base 'salida\exportada.sav'
    Comprobar ((Lanzar 'Exportar' ($destino)) -eq 0) 'exportar funciona (y crea la carpeta de destino)'
    Comprobar (Iguales ([System.IO.File]::ReadAllBytes($destino)) $a) 'la exportada es igual a la partida'
    [System.IO.File]::WriteAllBytes($sav, (Unir-Bytes $a (Bytes-Fijos 98304 255)))
    [void](Lanzar 'Exportar' ($destino))
    Comprobar (Iguales ([System.IO.File]::ReadAllBytes($destino)) $a) 'aunque el .sav del juego traiga relleno, se exportan 32 KiB'
    Remove-Item -LiteralPath $sav -Force
    Comprobar ((Lanzar 'Exportar' ((Join-Path $base 'otra.sav'))) -eq 1) 'sin partida guardada, exportar da error'

    Write-Host 'Copias de seguridad'
    [System.IO.File]::WriteAllBytes($sav, $b)
    $n1 = Contar-Copias
    Comprobar ((Lanzar 'Copia') -eq 0 -and (Contar-Copias) -eq ($n1 + 1)) 'crear una copia añade un archivo'
    $manual = (Get-ChildItem -LiteralPath $copias -Filter '*manual.sav' | Select-Object -First 1).FullName
    [System.IO.File]::WriteAllBytes($sav, $a)
    Comprobar ((Lanzar 'Restaurar' ($manual)) -eq 0 -and (Iguales ([System.IO.File]::ReadAllBytes($sav)) $b)) 'recuperar una copia deja la partida de la copia'
    Comprobar ((Lanzar 'Restaurar' ((Join-Path $copias 'no-existe.sav'))) -eq 1) 'recuperar una copia que no existe da error'

    Write-Host 'rom.cfg'
    $otraRom = Join-Path $base 'otra_rom\mi_rom.gba'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $otraRom) | Out-Null
    Set-Content -LiteralPath (Join-Path $inst 'rom.cfg') -Value $otraRom -Encoding ASCII
    $r = Lanzar 'Importar' ((Archivo 'a4.sav' $a))
    Comprobar ($r -eq 0 -and (Test-Path -LiteralPath (Join-Path $base 'otra_rom\mi_rom.sav'))) 'la partida va junto a la ROM indicada en rom.cfg'
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fallos -gt 0) { Write-Host "`n$fallos prueba(s) fallida(s)."; exit 1 }
Write-Host "`nPruebas de Partidas: todo correcto."
exit 0
