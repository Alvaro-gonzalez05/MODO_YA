<#
.SYNOPSIS
  Arma el icono cuadrado de una app (fondo negro + logo centrado) a partir
  del logo con fondo transparente de packages/my_ui/assets/branding.

.DESCRIPTION
  Genera un PNG de 1024x1024 con fondo negro y el logo escalado al
  porcentaje indicado, centrado. Es la imagen base que flutter_launcher_icons
  reparte a Android, web y Windows (ver tools/iconos.md).

.EXAMPLE
  .\tools\icono_app.ps1 packages\my_ui\assets\branding\logo_modo_ya.png apps\modo_ya\assets\icono.png
#>
param(
  [Parameter(Mandatory = $true)][string]$Logo,
  [Parameter(Mandatory = $true)][string]$Salida,
  [int]$Tamano = 1024,
  [double]$Escala = 0.82
)

Add-Type -AssemblyName System.Drawing

$origen = [System.Drawing.Image]::FromFile((Resolve-Path $Logo))
$lienzo = New-Object System.Drawing.Bitmap $Tamano, $Tamano
$g = [System.Drawing.Graphics]::FromImage($lienzo)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$g.Clear([System.Drawing.Color]::Black)

# El logo entra completo en un cuadrado de $Escala * $Tamano, sin deformarlo.
$lado = $Tamano * $Escala
$factor = [Math]::Min($lado / $origen.Width, $lado / $origen.Height)
$w = [int]($origen.Width * $factor)
$h = [int]($origen.Height * $factor)
$x = [int](($Tamano - $w) / 2)
$y = [int](($Tamano - $h) / 2)
$g.DrawImage($origen, $x, $y, $w, $h)

$dir = Split-Path -Parent $Salida
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$lienzo.Save($Salida, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $lienzo.Dispose(); $origen.Dispose()
Write-Output "OK $Salida ($Tamano px, logo al $([int]($Escala * 100))%)"
