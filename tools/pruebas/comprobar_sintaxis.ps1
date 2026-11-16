# Comprueba que todos los scripts de PowerShell del proyecto se pueden analizar (sintaxis),
# sin ejecutarlos. Uso: pwsh tools/pruebas/comprobar_sintaxis.ps1
$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fallos = 0
$archivos = Get-ChildItem -LiteralPath $raiz -Recurse -Filter *.ps1 -File |
    Where-Object { $_.FullName -notmatch '[\\/](externo|juego|build|herramientas)[\\/]' } |
    Sort-Object FullName
foreach ($archivo in $archivos) {
    $errores = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($archivo.FullName, [ref]$null, [ref]$errores)
    $relativo = $archivo.FullName.Substring($raiz.Length).TrimStart('\', '/')
    if ($errores -and $errores.Count -gt 0) {
        $fallos++
        Write-Host "ERROR  $relativo"
        foreach ($e in $errores) { Write-Host ("       línea {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) }
    } else {
        Write-Host "ok     $relativo"
    }
    # Windows PowerShell 5.1 lee como ANSI los .ps1 sin BOM y rompe los acentos.
    $inicio = [System.IO.File]::ReadAllBytes($archivo.FullName)
    if ($inicio.Length -lt 3 -or $inicio[0] -ne 0xEF -or $inicio[1] -ne 0xBB -or $inicio[2] -ne 0xBF) {
        $fallos++
        Write-Host "ERROR  $relativo : falta la marca BOM de UTF-8"
    }
}
if ($fallos -gt 0) { Write-Host "Comprobación de sintaxis: $fallos fallo(s)."; exit 1 }
Write-Host 'Comprobación de sintaxis: todo correcto.'
