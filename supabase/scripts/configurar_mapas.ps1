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

  Con -Volver deja el servidor publico de OpenStreetMap (solo para desarrollar:
  no admite uso productivo).
#>
param([switch]$Volver)
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$archivos = @('env\publico.json', 'env\dev.json') |
  ForEach-Object { Join-Path $repo $_ } |
  Where-Object { Test-Path $_ }

if ($Volver) {
  $baldosas = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
  $atribucion = 'OpenStreetMap'
} else {
  # -AsSecureString: no se ve al pegar y no queda en el historial.
  $seguro = Read-Host 'Pega la clave de Geoapify para el MAPA' -AsSecureString
  $clave = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro))
  if ([string]::IsNullOrWhiteSpace($clave)) { throw 'No pegaste nada' }
  $clave = $clave.Trim()
  if ($clave -notmatch '^[0-9a-fA-F]{32}$') {
    Write-Host 'Ojo: no parece una clave de Geoapify (son 32 letras y numeros). Igual la pruebo.' -ForegroundColor Yellow
  }

  # osm-carto es el mismo dibujo que el mapa de OpenStreetMap que se usa hoy:
  # para la gente el cambio no se nota.
  $baldosas = "https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=$clave"
  # El plan gratis exige nombrar a Geoapify y a OpenStreetMap al pie del mapa.
  $atribucion = "Powered by Geoapify | $([char]0xA9) OpenStreetMap"

  # Antes de tocar ningun archivo, una baldosa real: la de la plaza de
  # Malargue en zoom 14. Una clave mal copiada dejaria la app sin mapa.
  $lat = -35.4756; $lng = -69.5847; $z = 14
  $n = [Math]::Pow(2, $z)
  $rad = $lat * [Math]::PI / 180
  $x = [Math]::Floor(($lng + 180) / 360 * $n)
  $y = [Math]::Floor((1 - [Math]::Log([Math]::Tan($rad) + 1 / [Math]::Cos($rad)) / [Math]::PI) / 2 * $n)
  $prueba = $baldosas.Replace('{z}', "$z").Replace('{x}', "$x").Replace('{y}', "$y")
  try {
    $r = Invoke-WebRequest -Uri $prueba -UseBasicParsing -UserAgent 'modoya-configurar-mapas/1.0'
  } catch {
    throw "Geoapify no devolvio la baldosa de prueba ($($_.Exception.Message)). Revisa la clave: no cambie nada."
  }
  if ($r.Headers['Content-Type'] -notlike 'image/*') {
    throw "Geoapify contesto algo que no es una imagen ($($r.Headers['Content-Type'])). No cambie nada."
  }
  Write-Host "La clave anda: baldosa de prueba de $($r.RawContentLength) bytes." -ForegroundColor Green
  $clave = $null
}

foreach ($a in $archivos) {
  # ReadAllText/WriteAllText con UTF-8 sin BOM: Get-Content de PowerShell 5.1
  # lee estos archivos como ANSI y Set-Content les agrega BOM.
  $json = [IO.File]::ReadAllText($a, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $json | Add-Member -NotePropertyName MY_MAPA_BALDOSAS -NotePropertyValue $baldosas -Force
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
