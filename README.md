# MODO YA

Plataforma local de delivery y cadetería para **Malargüe, Mendoza**. Un comercio
pide un cadete, el sistema busca al disponible más cercano, y el envío se sigue
hasta la entrega confirmada con código.

Monorepo Flutter (Dart 3) con dos apps y dos paquetes compartidos.

---

## Estructura

```
MODO_YA/
├─ apps/
│  ├─ gestion/       Comercio + Administración · Windows, Android (+web para demo)
│  └─ repartidor/    Cadetes · Android (+web para demo)
├─ packages/
│  ├─ my_core/       Modelos, máquina de estados del envío, repositorios, providers
│  └─ my_ui/         Tokens, tema y componentes del sistema de diseño
└─ .claude/          Configuración de herramientas
```

Es un **Dart pub workspace**: un solo `flutter pub get` en la raíz resuelve todo.

### Por qué dos apps y no una

La app del cadete pide **ubicación en segundo plano**. Es el permiso que más
miran Apple y Google en la revisión, y si viaja dentro de la app del comercio lo
más probable es que rechacen la publicación. Van separadas por eso.

Comercio y Administración sí comparten app: son el mismo binario con distinto
rol. El panel de admin usa riel lateral en pantallas anchas (Windows) y barra
inferior cuando la ventana es angosta.

---

## Correr el proyecto

```bash
flutter pub get
```

```bash
cd apps/gestion && flutter run -d windows
```

```bash
cd apps/repartidor && flutter run -d android
```

Sin credenciales de Supabase, las apps arrancan en **flavor `demo`**: datos en
memoria con calles reales de Malargüe. Sirve para recorrer todos los flujos sin
base de datos.

### Con Supabase

Creá `env/dev.json` (está en `.gitignore`, nunca se commitea):

```json
{
  "MY_FLAVOR": "dev",
  "MY_SUPABASE_URL": "https://TU-PROYECTO.supabase.co",
  "MY_SUPABASE_KEY": "sb_publishable_..."
}
```

```bash
flutter run --dart-define-from-file=../../env/dev.json
```

> La **publishable key** va en la app: es pública por diseño, cualquiera la puede
> leer del binario. Lo que protege los datos es RLS, no el secreto de esa clave.
> La **secret key** (`sb_secret_...`) equivale a `service_role` y saltea RLS por
> completo: solo puede vivir en Edge Functions. Nunca en el repo ni en la app.

---

## Estado del envío

El ciclo de vida completo vive en `EstadoEnvio` (`my_core`), con su tabla de
transiciones válidas:

```
borrador → cotizado → buscando_repartidor → asignado → en_local
         → retirado → en_camino → entregado
                    ↘ cancelado / sin_repartidor
```

La tabla de transiciones está en Dart para validar en la UI **antes** de mandar,
pero la regla que vale se va a hacer cumplir del lado del servidor con una
función RPC, para que ninguna app pueda saltear pasos.

---

## Tarifas

Los valores iniciales salen del documento MVP de la clienta:

| Concepto                     | Valor    |
|------------------------------|----------|
| Ganancia del cadete (≤ 2 km) | $3.000   |
| Comisión MODO YA             | $500     |
| **Total hasta 2 km**         | **$3.500** |
| Kilómetro adicional          | a definir |

Todo es editable desde el panel de administración (pantalla *Tarifas y reglas*)
porque la clienta pidió expresamente poder actualizarlos **sin publicar una
versión nueva de la app**.

---

## Mapeo pantalla ↔ código

| Diseño (Stitch)                     | Dónde está |
|-------------------------------------|-----------|
| A1 Bienvenida                        | `gestion/features/onboarding/bienvenida_page.dart` |
| A2 Registro del comercio             | `gestion/features/onboarding/registro_page.dart` |
| A3 Cuenta en revisión                | `gestion/features/onboarding/revision_page.dart` |
| A4 Inicio comercio                   | `gestion/features/comercio/inicio_page.dart` |
| A5 Crear envío + A6 Cotización       | `gestion/features/comercio/crear_envio_page.dart` |
| A7–A10 Buscando / Asignado / Retiro / Entregado | `gestion/features/comercio/seguimiento_page.dart` |
| A11 Historial                        | `gestion/features/comercio/historial_page.dart` |
| A12 Suscripción                      | `gestion/features/comercio/suscripcion_page.dart` |
| B1 Perfil y documentación            | `repartidor/features/perfil_page.dart` |
| B2 Inicio del cadete                 | `repartidor/features/inicio_page.dart` |
| B3 Oferta de servicio                | `repartidor/features/oferta_sheet.dart` |
| B4–B7 Servicio en curso              | `repartidor/features/servicio_page.dart` |
| B8 Ganancias e historial             | `repartidor/features/ganancias_page.dart` |
| C1 Dashboard                         | `gestion/features/admin/dashboard_page.dart` |
| C2 Mapa en vivo                      | `gestion/features/admin/mapa_page.dart` |
| C3 Comercios                         | `gestion/features/admin/comercios_page.dart` |
| C4 Cadetes                           | `gestion/features/admin/repartidores_page.dart` |
| C5 Envíos y trazabilidad             | `gestion/features/admin/envios_page.dart` |
| C7 Tarifas y reglas                  | `gestion/features/admin/tarifas_page.dart` |

**A7 a A10 son una sola pantalla.** En el diseño están separadas, pero son el
mismo layout en distintos estados del envío; resolverlas con un widget que
reacciona al estado evita cuatro rutas que hay que mantener sincronizadas. Lo
mismo con B4–B7.

---

## Lo que todavía no está

- **Supabase**: hoy corre todo contra `EnviosRepositoryDemo` (memoria). Las apps
  dependen de las interfaces de `my_core/repositories`, así que conectar la base
  es implementar `EnviosRepositorySupabase` y sobrescribir un provider.
- **Motor de asignación**: el botón *Simular una oferta (demo)* dispara la
  pantalla B3 a mano. Falta la función SQL con PostGIS que busca por cercanía.
- **Mapa**: `flutter_map` + `malargue.pmtiles`. Hoy hay un placeholder en C2.
- **Pagos**: sin definir con la clienta (ver *Pendientes*).
- **Distancia**: el slider de `crear_envio_page` es provisorio; reemplazarlo por
  el pin en el mapa + cálculo PostGIS.
- **Fuentes**: se bajan en runtime con `google_fonts`. Para producción conviene
  empaquetar Outfit y Be Vietnam Pro en `assets/`.
- **C6 Dinero y liquidaciones** y **C8 Reclamos**: pantallas no implementadas,
  dependen de definir cómo se cobra y cómo se liquida.

---

## Pendientes con la clienta

Bloquean decisiones técnicas, no solo comerciales:

1. **Pasarela de pago.** El MVP se planteó sin efectivo, pero la pantalla B3 del
   diseño dice "cobro en mano en efectivo". Hay que cerrarlo: cambia el modelo
   de datos de pagos y liquidaciones.
2. **Precio del kilómetro adicional** después de los primeros 2 km.
3. **Radio de búsqueda** y **tiempo para aceptar** de cada cadete.
4. **Frecuencia y método de liquidación** al cadete.
5. **Precio de la suscripción** mensual del comercio.
6. **Documentación exigida** por tipo de vehículo.

### Alcance: cadetería vs. marketplace

El documento MVP de la clienta excluye explícitamente (sección 13) el
marketplace de comida, el catálogo de productos y la app del cliente final. El
set de pantallas incluye un grupo **D** (home de cliente, menú del local, carrito
y checkout) que corresponde a un producto distinto y más grande.

**Este repo implementa la cadetería (A, B, C).** El grupo D queda para una etapa
posterior y debería presupuestarse aparte.
