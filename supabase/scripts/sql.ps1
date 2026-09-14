<#
.SYNOPSIS
  Corre un archivo .sql contra el proyecto de Supabase de MODO YA.

.DESCRIPTION
  Usa la Management API con el Personal Access Token guardado en la variable de
  entorno de usuario SUPABASE_TOKEN_MODO_YA (la misma que usa .mcp.json).
  El token nunca se imprime.

  Corre como `postgres`, que es dueno de las tablas y SALTEA RLS. Para probar
  politicas hay que usar `set local role authenticated` dentro del script
  (ver supabase/README.md, seccion Pruebas de regresion).

.EXAMPLE
  .\supabase\scripts\sql.ps1 supabase\tests\flujo_completo.sql
#>
param(
  [Parameter(Mandatory = $true)][string]$Archivo,
  [string]$Proyecto = 'wqahdncdqnzrusrmdyui'
)

$token = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
if (-not $token) { $token = $env:SUPABASE_TOKEN_MODO_YA }
if (-not $token) {
  Write-Error 'Falta la variable de entorno SUPABASE_TOKEN_MODO_YA.'
  exit 1
}

$ruta = Resolve-Path $Archivo
# ReadAllText y no Get-Content: Get-Content le cuelga propiedades al string que
# hacen que ConvertTo-Json de PowerShell 5.1 lo serialice como objeto.
$sql = [System.IO.File]::ReadAllText($ruta, [System.Text.Encoding]::UTF8)
$cuerpo = @{ query = $sql } | ConvertTo-Json -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($cuerpo)

try {
  $filas = Invoke-RestMethod `
    -Uri "https://api.supabase.com/v1/projects/$Proyecto/database/query" `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Method Post -Body $bytes -ErrorAction Stop
  if ($filas) { $filas | Format-Table -AutoSize -Wrap | Out-String -Width 220 }
  else { 'OK (sin filas)' }
} catch {
  $msg = $_.ErrorDetails.Message
  if (-not $msg) { $msg = $_.Exception.Message }
  Write-Output "ERROR: $msg"
  exit 1
}
