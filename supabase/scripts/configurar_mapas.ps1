<#
  Pasa las baldosas del mapa a Geoapify sin que la clave pase por el chat ni
  quede en el historial de la consola.

    .\supabase\scripts\configurar_mapas.ps1

  Pide la clave de Geoapify del MAPA (la que viaja dentro de la app), prueba
  que devuelva una baldosa de Malargue y recien ahi la escribe en
  env\publico.json (el que compila los instaladores) y en env\dev.json.
  La app la toma al compilar: los instaladores que ya estan en la calle siguen
  con el mapa viejo hasta la proxima version.

  La clave de las RUTAS es otra y va como secreto de Supabase (anda al
  instante, sin sacar version):

    .\supabase\scripts\guardar_secreto.ps1 RUTAS_GEOAPIFY_KEY

  Por que dos claves y no una: la del mapa la puede ver cualquiera que mire la
  app; la de las rutas queda en el servidor. Si alguien abusa de la del mapa,
  se cambia esa sola y las rutas siguen andando.

  Para cambiar el dibujo (los estilos se ven en
  https://apidocs.geoapify.com/docs/maps/map-tiles/), con la clave que ya esta
  cargada, sin volver a pedirla:

    .\supabase\scripts\configurar_mapas.ps1 -Estilo osm-bright-smooth

  -EstiloOscuro elige el del modo oscuro (por defecto dark-matter). -NuevaClave
  pide la clave aunque ya haya una.

  Con -Volver deja el servidor publico de OpenStreetMap (solo para desarrollar:
  no admite uso productivo).
#>
param(
  [string]$Estilo = 'osm-carto',
  [string]$EstiloOscuro = 'dark-matter',
  [switch]$NuevaClave,
  [switch]$Volver
)
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
# @(...): con un solo archivo PowerShell devolveria un texto y [0] seria su
# primera letra.
$archivos = @(@('env\publico.json', 'env\dev.json') |
  ForEach-Object { Join-Path $repo $_ } |
  Where-Object { Test-Path $_ })

function Leer([string]$a) { [IO.File]::ReadAllText($a, [Text.Encoding]::UTF8) | ConvertFrom-Json }

if ($Volver) {
  $baldosas = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
  $oscuro = ''
  $atribucion = 'OpenStreetMap'
} else {
  # La clave que ya esta cargada, si hay: cambiar de estilo no deberia
  # obligar a ir a buscarla de nuevo.
  $clave = $null
  if (-not $NuevaClave -and $archivos.Count -gt 0) {
    $actual = (Leer $archivos[0]).MY_MAPA_BALDOSAS
    if ($actual -match 'maps\.geoapify\.com.*apiKey=([0-9A-Za-z]+)') { $clave = $Matches[1] }
  }
  if (-not $clave) {
    # -AsSecureString: no se ve al pegar y no queda en el historial.
    $seguro = Read-Host 'Pega la clave de Geoapify para el MAPA' -AsSecureString
    $clave = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro))
    if ([string]::IsNullOrWhiteSpace($clave)) { throw 'No pegaste nada' }
    $clave = $clave.Trim()
    if ($clave -notmatch '^[0-9a-fA-F]{32}$') {
      Write-Host 'Ojo: no parece una clave de Geoapify (son 32 letras y numeros). Igual la pruebo.' -ForegroundColor Yellow
    }
  } else {
    Write-Host 'Uso la clave que ya estaba cargada.'
  }

  # {r}: la app pide la baldosa al doble de resolucion (@2x) en las pantallas
  # que la aprovechan. Se ve nitida y cuesta lo mismo.
  $plantilla = 'https://maps.geoapify.com/v1/tile/{0}/{{z}}/{{x}}/{{y}}{{r}}.png?apiKey={1}'
  $baldosas = $plantilla -f $Estilo, $clave
  $oscuro = $plantilla -f $EstiloOscuro, $clave
  # El plan gratis exige nombrar a Geoapify y a OpenStreetMap al pie del mapa,
  # y los estilos que no son osm-carto se dibujan con OpenMapTiles.
  $c = [char]0xA9
  $atribucion = if ($Estilo -eq 'osm-carto') { "Powered by Geoapify | $c OpenStreetMap" }
                else { "Powered by Geoapify | $c OpenMapTiles $c OpenStreetMap" }

  # Antes de tocar ningun archivo, una baldosa real de cada estilo: la de la
  # plaza de Malargue en zoom 14. Una clave o un estilo mal escritos dejarian
  # la app sin mapa.
  $lat = -35.4756; $lng = -69.5847; $z = 14
  $n = [Math]::Pow(2, $z)
  $rad = $lat * [Math]::PI / 180
  $x = [Math]::Floor(($lng + 180) / 360 * $n)
  $y = [Math]::Floor((1 - [Math]::Log([Math]::Tan($rad) + 1 / [Math]::Cos($rad)) / [Math]::PI) / 2 * $n)
  foreach ($u in @($baldosas, $oscuro)) {
    $prueba = $u.Replace('{z}', "$z").Replace('{x}', "$x").Replace('{y}', "$y").Replace('{r}', '@2x')
    try {
      $r = Invoke-WebRequest -Uri $prueba -UseBasicParsing -UserAgent 'modoya-configurar-mapas/1.0'
    } catch {
      throw "Geoapify no devolvio la baldosa de prueba ($($_.Exception.Message)). Revisa la clave y el estilo: no cambie nada."
    }
    if ($r.Headers['Content-Type'] -notlike 'image/*') {
      throw "Geoapify contesto algo que no es una imagen ($($r.Headers['Content-Type'])). No cambie nada."
    }
  }
  Write-Host "Anda: $Estilo para el modo claro y $EstiloOscuro para el oscuro." -ForegroundColor Green
  $clave = $null
}

foreach ($a in $archivos) {
  # ReadAllText/WriteAllText con UTF-8 sin BOM: Get-Content de PowerShell 5.1
  # lee estos archivos como ANSI y Set-Content les agrega BOM.
  $json = Leer $a
  $json | Add-Member -NotePropertyName MY_MAPA_BALDOSAS -NotePropertyValue $baldosas -Force
  $json | Add-Member -NotePropertyName MY_MAPA_BALDOSAS_OSCURO -NotePropertyValue $oscuro -Force
  $json | Add-Member -NotePropertyName MY_MAPA_ATRIBUCION -NotePropertyValue $atribucion -Force
  # ConvertTo-Json de PowerShell 5.1 sangra con 4 espacios y deja dos despues
  # de los dos puntos: se lleva al formato del resto del repo.
  $texto = (($json | ConvertTo-Json) -replace '":  ', '": ' -replace '(?m)^    ', '  ') + "`n"
  [IO.File]::WriteAllText($a, $texto, (New-Object Text.UTF8Encoding $false))
  Write-Host "actualizado: $a"
}

Write-Host ''
Write-Host 'Listo. Falta:'
Write-Host '  1. La clave de las rutas: .\supabase\scripts\guardar_secreto.ps1 RUTAS_GEOAPIFY_KEY'
Write-Host '  2. Sacar una version nueva para que los instaladores usen el mapa nuevo.'
