<#
  Deja listas las cuentas de prueba del local y del rider para sacar capturas
  de la app (tools/capturas). Correr despues del test de integracion, que es
  el que crea el local "Pizzeria Test" y su rider.

  Les pone contrasena al azar, le carga un menu de ejemplo al local y agrega
  MY_TEST_LOCAL_* y MY_TEST_RIDER_* a env/test.json. Solo toca cuentas
  *@modoya.test; preparar_prueba_app.ps1 -Limpiar las borra.
#>
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$ref  = 'wqahdncdqnzrusrmdyui'
$url  = "https://$ref.supabase.co"
$pat  = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
$mh   = @{ Authorization = "Bearer $pat" }
$keys = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/api-keys?reveal=true" -Headers $mh
$sec  = ($keys | Where-Object { $_.type -eq 'secret' } | Select-Object -First 1).api_key
$h    = @{ apikey = $sec; Authorization = "Bearer $sec" }
$ua   = 'modoya-test-script/1.0'

function Sql([string]$q) {
  $b = @{ query = $q } | ConvertTo-Json
  Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/database/query" -Method Post -Headers $mh `
    -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($b))
}

$filas = Sql @"
select u.id, u.email, p.rol from auth.users u join public.perfiles p on p.id = u.id
where u.email like '%@modoya.test' and p.rol in ('comercio','repartidor')
order by u.created_at desc
"@
$testJson = Join-Path $repo 'env\test.json'
$test = Get-Content $testJson -Raw | ConvertFrom-Json
$salida = [ordered]@{}
foreach ($p in $test.PSObject.Properties) { $salida[$p.Name] = $p.Value }

foreach ($rol in 'comercio', 'repartidor') {
  $u = $filas | Where-Object { $_.rol -eq $rol } | Select-Object -First 1
  if (-not $u) { throw "No hay cuenta de prueba con rol $rol (correr antes el test de integracion)" }
  $pass = "Prueba-$([guid]::NewGuid().ToString('N').Substring(0, 12))"
  $cuerpo = @{ password = $pass } | ConvertTo-Json
  Invoke-RestMethod -Uri "$url/auth/v1/admin/users/$($u.id)" -Method Put -Headers $h -UserAgent $ua `
    -ContentType 'application/json' -Body $cuerpo | Out-Null
  $clave = if ($rol -eq 'comercio') { 'LOCAL' } else { 'RIDER' }
  $salida["MY_TEST_$($clave)_EMAIL"] = $u.email
  $salida["MY_TEST_$($clave)_PASSWORD"] = $pass
  "lista: $($u.email)"
}

# Menu de ejemplo para el local de prueba
Sql @"
do `$`$
declare v_com uuid; v_sec uuid; v_sec2 uuid;
begin
  select c.id into v_com from comercios c join auth.users u on u.id = c.perfil_id
   where u.email = '$($salida.MY_TEST_LOCAL_EMAIL)';
  delete from productos where comercio_id = v_com;
  delete from secciones_menu where comercio_id = v_com;
  insert into secciones_menu (comercio_id, nombre, orden) values (v_com, 'Pizzas', 1) returning id into v_sec;
  insert into secciones_menu (comercio_id, nombre, orden) values (v_com, 'Empanadas y bebidas', 2) returning id into v_sec2;
  insert into productos (comercio_id, seccion_id, nombre, descripcion, precio, orden) values
    (v_com, v_sec, 'Muzzarella grande', 'Salsa de tomate, muzzarella y aceitunas verdes. 8 porciones.', 9800, 1),
    (v_com, v_sec, 'Napolitana con jamon crudo y rucula', 'Tomate en rodajas, ajo, muzzarella, jamon crudo estacionado y rucula fresca.', 13500, 2),
    (v_com, v_sec, 'Fugazzeta rellena', 'Doble masa, cebolla caramelizada y muzzarella.', 12400, 3),
    (v_com, v_sec2, 'Docena de empanadas de carne cortada a cuchillo', 'Horno de barro.', 15000, 1),
    (v_com, v_sec2, 'Gaseosa 1,5 L', null, 3200, 2);
end `$`$;
"@ | Out-Null
'menu de ejemplo cargado'

[System.IO.File]::WriteAllText($testJson, ($salida | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
'env\test.json actualizado'
