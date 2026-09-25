# MODO YA

Plataforma de delivery para **Malargüe, Mendoza**: cadetería (el local pide un
rider) y marketplace (el cliente pide a los locales desde la app).

Monorepo Flutter (Dart 3) + Supabase.

```
MODO_YA/
├─ apps/
│  ├─ modo_ya/       App MODO YA: clientes, locales y administracion
│  └─ repartidor/    App MODO YA Rider
├─ packages/
│  ├─ my_core/       Sesion, modelos, repositorios Supabase, providers
│  └─ my_ui/         Sistema de diseno: tokens, tema, componentes, mapas
├─ supabase/         Migraciones, Edge Functions, pruebas (ver supabase/README.md)
├─ docs/             Preguntas abiertas con la clienta
└─ env/              Configuracion local (ignorada por git; ver env/example.json)
```

## Descargas

Última versión (siempre estos mismos links):

| App | Plataforma | Link |
|---|---|---|
| MODO YA | Android | [MODO_YA-Android.apk](https://github.com/Alvaro-gonzalez05/MODO_YA/releases/latest/download/MODO_YA-Android.apk) |
| MODO YA | Windows | [MODO_YA-Windows-Setup.exe](https://github.com/Alvaro-gonzalez05/MODO_YA/releases/latest/download/MODO_YA-Windows-Setup.exe) |
| MODO YA | Windows sin instalar | [MODO_YA-Windows-portable.zip](https://github.com/Alvaro-gonzalez05/MODO_YA/releases/latest/download/MODO_YA-Windows-portable.zip) |
| MODO YA Rider | Android | [MODO_YA-Rider-Android.apk](https://github.com/Alvaro-gonzalez05/MODO_YA/releases/latest/download/MODO_YA-Rider-Android.apk) |

Todas las versiones: [Releases](https://github.com/Alvaro-gonzalez05/MODO_YA/releases).

## Dos apps, no una

| App | Quién la usa | Por qué |
|---|---|---|
| **MODO YA** | Clientes, locales y administracion | El rol de la cuenta decide que pantallas ve cada uno |
| **MODO YA Rider** | Riders | Necesita ubicacion (y en produccion, en segundo plano). Es el permiso que mas revisan Apple y Google; dentro de una app de clientes lo mas probable es que rechacen la publicacion |

## Cuentas

| Tipo | Como se crea |
|---|---|
| Cliente | Se registra solo desde la app |
| Local | Lo da de alta la administración desde la app: usuario `nombre.del.local@modoya.com` y contraseña generados |
| Rider | Igual: `rider.nombre.apellido@modoya.com` |
| Administración | Se crea a mano |

Los usuarios generados no reciben correo: si alguien se olvida la contraseña,
la administración le genera una nueva desde su ficha.

El rol **no lo puede elegir el usuario**: la base lo lee solo de metadatos que
escribe el servidor. Detalles en `supabase/README.md`.

## Correr

```bash
flutter pub get
```

Crea `env/dev.json` a partir de `env/example.json` (URL del proyecto y la
*publishable key*; nunca la secret key).

```bash
cd apps/modo_ya
flutter run -d windows --dart-define-from-file=../../env/dev.json
```

```bash
cd apps/repartidor
flutter run -d android --dart-define-from-file=../../env/dev.json
```

### Publicar una versión

No hace falta compilar en esta PC. Se empuja un tag y GitHub Actions compila
las dos apps y crea el Release (`.github/workflows/release.yml`):

```bash
git tag -a v1.2.0 -m "Qué cambió (se muestra en el aviso de actualización)"
git push origin v1.2.0
```

Con `[obligatoria]` en el mensaje del tag, las apps instaladas no dejan seguir
hasta actualizar (para cambios en la base que las versiones viejas no
entienden).

### Actualizaciones automáticas

Cada Release publica también `ultima.json`. Las apps (desde la 1.1.0) lo leen de
`releases/latest/download/ultima.json` al abrir y cada 6 horas; si hay una
versión más nueva muestran un aviso con "Actualizar":

- **Windows:** baja el instalador, cierra la app, instala en silencio y la
  vuelve a abrir.
- **Android:** baja el APK y abre el instalador del sistema (Android siempre
  pide confirmar; la primera vez pide permiso para instalar desde MODO YA).

Código: `packages/my_ui/lib/src/actualizaciones/` y el canal
`modoya/actualizaciones` en `MainActivity.kt` de cada app.

### Clave de firma de Android

Los APK de release se firman **siempre con la misma clave**: Android no instala
una actualización firmada con otra. La clave no está en el repo:

- En GitHub, secretos `ANDROID_KEYSTORE_BASE64` y `ANDROID_KEYSTORE_PASSWORD`
  (alias `modoya`). Sin ellos el workflow no publica.
- En la PC de desarrollo, `D:\dev\claves\modoya\` (con un LEEME). Para compilar
  local firmado: variable `MY_KEY_PROPERTIES` apuntando a su `key.properties`.
  Sin esa variable, `flutter build apk` firma con la clave de debug.

**Si la clave se pierde, las apps instaladas no pueden actualizarse nunca más.**
Guardar una copia fuera de la PC.

### Compilar a mano

```bash
cd apps/modo_ya
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=../../env/publico.json
```

Windows: `.\installer\armar_windows.ps1 -Version 1.2.0` compila y arma
`build\instaladores\MODO_YA_Setup_<version>.exe` con Inno Setup 6 (instala por
usuario, sin pedir administrador). Se compila con `env/publico.json` (URL y
publishable key, públicas por diseño).

### Requisitos en Windows

- **Modo desarrollador** activado (los plugins usan symlinks).
- **Visual Studio** con la carga *Desarrollo para el escritorio con C++*.
  `flutter doctor` tiene que mostrar Visual Studio sin cruces.

## Probar mientras se desarrolla

Doble clic en `dev.cmd` (o `dev rider` para la app del rider). Abre
http://localhost:5051 conectada a la base real (`env/dev.json`) y **se recarga
sola cada vez que se guarda un cambio** (compila en `D:\dev\modoya-dev`, ~1 min
por cambio, para no llenar el disco C:). En la PC se ve el diseño completo; para
ver el del celular, achicar la ventana o usar F12 → icono de celular. Desde un
celular en la misma wifi: `http://<IP de la PC>:5051` (la consola la muestra).

## Diseño

Cada pantalla tiene dos diseños, no uno estirado (`packages/my_ui/lib/src/widgets/responsive.dart`):

- **PC (desde 1100 px):** barra lateral navy, barra superior con el estado y el
  menú del usuario, tablas y fichas al costado (diseños C de Stitch).
- **Tableta (720 a 1100):** barra lateral compacta, solo iconos.
- **Celular:** el dock flotante de la app del rider; si no entran los botones,
  el último es "Más".

Para revisar pantallas sin abrir la app a mano: `tools/capturas/capturar.mjs`
(Chrome headless sobre la versión web).

## Qué hay en cada app

**Cliente:** locales por rubro, ofertas del dia, menu con fotos y
personalizacion (tamanos, agregados), carrito, direcciones con pin en el mapa,
pago con tarjeta dentro de la app (tarjetas guardadas), MODO YA Plus (envio
gratis en los locales adheridos, con renovacion automatica), seguimiento con el
codigo de entrega que le dicta al rider.

**Local:** pedidos que entran en vivo (aceptar, preparar, listo), editor de menu
con fotos y opciones, promociones (descuento en todo el menu o en lo que elija),
campanas (publicidad y MODO YA Plus), horarios (incluso turnos que cruzan
medianoche), pausa manual, cadeteria (pedir rider para pedidos por telefono) con
seguimiento.

**Administracion:** resumen con mapa en vivo, alta de locales y riders, cobros,
liquidaciones por local y por rider, promociones de todos los locales,
suspension, envios en curso, tarifas y carteles.

**Rider:** conectarse con ubicacion, ofertas con cuenta regresiva, recorrido
retiro/entrega con confirmacion por codigo, cuanto tiene que cobrar en la
puerta, ganancias.

## Pruebas

Todo contra el proyecto real y dejando la base como estaba.

```powershell
# Base: permisos, horarios, flujos de cadeteria y marketplace
.\supabase\scripts\sql.ps1 supabase\tests\permisos.sql

# Alta de cuentas contra Auth + Edge Function reales
.\supabase\tests\cuentas.ps1

# La app de punta a punta: los repositorios de Dart contra la base real
.\supabase\tests\preparar_prueba_app.ps1
cd packages\my_core
flutter test test\integracion_test.dart --dart-define-from-file=..\..\env\test.json
cd ..\..
.\supabase\tests\preparar_prueba_app.ps1 -Limpiar
```

El test de integracion recorre el flujo entero: la administracion crea un local
y un rider, el local arma su menu con foto, el cliente pide, se confirma el pago,
el local lo prepara, el rider lo recibe, retira y entrega con el codigo que ve
el cliente. Tambien cadeteria, rechazos, reglas de opciones y tiempo real.

## Provisorio (antes de produccion)

- **Mapas:** las baldosas salen del servidor publico de OpenStreetMap, que no
  admite uso productivo. Hay que pasar al archivo propio `malargue.pmtiles`
  (un cambio en `packages/my_ui/lib/src/widgets/mapa.dart`).
- **Pagos:** no esta decidido como se cobra. Mientras tanto, la administracion
  confirma cada pago a mano desde la app.
- **Ubicacion del rider en segundo plano:** hoy se manda con la app abierta.
- **Mails:** la confirmacion de email esta desactivada (cualquiera se registra
  sin validar su correo). Falta SMTP propio para volver a activarla y para
  recuperar contrasenas (ver `docs/preguntas-para-la-clienta.md`).
- **Fuentes:** se descargan en tiempo de ejecucion; conviene empaquetarlas.

## Del diseno que no se implemento a proposito

Puntos "Club MODO YA", cupones, propina y estrellas de los locales: la base no
tiene esos datos y el documento de la clienta excluye el programa de puntos.
Mejor no mostrar numeros inventados.
