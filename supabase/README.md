# Base de datos

Proyecto Supabase: `wqahdncdqnzrusrmdyui` · región `sa-east-1` (São Paulo) · PostgreSQL 17.6 + PostGIS 3.3.7.

## Migraciones

Se aplican en orden numérico. Ninguna se edita después de aplicada: los cambios
van en una migración nueva.

| Archivo | Qué hace |
|---|---|
| `0001_extensiones_enums_y_base.sql` | PostGIS, enums, ciudades, zonas, perfiles |
| `0002_actores.sql` | comercios, repartidores, documentación |
| `0003_tarifas_y_envios.sql` | tarifario versionado, envíos, auditoría, ofertas |
| `0004_dinero_y_reclamos.sql` | pagos, suscripciones, liquidaciones, reclamos |
| `0005_funciones.sql` | cotización, máquina de estados, motor de asignación |
| `0006_rls.sql` | Row Level Security por rol |
| `0007_semilla.sql` | Malargüe, tarifario inicial, documentación exigida |
| `0008_hardening.sql` | correcciones del advisor de seguridad |
| `0009_codigos_de_error.sql` | SQLSTATE propios (ver abajo) |
| `0010_fk_de_atribucion.sql` | la auditoría no bloquea borrar una cuenta |
| `0011_politicas_sin_solapamiento.sql` | una sola política permisiva por acción |
| `0012_catalogo.sql` | clientes, rubros, menús, productos, opciones, horarios |
| `0013_pedidos.sql` | pedidos, renglones, máquina de estados, sincronía con el envío |
| `0014_rls_marketplace.sql` | RLS del catálogo y de los pedidos |
| `0015_politicas_catalogo.sql` | mismo arreglo que 0011, sobre el catálogo |
| `0016_permisos_por_columna.sql` | **crítico**: nadie puede cambiarse el rol ni autoaprobarse |
| `0017_cuentas_storage_realtime.sql` | alta automática de clientes, sesión, vistas, fotos, tiempo real |
| `0018_rol_por_update_de_auth.sql` | el rol también se toma cuando Auth lo escribe en un UPDATE |
| `0019_huecos_de_flujo.sql` | código de entrega para el cliente, horarios nocturnos, pg_cron |
| `0020_horario_testeable.sql` | la lógica de horarios recibe el momento a evaluar |
| `0021_validar_opciones_del_pedido.sql` | opciones obligatorias, únicas y máximos, validados en el servidor |
| `0022_usuario_de_la_cuenta.sql` | `admin_usuario_de`: la administración ve con qué usuario entra cada local o rider |
| `0023_rubros_con_acentos.sql` | nombres de rubros con acentos (y la copia en `comercios.rubro`) |
| `0024_carteles_del_inicio.sql` | carteles del inicio del cliente, editables desde el panel de administración |
| `0025_portada_del_local.sql` | portada del local aparte del logo |
| `0026_pago_con_tarjeta.sql` | medio de pago "tarjeta" |
| `0027_pedido_directo_al_local.sql` | el pedido llega directo al local con el medio de pago elegido; sin horarios = cerrado; la búsqueda de rider no se rinde |
| `0028_cobros_en_pedidos.sql` | estado del cobro en `v_pedidos` para la administración |
| `0029_tope_de_busqueda.sql` | la búsqueda de rider corta a las 3 horas |

## Decisiones de diseño

**El precio lo calcula el servidor, siempre.** `crear_envio()` recibe
direcciones, nunca importes. No hay política de `insert` ni de `update` directo
sobre `envios` para comercio ni cadete: la única vía son las funciones RPC. Una
app comprometida o vieja no puede fijarse su propia tarifa.

**El tarifario es versionado, no editable.** Cambiar una tarifa cierra la fila
vigente (`vigente_hasta`) y crea una nueva. Así un envío de hace tres meses
sigue mostrando lo que realmente se cobró y las liquidaciones cerradas no se
mueven solas.

**Los importes son `integer` en pesos enteros.** No hay centavos en el producto
y evitamos por completo los errores de punto flotante.

**La ciudad es una fila, no una constante.** Abrir una ciudad nueva es un
`insert`. Lo mismo con `tipo_servicio`: hoy solo se usa `delivery`, pero taxi y
cadetería ya tienen lugar, como pide el documento de la clienta.

**Una sola posición por cadete, no un histórico.** `repartidores.ultima_ubicacion`
se sobrescribe. Guardar cada ping de GPS infla la base sin dar nada: el
seguimiento en vivo va por Realtime Broadcast.

**El origen del envío se copia, no se referencia.** Si un comercio se muda, los
envíos viejos tienen que seguir diciendo desde dónde salieron.

## Cuentas

| Tipo | Cómo se crea |
|---|---|
| Cliente | Se registra solo desde la app |
| Local | Lo da de alta la administración (Edge Function `admin-crear-usuario`) |
| Rider | Lo da de alta la administración (misma función) |
| Administración | Una cuenta creada a mano |

### Usuarios de locales y riders

La administración no carga emails: `admin-crear-usuario` genera el usuario con
el nombre y una contraseña al azar que se muestra una sola vez:

- Local "Pizzería Don Luis" → `pizzeria.don.luis@modoya.com`
- Rider "Juan Pérez" → `rider.juan.perez@modoya.com`
- Si ya existe, se agrega un número: `pizzeria.don.luis.2@modoya.com`

Así el dueño o el rider conserva su email personal para registrarse como cliente
si quiere. El dominio (`MODOYA_DOMINIO_CUENTAS`, por defecto `modoya.com`) es
solo un identificador: **a esos usuarios no se les manda correo**, por eso la
misma función tiene la acción `restablecer_password` (el panel la muestra como
"Nueva contraseña" en la ficha del local o del rider).

Al crearse cualquier usuario, el trigger `alta_usuario` le arma el perfil. **El
rol sale únicamente de `raw_app_meta_data`**, que solo puede escribir el
servidor. `raw_user_meta_data` lo manda el propio usuario al registrarse: si el
rol saliera de ahí, cualquiera haría `signUp(data: {rol: 'admin'})` y se quedaría
con el panel. Un registro común no trae rol en app_metadata y cae en `cliente`.

La app pide todo lo que necesita saber de la sesión en una sola llamada:
`rpc('mi_sesion')` devuelve rol, ids de comercio/rider/cliente y estado de
aprobación.

### Permisos por columna

RLS decide **qué filas** puede tocar cada uno, no **qué columnas**. Con solo RLS,
la política "cada uno edita su perfil" dejaba hacer
`update perfiles set rol = 'admin'`, y un local pendiente podía aprobarse solo.
Estaba explotable y se verificó con una sonda antes de corregirlo (0016).

Ahora `authenticated` solo tiene `UPDATE` sobre las columnas que de verdad son
suyas (nombre, teléfono, foto, datos de la vidriera). Todo lo que cambia estado,
aprobación o privilegios va por funciones `admin_*` que verifican el rol por
dentro. `tests/permisos.sql` prueba los dos lados: lo que no se tiene que poder
y lo que sí (cerrar de más también es un bug).

## Fotos

| Bucket | Acceso | Ruta |
|---|---|---|
| `catalogo` | público (CDN) | `<comercio_id>/logo.jpg`, `<comercio_id>/productos/<producto_id>.jpg` |
| `documentos` | privado: el rider dueño y la administración | `<repartidor_id>/<tipo>.jpg` |

Cada local solo puede escribir dentro de la carpeta con su propio id.

## Vistas para la app

PostgREST devuelve las columnas `geography` como EWKB en hexadecimal, que desde
Flutter no sirve. `v_comercios`, `v_envios`, `v_pedidos`, `v_repartidores`,
`v_direcciones` y `ofertas_abiertas` exponen `lat`/`lng` como números y traen
resueltos los nombres que cada pantalla necesita. Todas son `security_invoker`,
así que respetan el RLS de quien consulta.

## Pedido y envío son cosas distintas

El sistema cubre dos productos que conviven:

- **Cadetería** — el comercio pide un cadete. Genera un `envio` sin `pedido_id`.
- **Marketplace** — el cliente arma un carrito. Genera un `pedido`, y cuando el
  comercio lo acepta nace el `envio` que lo lleva (`envios.pedido_id`).

Modelarlos por separado es lo que permite que la cadetería siga funcionando sola
sin arrastrar el catálogo, y que el marketplace reutilice entero el motor de
asignación que ya existía.

Dos detalles que importan:

**La cotización del envío se congela en el pedido.** El cliente paga $3.500 de
envío al comprar; media hora después el comercio acepta y el envío se crea con
*esos* $3.500, no con una cotización nueva. Por eso `pedidos` guarda
`envio_tarifario_id`, `envio_ganancia_repartidor` y `envio_comision`.

**Se busca cadete recién cuando el pedido está listo**, no cuando se acepta. No
tiene sentido tener a alguien esperando en la puerta mientras se prepara la
comida.

**El estado del envío arrastra al del pedido.** Cuando el cadete marca
"retirado", el pedido pasa solo a `en_camino`; al confirmar la entrega, queda
`entregado`. Lo hace un trigger, así el cliente ve un estado coherente sin que
nadie lo sincronice a mano.

## Privacidad

El documento de la clienta pide no mostrar datos completos del cliente a
repartidores no asignados. Se implementa en tres capas:

1. **Antes de aceptar**, el cadete ve el envío por la vista `ofertas_abiertas`,
   que **no expone** `cliente_nombre`, `cliente_telefono` ni
   `cliente_indicaciones`. Esos campos aparecen recién cuando acepta.
2. **El cadete nunca ve el pedido.** Qué productos pidió el cliente y cuánto
   pagó no le hace falta para entregar. `pedidos` y `pedido_items` no le
   devuelven ni una fila.
3. **La libreta de direcciones es del cliente.** Ni el comercio ni el cadete la
   ven: a ellos les llega copiada, en el pedido y en el envío, solo la dirección
   de esa entrega.

Las tres están verificadas en `tests/flujo_marketplace.sql`.

## Códigos de error

Viajan en la respuesta de PostgREST, así que la app puede distinguirlos sin leer
el texto del mensaje.

| Código | Significado |
|---|---|
| `MY001` | transición de estado inválida |
| `MY002` | código de entrega incorrecto |
| `MY003` | la oferta ya no está disponible (venció o la tomó otro) |
| `MY004` | no existe el recurso pedido |
| `MY005` | el comercio está cerrado |
| `MY006` | datos inválidos (cantidad, opción que no corresponde) |
| `42501` | sin permiso o cuenta no aprobada (PostgREST → HTTP 403) |

> No usar la clase `P00xx`: ya está tomada por PL/pgSQL. En particular `P0004`
> es `assert_failure`, que `exception when others` **no atrapa**.

## Pruebas de regresión

Todas dejan la base como la encontraron. Se corren con:

```powershell
.\supabase\scripts\sql.ps1 supabase\tests\permisos.sql
```

**`tests/horarios.sql`** — `comercio_abierto_en()` con momentos fijos: turnos
normales, que cruzan medianoche, vuelta de sábado a domingo, pausa manual.

**`tests/cuentas.ps1`** — alta de cuentas contra la API real de Auth y la Edge
Function. Existe porque GoTrue escribe el `app_metadata` en un UPDATE posterior
al INSERT, algo que un test SQL no puede ver (ver 0018).

**`../packages/my_core/test/integracion_test.dart`** — los repositorios de la app
contra la base real: nombres de columnas de las vistas, parámetros de las RPC,
parseo de respuestas y Realtime con el RLS de cada usuario. Se prepara con
`tests/preparar_prueba_app.ps1`.

**`tests/permisos.sql`** — escalada de privilegios. Cliente que intenta hacerse
admin, local que intenta aprobarse, rider que se infla los viajes o valida su
propio documento, registro con `rol: admin` en user_metadata. Y del otro lado,
que cada uno sí pueda editar lo suyo.

**`tests/flujo_completo.sql`** — cadetería. Crear → cotizar → buscar → ofertar →
aceptar → retirar → entregar. Verifica que el precio lo ponga el servidor, que
el motor elija al cadete más cercano *dentro del radio* (hay un segundo cadete a
9 km que debe quedar afuera), que una transición inválida rebote y que un código
de entrega equivocado no cierre el envío.

**`tests/flujo_marketplace.sql`** — marketplace. Carrito con opciones → pago →
aceptación → preparación → entrega. Además de los precios y la sincronía entre
pedido y envío, comprueba las tres reglas de privacidad de arriba.

> **Ojo al escribir pruebas de RLS.** Estos scripts corren como `postgres`, que
> es dueño de las tablas y **saltea RLS por completo**. Cualquier comprobación
> de políticas necesita `set local role authenticated` (y volver con
> `reset role` antes de escribir en la tabla temporal de resultados, que
> `authenticated` no puede tocar). Sin eso, un test de RLS pasa siempre y no
> prueba nada. `flujo_completo.sql` ejercita las RPC, que validan por dentro,
> pero **no** verifica RLS; el de marketplace sí.

## Pendiente

- **Custom Access Token Hook** para llevar el rol en el JWT. Hoy las políticas
  lo leen de `perfiles` con funciones `security definer`, que funciona bien; el
  hook ahorraría una consulta por request.
- **Zonas de cobertura**: la tabla existe, falta cargar el polígono de Malargüe
  y rechazar destinos fuera del área.
