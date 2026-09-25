<#
  Deja en Vault lo que la base necesita para llamarse a si misma:

    url_funciones      https://<ref>.supabase.co/functions/v1
    clave_de_servicio  la service role key del proyecto

  Lo usa el cron "renovar-plus" (migracion 0041): pg_net le pega a la Edge
  Function `pagar-pedido` con esa clave. Asi el secreto no vive en el codigo,
  ni en las migraciones, ni pasa por ningun chat.

  La clave se lee sola de la Management API con SUPABASE_TOKEN_MODO_YA: no hay
  que copiarla ni pegarla a mano.

  Uso:
    .\supabase\scripts\guardar_secretos.ps1
#>
$ErrorActionPreference = 'Stop'

$ref = 'wqahdncdqnzrusrmdyui'
$pat = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
if (-not $pat) { throw 'Falta la variable de entorno SUPABASE_TOKEN_MODO_YA' }
$mh = @{ Authorization = "Bearer $pat" }

$keys = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/api-keys?reveal=true" -Headers $mh
$sec = ($keys | Where-Object { $_.type -eq 'secret' } | Select-Object -First 1).api_key
if (-not $sec) { throw 'No se pudo leer la clave de servicio del proyecto' }

function Sql([string]$q) {
  $b = @{ query = $q } | ConvertTo-Json
  Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/database/query" -Method Post -Headers $mh `
    -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($b))
}

# Las comillas simples se duplican: el valor entra como literal SQL.
function Guardar([string]$nombre, [string]$valor, [string]$descripcion) {
  $v = $valor.Replace("'", "''")
  Sql @"
do `$`$
declare s uuid;
begin
  select id into s from vault.secrets where name = '$nombre';
  if s is null then
    perform vault.create_secret('$v', '$nombre', '$descripcion');
  else
    perform vault.update_secret(s, '$v');
  end if;
end
`$`$;
"@ | Out-Null
  Write-Host "guardado: $nombre"
}

Guardar 'url_funciones' "https://$ref.supabase.co/functions/v1" 'Base de las Edge Functions, para que la base se llame a si misma'
Guardar 'clave_de_servicio' $sec 'Service role key: la usa el cron renovar-plus con pg_net'

$r = Sql "select name, description from vault.secrets order by name"
$r | Format-Table
