<#
  Publica una Edge Function con la Management API.

    .\supabase\scripts\desplegar_funcion.ps1 pagar-pedido

  Se usa la API y no el CLI de Supabase porque el CLI pide Docker y aca no
  hace falta: la funcion es un solo archivo.

  Las dos funciones se publican con verify_jwt = false a proposito: la
  identidad se verifica adentro (asi andan las claves nuevas `sb_publishable_`
  y las viejas `anon`), y `renovar_plus` entra con la clave de servicio.
#>
param(
  [Parameter(Mandatory = $true)][string]$Nombre
)
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$ref = 'wqahdncdqnzrusrmdyui'
$pat = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
if (-not $pat) { throw 'Falta la variable de entorno SUPABASE_TOKEN_MODO_YA' }

$archivo = Join-Path $repo "supabase\functions\$Nombre\index.ts"
if (-not (Test-Path $archivo)) { throw "No existe $archivo" }

# El metadata va en un archivo: pasado en linea, las comillas del JSON se
# pierden entre PowerShell y curl.
$meta = Join-Path $env:TEMP "modoya-deploy-$Nombre.json"
@{
  entrypoint_path = 'index.ts'
  name            = $Nombre
  verify_jwt      = $false
} | ConvertTo-Json -Compress | ForEach-Object { [IO.File]::WriteAllText($meta, $_) }  # sin BOM

try {
  $salida = & curl.exe -sS -X POST `
    "https://api.supabase.com/v1/projects/$ref/functions/deploy?slug=$Nombre" `
    -H "Authorization: Bearer $pat" `
    -F "metadata=<$meta;type=application/json" `
    -F "file=@$archivo;type=application/typescript;filename=index.ts"
} finally {
  Remove-Item $meta -ErrorAction SilentlyContinue
}

if ($LASTEXITCODE -ne 0) { throw "curl fallo ($LASTEXITCODE)" }

$r = $salida | ConvertFrom-Json
if ($r.message) { throw "Supabase: $($r.message)" }
Write-Host "publicada $($r.slug) version $($r.version) ($($r.status))"
