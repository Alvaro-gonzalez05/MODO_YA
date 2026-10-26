# MODO YA

Plataforma de delivery y cadetería para Malargüe, Mendoza. Flutter + Supabase.
Cliente final: Carolina (dueña del negocio y de la cuenta de Mercado Pago).
Desarrollo: Codea Desarrollos.

## Cómo está armado

Workspace de Flutter (SDK `^3.13.3`), dos apps y dos paquetes compartidos:

| Carpeta | Qué es |
| --- | --- |
| `apps/modo_ya` | La app principal: cliente, local y administración en un solo binario |
| `apps/repartidor` | La app del rider, separada a propósito |
| `packages/my_core` | Modelos, repositorios y providers de Riverpod |
| `packages/my_ui` | Componentes (`MyBoton`, `MyCampo`, `MyCard`…) y tokens de diseño |
| `supabase/` | Migraciones, Edge Functions, tests SQL y scripts |
| `landing/` | Sitio público estático |
| `tools/` | `dev.mjs` (server local), `servir.mjs`, `capturas/` |

Navegación con go_router (`StatefulShellRoute`), estado con Riverpod.

## Idioma y estilo

**Todo en castellano rioplatense, con voseo**: nombres de tablas, funciones,
variables, archivos, commits y texto de la interfaz. `crear_pedido`, no
`createOrder`. "Escribí por qué se le cobra", no "Escribe".

Los comentarios explican **por qué**, no qué hace el código. Si una decisión fue
deliberada (un filtro que se repite a propósito, un nombre que no se puede
cambiar porque rompe otra cosa), eso va en un comentario.

Mensajes de commit: una línea, en castellano, describiendo el efecto para el
usuario. "El botón de PDF estaba escondido", no "fix: button visibility".

## La base de datos

Postgres en Supabase con RLS en todo. La lógica de negocio vive en funciones
`security definer`, no en la app. Las vistas usan `security_invoker`.

Las migraciones están numeradas (`0001_…` a `0073_…`) y se aplican con:

```bash
powershell -NoProfile -Command "& './supabase/scripts/sql.ps1' -Archivo 'ruta/al/archivo.sql'"
```

**Trampa importante:** `sql.ps1` corre como `postgres`, que **ignora el RLS**.
Un test que verifica permisos tiene que hacer `set local role authenticated` y
después `reset role`, o va a pasar siempre aunque la política esté mal.

Otras cosas que ya costaron tiempo:
- Postgres no deja renombrar columnas de una vista con `create or replace`:
  hay que `drop view` y crearla de nuevo.
- Cambiar la firma de una función (agregar un parámetro con default) requiere
  `drop function` con la firma vieja primero.

### Edge Functions

En `supabase/functions/`: `pagar-pedido`, `mp-webhook`, `mp-procesar-avisos`,
`reembolsar`, `enviar-push`, `admin-crear-usuario`, `ruta`. Se despliegan con:

```bash
powershell -NoProfile -Command "& './supabase/scripts/desplegar_funcion.ps1' -Nombre pagar-pedido"
```

El metadata del deploy se escribe a un archivo **sin BOM** (`[IO.File]::WriteAllText`),
si no la API lo rechaza con `Invalid metadata JSON`.

## Pagos — leer antes de tocar nada

En la app **solo se paga con tarjeta**. Efectivo y transferencia salieron
(migración `0058`). Los mandados son aparte y siguen con efectivo.

Se usa la **Orders API** de Mercado Pago (`POST /v1/orders`), no la de Payments.
Montos como string con dos decimales (`"13550.00"`).

### Dónde van las credenciales

- **Public key** → `env/dev.json` y `env/publico.json`. Es pública por diseño:
  solo tokeniza tarjetas del lado del cliente, no puede cobrar ni devolver.
  `env/publico.json` está trackeado y es el que compila los instaladores.
- **Access token y clave del webhook** → secretos de Supabase, cargados con
  `guardar_secreto.ps1` (pide el valor oculto, no queda en disco ni en el
  historial). Una vez cargados **no se pueden volver a leer**: la API los
  devuelve hasheados.

**Nunca pedir ni aceptar credenciales pegadas en el chat.** Si aparece una,
hay que decir que se renueve.

### Modo simulado

Si no hay `MP_ACCESS_TOKEN`, o si la app manda un token que empieza con
`token-simulado`, no se llama a Mercado Pago y el pago se simula. Una app
compilada **sin** public key manda ese token. Por eso un build de demo se hace
con `MY_MP_PUBLIC_KEY` vacío en `env/dev.json`.

## Tests

- SQL: `supabase/tests/*.sql`, se corren con `sql.ps1`. Datos de prueba con
  `preparar_prueba_app.ps1`.
- Dart: `packages/my_core/test/integracion_test.dart`.

## El server local

```bash
node tools/dev.mjs modo_ya 5051
```

Compila en `D:\dev\modoya-dev` y sirve el build. **Trampa:** si ya hay un build
viejo ahí, lo sirve al instante mientras recompila — hay que verificar que el
bundle servido sea el nuevo antes de sacar conclusiones o capturas.

## Entorno Windows — trampas conocidas

- La shell es **PowerShell 5.1**: `&&` es un error de sintaxis. Se encadena con
  `;` y `if ($?) { … }`.
- PowerShell envuelve el stderr de los ejecutables nativos en `NativeCommandError`:
  un mensaje informativo de Flutter ("Wasm dry run succeeded") **parece** un
  error de compilación y no lo es.
- `grep` sobre strings con acentos contra JS minificado da falsos negativos.
  Buscar siempre subcadenas sin acentos.

## Publicar una versión

Se etiqueta y se pushea el tag; GitHub Actions compila los instaladores
(`.github/workflows/release.yml`). El mensaje del tag es el changelog que ve el
usuario. `[obligatoria]` al principio fuerza la actualización.

`mantener-viva.yml` pega en la base una vez por día para que Supabase no pause
el proyecto por inactividad.

## Estado

Ver `README.md` (estado general), `supabase/README.md` (la base en detalle) y
`docs/hallazgos-de-la-revision.md` (lo que falta, con severidad).
