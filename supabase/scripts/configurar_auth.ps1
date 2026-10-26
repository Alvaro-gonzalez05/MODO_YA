<#
  Deja la autenticacion de Supabase como la necesita MODO YA en produccion.

    .\supabase\scripts\configurar_auth.ps1
        Asuntos y plantillas de los mails en castellano (supabase/correo/),
        contrasenas de al menos 8 caracteres y rechazo de las filtradas.

    .\supabase\scripts\configurar_auth.ps1 -Sitio https://modoya.com.ar
        Ademas, la direccion de la web: los links de los mails apuntan a
        <sitio>/confirmar y <sitio>/nueva-clave. Hoy esta en localhost:3000.

    .\supabase\scripts\configurar_auth.ps1 -ExigirConfirmacion
        Ademas, exige confirmar el email al registrarse. Se niega si no hay un
        SMTP propio cargado: con el correo de Supabase salen dos mails por hora
        y solo a los miembros del proyecto, asi que nadie mas podria
        registrarse.

  El SMTP no se carga aca: lo hace la integracion de Resend con Supabase (ver
  docs/salir-a-produccion.md), sin que la clave pase por ningun archivo.
#>
param(
  [string]$Sitio,
  [switch]$ExigirConfirmacion,
  [int]$MailsPorHora = 30
)
$ErrorActionPreference = 'Stop'

$ref = 'wqahdncdqnzrusrmdyui'
$pat = [Environment]::GetEnvironmentVariable('SUPABASE_TOKEN_MODO_YA', 'User')
if (-not $pat) { throw 'Falta la variable de entorno SUPABASE_TOKEN_MODO_YA' }
$h = @{ Authorization = "Bearer $pat" }
$api = "https://api.supabase.com/v1/projects/$ref/config/auth"
$correo = Join-Path $PSScriptRoot '..\correo'

function Plantilla([string]$archivo) {
  [IO.File]::ReadAllText((Join-Path $correo $archivo), [Text.Encoding]::UTF8)
}

function Mandar($cambios) {
  $json = $cambios | ConvertTo-Json -Compress
  Invoke-RestMethod -Uri $api -Method Patch -Headers $h -ContentType 'application/json' `
    -Body ([Text.Encoding]::UTF8.GetBytes($json)) | Out-Null
}

$actual = Invoke-RestMethod -Uri $api -Headers $h

$smtp = [bool]$actual.smtp_host

# La app ya le dice al usuario "al menos 8": la base pedia 6.
$cambios = [ordered]@{ password_min_length = 8 }
if ($Sitio) { $cambios.site_url = $Sitio.TrimEnd('/') }
Mandar $cambios
'Contrasenas de al menos 8 caracteres: listo.'
if ($Sitio) { "Sitio: $($cambios.site_url)" }

# En el plan gratis, Supabase no deja tocar las plantillas mientras se use su
# correo por defecto: recien con un SMTP propio.
if ($smtp) {
  Mandar ([ordered]@{
    mailer_subjects_confirmation          = 'Confirmá tu cuenta de MODO YA'
    mailer_templates_confirmation_content = Plantilla 'confirmar.html'
    mailer_subjects_recovery              = 'Elegí una contraseña nueva para MODO YA'
    mailer_templates_recovery_content     = Plantilla 'recuperar.html'
    mailer_subjects_email_change          = 'Confirmá tu nuevo email en MODO YA'
    mailer_templates_email_change_content = Plantilla 'cambio_de_email.html'
  })
  'Plantillas y asuntos en castellano: listos.'
} else {
  'Plantillas: todavia no. Supabase las deja cambiar recien con un SMTP propio; corre este script de nuevo despues de conectar Resend.'
}

if ($ExigirConfirmacion) {
  if (-not $smtp) {
    throw 'No hay SMTP propio cargado. Conecta Resend primero (docs/salir-a-produccion.md).'
  }
  Mandar ([ordered]@{ mailer_autoconfirm = $false; rate_limit_email_sent = $MailsPorHora })
  "Confirmacion de email: exigida ($MailsPorHora mails por hora)."
}

# Aparte: rechazar contrasenas filtradas (HaveIBeenPwned) solo esta en los
# planes pagos de Supabase. Si el plan no lo incluye, la API lo rechaza y el
# resto ya quedo guardado.
try {
  Mandar @{ password_hibp_enabled = $true }
  'Contrasenas filtradas: se rechazan.'
} catch {
  'Contrasenas filtradas: el plan actual de Supabase no lo permite (hace falta el plan Pro).'
}
