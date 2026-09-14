<#
  Prueba de extremo a extremo del alta de cuentas, contra la API REAL de Auth,
  PostgREST y Edge Functions (no SQL directo).

  Existe porque hay comportamientos que un test SQL no puede ver: por ejemplo,
  GoTrue inserta el usuario y recien despues escribe el app_metadata en un
  UPDATE (ver migracion 0018).

  Crea usuarios temporales *@modoya.test y los borra al final, pase lo que pase.
  No manda emails. Las claves se leen de la Management API y quedan solo en
  memoria.

  Uso:  .\supabase\tests\cuentas.ps1
#>
$ErrorActionPreference = 'Stop'
$ref  = 'wqahdncdqnzrusrmdyui'
$url  = "https://$ref.supabase.co"
$pat  = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
$mgmt = @{ Authorization = "Bearer $pat" }

$keys = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/api-keys?reveal=true" -Headers $mgmt
$pub  = ($keys | Where-Object { $_.type -eq 'publishable' } | Select-Object -First 1).api_key
$sec  = ($keys | Where-Object { $_.type -eq 'secret' } | Select-Object -First 1).api_key
if (-not $pub -or -not $sec) { throw 'No se pudieron leer las claves del proyecto' }

function Api($metodo, $ruta, $cuerpo, $headers) {
  # User-Agent propio: el gateway rechaza la clave secreta si el pedido parece
  # venir de un navegador, y el de PowerShell 5.1 dice "Mozilla".
  $p = @{
    Uri = "$url$ruta"; Method = $metodo; Headers = $headers
    ContentType = 'application/json'; UserAgent = 'modoya-test-script/1.0'
  }
  if ($cuerpo) {
    $p.Body = [System.Text.Encoding]::UTF8.GetBytes(($cuerpo | ConvertTo-Json -Compress -Depth 5))
  }
  try {
    $r = Invoke-WebRequest @p -UseBasicParsing
    $b = if ($r.Content) { $r.Content | ConvertFrom-Json } else { $null }
    return @{ status = [int]$r.StatusCode; body = $b }
  } catch {
    $resp = $_.Exception.Response
    $status = if ($resp) { [int]$resp.StatusCode } else { 0 }
    $txt = $_.ErrorDetails.Message
    if (-not $txt -and $resp) {
      try { $txt = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() } catch {}
    }
    $b = try { $txt | ConvertFrom-Json } catch { $txt }
    return @{ status = $status; body = $b }
  }
}

function Con($jwt) { @{ apikey = $pub; Authorization = "Bearer $jwt" } }

$hAdminApi = @{ apikey = $sec; Authorization = "Bearer $sec" }
$hPub      = @{ apikey = $pub }
$stamp     = Get-Date -Format 'HHmmss'
$creados   = New-Object System.Collections.ArrayList

function Veredicto($ok) { if ($ok) { 'OK' } else { 'FALLA' } }

try {
  # ---- 1-3. Administracion --------------------------------------------------
  $adminMail = "test-admin-$stamp@modoya.test"
  $adminPass = "Adm-$([guid]::NewGuid().ToString('N').Substring(0,12))"
  $r = Api POST '/auth/v1/admin/users' @{
    email = $adminMail; password = $adminPass; email_confirm = $true
    app_metadata = @{ rol = 'admin' }; user_metadata = @{ nombre = 'Admin Test' }
  } $hAdminApi
  if ($r.status -ge 300) { throw "no se pudo crear el admin: $($r.body | ConvertTo-Json -Compress)" }
  [void]$creados.Add($r.body.id)

  $r = Api POST '/auth/v1/token?grant_type=password' @{ email = $adminMail; password = $adminPass } $hPub
  $jwtAdmin = $r.body.access_token
  $s = Api POST '/rest/v1/rpc/mi_sesion' @{} (Con $jwtAdmin)
  "01 admin creado por Auth queda admin     -> rol=$($s.body.rol) $(Veredicto ($s.body.rol -eq 'admin'))"

  # ---- 4-7. Alta de un local ------------------------------------------------
  $localMail = "test-local-$stamp@modoya.test"
  $rubro = (Api GET '/rest/v1/rubros?select=id&nombre=eq.Pizzer%C3%ADa' $null (Con $jwtAdmin)).body[0].id
  $r = Api POST '/functions/v1/admin-crear-usuario' @{
    rol = 'comercio'; email = $localMail; nombre = 'Pizzeria Test'; telefono = '+54 260 400-0000'
    rubro_id = $rubro; calle = 'Av. Roca 420'; referencia = 'Frente a la plaza'
    lat = -35.4761; lng = -69.5839
  } (Con $jwtAdmin)
  if ($r.body.usuario_id) { [void]$creados.Add($r.body.usuario_id) }
  $okAlta = ($r.status -eq 201) -and $r.body.comercio_id -and $r.body.password_temporal
  "02 admin da de alta un local             -> HTTP $($r.status) $(Veredicto $okAlta)"
  if (-not $okAlta) { "   $($r.body | ConvertTo-Json -Compress)" }
  $localPass = $r.body.password_temporal

  $r = Api POST '/auth/v1/token?grant_type=password' @{ email = $localMail; password = $localPass } $hPub
  $jwtLocal = $r.body.access_token
  "03 local entra con la clave temporal     -> HTTP $($r.status) $(Veredicto ($r.status -eq 200))"

  $s = Api POST '/rest/v1/rpc/mi_sesion' @{} (Con $jwtLocal)
  $okSes = ($s.body.rol -eq 'comercio') -and ($s.body.estado_aprobacion -eq 'aprobado') -and $s.body.comercio_id -and (-not $s.body.cliente_id)
  "04 sesion del local                      -> rol=$($s.body.rol) aprobado=$($s.body.estado_aprobacion) sin_ficha_cliente=$(-not $s.body.cliente_id) $(Veredicto $okSes)"

  $r = Api GET "/rest/v1/v_comercios?select=nombre,lat,rubro_nombre&id=eq.$($s.body.comercio_id)" $null (Con $jwtLocal)
  $v = $r.body | Select-Object -First 1
  "05 vidriera con lat/lng numericos        -> $($v.nombre) lat=$($v.lat) $(Veredicto ($v.lat -eq -35.4761))"

  # ---- 6. Alta de un rider --------------------------------------------------
  $riderMail = "test-rider-$stamp@modoya.test"
  $r = Api POST '/functions/v1/admin-crear-usuario' @{
    rol = 'repartidor'; email = $riderMail; nombre = 'Rider Test'; telefono = '+54 260 500-0000'; vehiculo = 'moto'
  } (Con $jwtAdmin)
  if ($r.body.usuario_id) { [void]$creados.Add($r.body.usuario_id) }
  "06 admin da de alta un rider             -> HTTP $($r.status) $(Veredicto (($r.status -eq 201) -and $r.body.repartidor_id))"

  # ---- 7-9. Negativos -------------------------------------------------------
  $r = Api POST '/functions/v1/admin-crear-usuario' @{
    rol = 'repartidor'; email = "pillo-$stamp@modoya.test"; nombre = 'Pillo'; telefono = '1'; vehiculo = 'moto'
  } (Con $jwtLocal)
  "07 NO un local crea cuentas              -> HTTP $($r.status) $(Veredicto ($r.status -eq 403))"
  if ($r.body.usuario_id) { [void]$creados.Add($r.body.usuario_id) }

  $r = Api POST '/functions/v1/admin-crear-usuario' @{ rol = 'comercio' } $hPub
  "08 NO sin sesion                         -> HTTP $($r.status) $(Veredicto ($r.status -eq 401))"

  $r = Api POST '/functions/v1/admin-crear-usuario' @{
    rol = 'comercio'; email = $localMail; nombre = 'Dup'; telefono = '1'; calle = 'x'; lat = -35.47; lng = -69.58
  } (Con $jwtAdmin)
  "09 email repetido                        -> HTTP $($r.status) $($r.body.error.codigo) $(Veredicto ($r.status -eq 409))"

  # ---- 10. Registro que intenta colarse como admin --------------------------
  # No usa /auth/v1/signup: con confirmacion de email activa manda un mail, y el
  # SMTP de Supabase permite 2 por hora y solo entrega al equipo del proyecto.
  # Se crea el usuario igual que lo dejaria un signup (rol en user_metadata, que
  # es lo que controla el usuario, y nada en app_metadata).
  $cliMail = "test-cliente-$stamp@modoya.test"
  $cliPass = "Cli-$([guid]::NewGuid().ToString('N').Substring(0,12))"
  $r = Api POST '/auth/v1/admin/users' @{
    email = $cliMail; password = $cliPass; email_confirm = $true
    user_metadata = @{ nombre = 'Cliente Test'; rol = 'admin' }
  } $hAdminApi
  if ($r.body.id) { [void]$creados.Add($r.body.id) }
  $r = Api POST '/auth/v1/token?grant_type=password' @{ email = $cliMail; password = $cliPass } $hPub
  $s = Api POST '/rest/v1/rpc/mi_sesion' @{} (Con $r.body.access_token)
  "10 NO registro con rol=admin en metadata -> rol=$($s.body.rol) ficha_cliente=$([bool]$s.body.cliente_id) $(Veredicto (($s.body.rol -eq 'cliente') -and $s.body.cliente_id))"

  # ---- 12-16. Usuario generado y contrasena restablecida --------------------
  # Sin email: el servidor arma nombre@modoya.com. Los nombres llevan el sello
  # para no chocar con cuentas reales, y se borran en el finally.
  $r = Api POST '/functions/v1/admin-crear-usuario' @{
    rol = 'comercio'; nombre = "ZZ Prueba Local $stamp"; telefono = '1'; calle = 'Av. Roca 1'
    lat = -35.4761; lng = -69.5839
  } (Con $jwtAdmin)
  if ($r.body.usuario_id) { [void]$creados.Add($r.body.usuario_id) }
  $genLocal = $r.body.email
  $genLocalId = $r.body.comercio_id
  "12 alta sin email genera el usuario      -> $genLocal $(Veredicto ($genLocal -eq "zz.prueba.local.$stamp@modoya.com"))"

  $r = Api POST '/functions/v1/admin-crear-usuario' @{
    rol = 'comercio'; nombre = "ZZ Prueba Local $stamp"; telefono = '1'; calle = 'Av. Roca 2'
    lat = -35.4761; lng = -69.5839
  } (Con $jwtAdmin)
  if ($r.body.usuario_id) { [void]$creados.Add($r.body.usuario_id) }
  "13 mismo nombre suma un numero           -> $($r.body.email) $(Veredicto ($r.body.email -eq "zz.prueba.local.$stamp.2@modoya.com"))"

  $r = Api POST '/functions/v1/admin-crear-usuario' @{
    rol = 'repartidor'; nombre = "ZZ Prueba Rider $stamp"; telefono = '1'; vehiculo = 'moto'
  } (Con $jwtAdmin)
  if ($r.body.usuario_id) { [void]$creados.Add($r.body.usuario_id) }
  $genRider = $r.body.email
  $t = Api POST '/auth/v1/token?grant_type=password' @{ email = $genRider; password = $r.body.password_temporal } $hPub
  "14 rider generado entra con su clave     -> $genRider HTTP $($t.status) $(Veredicto (($genRider -eq "rider.zz.prueba.rider.$stamp@modoya.com") -and $t.status -eq 200))"

  $r = Api POST '/functions/v1/admin-crear-usuario' @{ accion = 'restablecer_password'; comercio_id = $genLocalId } (Con $jwtAdmin)
  $nueva = $r.body.password_temporal
  $t = Api POST '/auth/v1/token?grant_type=password' @{ email = $genLocal; password = $nueva } $hPub
  "15 restablecer contrasena de un local    -> HTTP $($r.status) entra=$($t.status) $(Veredicto (($r.status -eq 200) -and ($r.body.email -eq $genLocal) -and $t.status -eq 200))"

  $r = Api POST '/functions/v1/admin-crear-usuario' @{ accion = 'restablecer_password'; comercio_id = $genLocalId } (Con $jwtLocal)
  "16 NO un local restablece contrasenas    -> HTTP $($r.status) $(Veredicto ($r.status -eq 403))"

  $u = Api POST '/rest/v1/rpc/admin_usuario_de' @{ p_comercio = $genLocalId } (Con $jwtAdmin)
  $n = Api POST '/rest/v1/rpc/admin_usuario_de' @{ p_comercio = $genLocalId } (Con $jwtLocal)
  "17 admin ve el usuario; el local no      -> admin=$($u.body) local=HTTP $($n.status) $(Veredicto (($u.body -eq $genLocal) -and $n.status -ge 400))"

  # ---- 11. Configuracion de registro (informativo) --------------------------
  $cfg = Invoke-RestMethod -Uri "https://api.supabase.com/v1/projects/$ref/config/auth" -Headers $mgmt
  $puede = (-not $cfg.disable_signup) -and ($cfg.mailer_autoconfirm -or $cfg.smtp_host)
  $estado = if ($puede) { 'habilitado' } else { 'BLOQUEADO: pide confirmar email y no hay SMTP propio' }
  "11 registro de clientes desde la app     -> $estado"
}
finally {
  foreach ($id in $creados) { $null = Api DELETE "/auth/v1/admin/users/$id" $null $hAdminApi }
  "limpieza: $($creados.Count) usuarios de prueba borrados"
}
