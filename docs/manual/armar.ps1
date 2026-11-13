# Rehace el PDF del manual a partir del HTML.
#
#   powershell -NoProfile -Command "& './docs/manual/armar.ps1'"
#
# Se imprime con Chrome headless porque es el mismo motor que dibuja el HTML:
# lo que se ve en el navegador es exactamente lo que sale en el PDF. Las
# tipografias estan en docs/manual/fuentes (no se bajan de internet), asi que
# el PDF sale igual aunque la maquina no tenga salida.

$ErrorActionPreference = 'Stop'

$carpeta = Split-Path -Parent $MyInvocation.MyCommand.Path
$html = Join-Path $carpeta 'modo-ya-como-funciona.html'
$pdf = Join-Path $carpeta 'MODO-YA-Como-funciona.pdf'

$chrome = $env:CHROME
if (-not $chrome) { $chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe' }
if (-not (Test-Path $chrome)) { throw "No encontre Chrome en $chrome. Pone la ruta en la variable CHROME." }

$uri = ([uri](Resolve-Path $html).Path).AbsoluteUri

& $chrome --headless=new --disable-gpu --no-sandbox --no-pdf-header-footer `
  --virtual-time-budget=15000 "--print-to-pdf=$pdf" $uri 2>$null

if (-not (Test-Path $pdf)) { throw 'Chrome no escribio el PDF.' }
Write-Output "Listo: $pdf"
