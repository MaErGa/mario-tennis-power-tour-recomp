<#
.SYNOPSIS
    Pruebas de la elección de la carpeta temporal de compilación (Obtener-DirObra de tools/INSTALAR.ps1).

.DESCRIPTION
    Carga las funciones reales de INSTALAR.ps1 y simula discos con más o menos espacio libre:
    C: casi llena con el juego en D:, discos sin sitio, carpeta conservada de una instalación anterior...
    Funciona con PowerShell 5.1 (Windows) y con PowerShell 7 (Windows, Linux, macOS).
#>
$ErrorActionPreference = 'Stop'
$tools = Split-Path -Parent $PSScriptRoot
. (Join-Path $tools 'comun.ps1')

# Funciones reales (por su definición en el archivo, sin ejecutar el instalador).
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $tools 'INSTALAR.ps1'), [ref]$null, [ref]$null)
foreach ($nombre in @('Espacio-Necesario', 'Obtener-DirObra')) {
    $f = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $nombre }, $true)
    if (-not $f) { throw "No encuentro la función $nombre en INSTALAR.ps1" }
    Invoke-Expression $f.Extent.Text
}

# Datos y sustitutos de lo que toca el sistema (discos y mensajes).
$EspacioLigeroGB = 1.5; $EspacioMsys2ConGB = 1.5; $EspacioMsys2SinGB = 4.0
$Metodo = 'ligero'; $Msys2 = Join-Path ([System.IO.Path]::GetTempPath()) 'msys64-que-no-existe'
$LongitudMaxObra = 500
$script:libres = @{}
$script:avisos = New-Object System.Collections.ArrayList
function Escribir-Aviso([string]$t) { [void]$script:avisos.Add($t) }
function Formatear-Tamano([double]$b) { return ('{0:N1} GB' -f ($b / 1GB)) }
function Espacio-Libre([string]$ruta) {
    if ($ruta -match '^([A-Za-z]):') { return [long]$script:libres[$matches[1].ToUpper() + ':\'] }
    return [long]$script:libres['C:\']      # la carpeta por defecto (perfil del usuario) se cuenta en C:
}
function Raiz-De([string]$ruta) {
    if ($ruta -match '^([A-Za-z]:\\)') { return $matches[1].ToUpper() }
    return ''
}
function Unidades([hashtable]$mapa) {
    $r = @()
    foreach ($k in $mapa.Keys) { $r += @{ Raiz = $k; Libre = [long]($mapa[$k] * 1GB) } }
    return ,$r
}

$fallos = 0
function Comprobar([bool]$condicion, [string]$texto) {
    if ($condicion) { Write-Host "  ok     $texto" }
    else { Write-Host "  FALLO  $texto"; $script:fallos++ }
}
function Caso([hashtable]$gb, [string]$destino, $anterior) {
    $script:libres = @{}
    foreach ($k in $gb.Keys) { $script:libres[$k] = [long]($gb[$k] * 1GB) }
    $script:avisos.Clear()
    $r = Obtener-DirObra $destino $anterior (Unidades $gb)
    return ([string]$r).Replace('/', '\')
}

Write-Host 'Elección de la carpeta de compilación'
$r = Caso @{ 'C:\' = 50; 'D:\' = 100 } 'D:\Games\Mario Tennis Power Tour' $null
Comprobar ($r -notmatch '^[A-Z]:\\MTP-obra$' -and $script:avisos.Count -eq 0) "C: con espacio: se queda la carpeta de siempre ($r)"

$r = Caso @{ 'C:\' = 1.3; 'D:\' = 100 } 'D:\Games\Mario Tennis Power Tour' $null
Comprobar ($r -eq 'D:\MTP-obra') "C: con 1,3 GB y el juego en D: (el caso real): usa D:\MTP-obra ($r)"
Comprobar ($script:avisos.Count -eq 1) 'avisa de que usa otra unidad'

$r = Caso @{ 'C:\' = 1.3; 'D:\' = 1.0; 'E:\' = 20 } 'D:\Juegos\MTP' $null
Comprobar ($r -eq 'E:\MTP-obra') "la unidad del juego tampoco llega: usa la que tiene sitio ($r)"

$r = Caso @{ 'C:\' = 1.3; 'D:\' = 30; 'E:\' = 200 } 'F:\Juegos\MTP' $null
Comprobar ($r -eq 'E:\MTP-obra') "el juego en una unidad que no está en la lista: la de más espacio ($r)"

$r = Caso @{ 'C:\' = 0.4; 'D:\' = 0.5 } 'D:\MTP' $null
Comprobar ($r -notmatch '^[A-Z]:\\MTP-obra$') "ninguna unidad tiene sitio: devuelve la de siempre para que el error lo explique ($r)"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('probar-obra-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $tmp 'build') | Out-Null
$ant = [pscustomobject]@{ obra = $tmp }
$r = Caso @{ 'C:\' = 0.4; 'D:\' = 100 } 'D:\MTP' $ant
Comprobar ($r.Replace('\', '/') -eq ([string]$tmp).Replace('\', '/')) 'carpeta conservada con lo compilado: se reutiliza aunque C: vaya justa'
Remove-Item -Recurse -Force -LiteralPath $tmp

$ant = [pscustomobject]@{ obra = (Join-Path ([System.IO.Path]::GetTempPath()) 'obra-que-no-existe-xyz') }
$r = Caso @{ 'C:\' = 1.3; 'D:\' = 100 } 'D:\MTP' $ant
Comprobar ($r -eq 'D:\MTP-obra') 'carpeta anterior que ya no existe: se vuelve a elegir'

$Metodo = 'msys2'
$r = Caso @{ 'C:\' = 3.0; 'D:\' = 100 } 'D:\MTP' $null
Comprobar ($r -eq 'D:\MTP-obra') "con MSYS2 (hacen falta 4 GB): C: con 3 GB no basta ($r)"
$Metodo = 'ligero'

Write-Host ''
if ($fallos -gt 0) { Write-Host "Pruebas de la carpeta de compilación: $fallos fallo(s)."; exit 1 }
Write-Host 'Pruebas de la carpeta de compilación: todo correcto.'
