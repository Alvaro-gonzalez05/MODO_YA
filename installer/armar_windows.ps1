<#
  Compila la app MODO YA para Windows y arma el instalador .exe.

  Requisitos: Visual Studio (o Build Tools) con "Desarrollo para el escritorio
  con C++" y el Windows SDK, e Inno Setup 6. El runner windows-latest de
  GitHub ya trae todo (lo usa .github/workflows/release.yml).

  Uso (desde la raiz del repo):
    .\installer\armar_windows.ps1 -Version 1.0.0
  Resultado: build\instaladores\MODO_YA_Setup_<version>.exe
#>
param(
  [string]$Version = '0.0.0',
  # Por defecto la config publica del repo; en desarrollo se puede pasar env\dev.json.
  [string]$Entorno = 'env\publico.json'
)
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$app  = Join-Path $repo 'apps\modo_ya'
$rel  = Join-Path $app 'build\windows\x64\runner\Release'
$config = Resolve-Path (Join-Path $repo $Entorno)

Push-Location $app
# En PowerShell 5.1, con 'Stop' cualquier warning del compilador que salga por
# stderr corta el script. El resultado real lo dice $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
try {
  $definiciones = @("--dart-define-from-file=$config")
  # Con version real la app sabe cual es y busca actualizaciones.
  if ($Version -ne '0.0.0') { $definiciones += @("--dart-define=MY_VERSION=$Version", "--build-name=$Version") }
  flutter build windows --release @definiciones
  if ($LASTEXITCODE -ne 0) { throw 'Fallo flutter build windows' }
} finally { Pop-Location; $ErrorActionPreference = 'Stop' }

# Runtime de Visual C++ al lado del .exe: asi la app abre en PCs que no lo
# tienen instalado, sin pedir permisos de administrador.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products * -property installationPath
$crt = Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $crt) { throw 'No encontre el runtime de Visual C++ (VC\Redist) en Visual Studio' }
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item (Join-Path $crt.FullName $dll) $rel -Force
}

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Falta Inno Setup 6 (https://jrsoftware.org/isdl.php)' }
$ErrorActionPreference = 'Continue'
& $iscc "/DVersion=$Version" (Join-Path $PSScriptRoot 'modo_ya.iss')
if ($LASTEXITCODE -ne 0) { throw 'Fallo Inno Setup' }
