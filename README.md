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

## Dos apps, no una

| App | Quien la usa | Por que |
|---|---|---|
| **MODO YA** | Clientes, locales y administracion | El rol de la cuenta decide que pantallas ve cada uno |
| **MODO YA Rider** | Riders | Necesita ubicacion (y en produccion, en segundo plano). Es el permiso que mas revisan Apple y Google; dentro de una app de clientes lo mas probable es que rechacen la publicacion |

## Cuentas

| Tipo | Como se crea |
|---|---|
| Cliente | Se registra solo desde la app |
| Local | Lo da de alta la administracion desde la app (queda con contrasena temporal) |
| Rider | Lo da de alta la administracion desde la app |
| Administracion | Se crea a mano (ver abajo) |

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

### Requisitos en Windows

- **Modo desarrollador** activado (los plugins usan symlinks).
- **Visual Studio** con la carga *Desarrollo para el escritorio con C++*.
  `flutter doctor` tiene que mostrar Visual Studio sin cruces.

## Que hay en cada app

**Cliente:** locales por rubro, menu con fotos y personalizacion (tamanos,
agregados), carrito, direcciones con pin en el mapa, pedido, seguimiento con el
codigo de entrega que le dicta al rider.

**Local:** pedidos que entran en vivo (aceptar, preparar, listo), editor de menu
con fotos y opciones, horarios (incluso turnos que cruzan medianoche), pausa
manual, cadeteria (pedir rider para pedidos por telefono) con seguimiento.

**Administracion:** resumen con mapa en vivo, alta de locales y riders, pedidos
por cobrar (provisorio), suspension, envios en curso, tarifas.

**Rider:** conectarse con ubicacion, ofertas con cuenta regresiva, recorrido
retiro/entrega con confirmacion por codigo, ganancias.

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
- **Mails:** el registro de clientes necesita SMTP propio o desactivar la
  confirmacion de email (ver `docs/preguntas-para-la-clienta.md`).
- **Fuentes:** se descargan en tiempo de ejecucion; conviene empaquetarlas.

## Del diseno que no se implemento a proposito

Puntos "Club MODO YA", cupones, propina y estrellas de los locales: la base no
tiene esos datos y el documento de la clienta excluye el programa de puntos.
Mejor no mostrar numeros inventados.
