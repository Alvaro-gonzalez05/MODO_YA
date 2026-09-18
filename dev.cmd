@echo off
rem Abre MODO YA en modo desarrollo, conectada a la base (env\dev.json).
rem   dev            -> app principal (clientes, locales, administracion)
rem   dev rider      -> app del rider
rem Se recarga sola cada vez que se guarda un cambio. Cerrar esta ventana la apaga.
cd /d "%~dp0"
if /i "%1"=="rider" (
  set APP=repartidor
  set PUERTO=5052
) else (
  set APP=modo_ya
  set PUERTO=5051
)
start "" cmd /c "timeout /t 90 >nul & start http://localhost:%PUERTO%"
node tools\dev.mjs %APP% %PUERTO%
