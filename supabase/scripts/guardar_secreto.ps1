<#
  Carga (o reemplaza) un secreto de las Edge Functions sin que el valor quede
  en ningun lado: lo pide por teclado tapado, lo manda por la Management API y
  no lo escribe en disco ni en el historial de la consola.

    .\supabase\scripts\guardar_secreto.ps1 MP_ACCESS_TOKEN
    .\supabase\scripts\guardar_secreto.ps1 MP_WEBHOOK_SECRET

  Si el secreto tiene varias lineas (la clave de servicio de Firebase es un
  JSON entero), no se puede pegar: Read-Host corta en el primer Enter. Para eso
  se lee del archivo, sin mostrarlo. Conviene borrar el archivo despues:

    .\supabase\scripts\guardar_secreto.ps1 FCM_SERVICE_ACCOUNT -DesdeArchivo "$env:USERPROFILE\Downloads\modo-ya-firebase-adminsdk.json"

  Con -Listar muestra que secretos hay cargados (solo los nombres):

    .\supabase\scripts\guardar_secreto.ps1 -Listar

  Con -Borrar lo saca:

    .\supabase\scripts\guardar_secreto.ps1 MP_ACCESS_TOKEN -Borrar

  Los secretos los lee la Edge Function con Deno.env.get() en cada invocacion:
  no hace falta volver a publicarla.
#>
param(
  [Parameter(Position = 0)][string]$Nombre,
  [string]$DesdeArchivo,
  [switch]$Listar,
  [switch]$Borrar
)
$ErrorActionPreference = 'Stop'

$ref = 'wqahdncdqnzrusrmdyui'
$pat = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
if (-not $pat) { throw 'Falta la variable de entorno SUPABASE_TOKEN_MODO_YA' }
$h = @{ Authorization = "Bearer $pat" }
$api = "https://api.supabase.com/v1/projects/$ref/secrets"

if ($Listar) {
  Write-Host 'Secretos cargados en las Edge Functions:'
  (Invoke-RestMethod -Uri $api -Headers $h) |
    Where-Object { $_.name -notlike 'SUPABASE_*' } |
    ForEach-Object { Write-Host "  $($_.name)" }
  Write-Host '(los SUPABASE_* los pone Supabase solo)'
  return
}

if (-not $Nombre) { throw 'Decime el nombre del secreto (ej: MP_ACCESS_TOKEN)' }

if ($Borrar) {
  Invoke-RestMethod -Uri $api -Method Delete -Headers $h `
    -ContentType 'application/json' -Body (ConvertTo-Json @($Nombre)) | Out-Null
  Write-Host "borrado: $Nombre"
  return
}

if ($DesdeArchivo) {
  # Un secreto de varias lineas (la clave de servicio de Firebase es un JSON
  # entero) no se puede pegar en el prompt: Read-Host corta en el primer Enter.
  # Se lee del archivo tal cual, sin mostrarlo.
  if (-not (Test-Path $DesdeArchivo)) { throw "No encuentro el archivo: $DesdeArchivo" }
  $valor = [System.IO.File]::ReadAllText((Resolve-Path $DesdeArchivo), [System.Text.Encoding]::UTF8)
} else {
  # -AsSecureString: no se ve al tipear y no queda en el historial de PowerShell.
  $seguro = Read-Host "Pegá el valor de $Nombre (si tiene varias líneas, usá -DesdeArchivo)" -AsSecureString
  $valor = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seguro))
}

if ([string]::IsNullOrWhiteSpace($valor)) { throw 'No pegaste nada' }
$valor = $valor.Trim()

# Aviso util: las credenciales de prueba y las de produccion no se mezclan.
if ($Nombre -eq 'MP_ACCESS_TOKEN') {
  if ($valor.StartsWith('TEST-')) { Write-Host 'Ojo: es un access token de PRUEBA.' -ForegroundColor Yellow }
  elseif ($valor.StartsWith('APP_USR-')) { Write-Host 'Es un access token de PRODUCCION: se cobra de verdad.' -ForegroundColor Yellow }
  else { Write-Host 'No parece un access token de Mercado Pago (no empieza con TEST- ni APP_USR-).' -ForegroundColor Red }
}

$largo = $valor.Length

Invoke-RestMethod -Uri $api -Method Post -Headers $h -ContentType 'application/json' `
  -Body (ConvertTo-Json @(@{ name = $Nombre; value = $valor })) | Out-Null

$valor = $null
[GC]::Collect()

Write-Host "guardado: $Nombre (largo $largo caracteres)"
Write-Host 'Las Edge Functions lo toman en la proxima llamada. No hace falta republicar.'
