<#
  Prepara (o limpia) las cuentas para el test de integracion de la app
  (packages/my_core/test/integracion_test.dart).

  Crea una cuenta de administracion y una de cliente *@modoya.test con
  contrasenas al azar, y escribe env/test.json (ignorado por git) con eso mas
  la configuracion de env/dev.json. El local y el rider los crea el propio test
  a traves de la Edge Function, igual que lo haria la administracion desde la app.

  Uso:
    .\supabase\tests\preparar_prueba_app.ps1            # prepara
    cd packages\my_core
    flutter test test\integracion_test.dart --dart-define-from-file=..\..\env\test.json
    cd ..\..
    .\supabase\tests\preparar_prueba_app.ps1 -Limpiar   # borra todo lo de prueba
#>
param([switch]$Limpiar)
$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$ref  = 'wqahdncdqnzrusrmdyui'
$url  = "https://$ref.supabase.co"
$pat  = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
if (-not $pat) { throw 'Falta la variable de entorno SUPABASE_TOKEN_MODO_YA' }

# La clave secreta se lee de la Management API y queda solo en memoria.
$keys = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/api-keys?reveal=true" -Headers @{ Authorization = "Bearer $pat" }
$sec  = ($keys | Where-Object { $_.type -eq 'secret' } | Select-Object -First 1).api_key
$h    = @{ apikey = $sec; Authorization = "Bearer $sec" }
# El gateway rechaza la clave secreta si el User-Agent parece de navegador.
$ua   = 'modoya-test-script/1.0'

function BorrarUsuariosDePrueba {
  $n = 0
  $pagina = 1
  do {
    $r = Invoke-RestMethod -Uri "$url/auth/v1/admin/users?page=$pagina&per_page=200" -Headers $h -UserAgent $ua
    $deEstaPagina = @($r.users | Where-Object { $_.email -like '*@modoya.test' })
    foreach ($u in $deEstaPagina) {
      Invoke-RestMethod -Uri "$url/auth/v1/admin/users/$($u.id)" -Method Delete -Headers $h -UserAgent $ua | Out-Null
      $n++
    }
    $pagina++
  } while ($r.users.Count -eq 200)
  return $n
}

# Siempre se limpia primero: una corrida anterior que fallo pudo dejar restos.
$limpieza = & (Join-Path $PSScriptRoot '..\scripts\sql.ps1') (Join-Path $PSScriptRoot 'limpiar_prueba_app.sql')
if ("$limpieza" -match 'ERROR:') { throw "Fallo la limpieza de datos de prueba: $limpieza" }
$borrados = BorrarUsuariosDePrueba
"limpieza: $borrados usuarios de prueba borrados"
if ($Limpiar) { return }

$cuentas = [ordered]@{}
foreach ($c in @(
    @{ clave = 'ADMIN'; email = 'admin@modoya.test'; nombre = 'Admin Prueba'; app = @{ rol = 'admin' } },
    @{ clave = 'CLIENTE'; email = 'cliente@modoya.test'; nombre = 'Cliente Prueba'; app = @{} }
  )) {
  $pass = "Prueba-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
  $cuerpo = @{
    email = $c.email; password = $pass; email_confirm = $true
    app_metadata = $c.app; user_metadata = @{ nombre = $c.nombre; telefono = '2604000000' }
  } | ConvertTo-Json -Depth 5
  Invoke-RestMethod -Uri "$url/auth/v1/admin/users" -Method Post -Headers $h -UserAgent $ua `
    -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($cuerpo)) | Out-Null
  $cuentas["MY_TEST_$($c.clave)_EMAIL"] = $c.email
  $cuentas["MY_TEST_$($c.clave)_PASSWORD"] = $pass
  "creada $($c.email)"
}

$dev = Get-Content (Join-Path $repo 'env\dev.json') -Raw | ConvertFrom-Json
$test = [ordered]@{
  MY_FLAVOR       = 'dev'
  MY_SUPABASE_URL = $dev.MY_SUPABASE_URL
  MY_SUPABASE_KEY = $dev.MY_SUPABASE_KEY
}
foreach ($k in $cuentas.Keys) { $test[$k] = $cuentas[$k] }
[System.IO.File]::WriteAllText((Join-Path $repo 'env\test.json'), ($test | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
'env\test.json escrito'
