# Iconos de las apps

Cada app tiene su propio icono: MODO YA usa el logo "MODO YA" y la app del
rider el logo "MODO YA RIDERS". Los logos con fondo transparente viven en
`packages/my_ui/assets/branding/`.

Para regenerarlos (Android, web y Windows):

```powershell
# 1. Imagen base: fondo negro + logo centrado (1024 px).
.\tools\icono_app.ps1 packages\my_ui\assets\branding\logo_modo_ya.png apps\modo_ya\assets\icono\icono.png
.\tools\icono_app.ps1 packages\my_ui\assets\branding\logo_riders.png  apps\repartidor\assets\icono\icono.png

# 2. Repartir a cada plataforma (una vez: dart pub global activate flutter_launcher_icons).
cd apps\modo_ya;    dart pub global run flutter_launcher_icons; cd ..\..
cd apps\repartidor; dart pub global run flutter_launcher_icons; cd ..\..
```

El icono adaptativo de Android usa el logo transparente sobre fondo negro con
un margen del 24 %, para que la máscara redonda de cada celular no corte el
texto. El margen se ajusta en `apps/<app>/flutter_launcher_icons.yaml`.
