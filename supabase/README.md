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
| `0030_todo_en_vivo.sql` | locales, horarios, menús, rubros, direcciones y tarifas en Realtime |
| `0031_cobro_al_entregar.sql` | el envío dice cuánto tiene que cobrar el rider en la puerta y con qué |
| `0032_pago_con_tarjeta_en_la_app.sql` | cobro con Mercado Pago (Checkout API), tarjetas guardadas |
| `0033_evento_del_pago_con_perfil.sql` | arreglo: el evento del pago guarda el perfil, no el cliente |
| `0034_reintentar_el_pago.sql` | una tarjeta rechazada no cancela el pedido; los abandonados los cierra un cron |
| `0035_liquidaciones.sql` | qué le queda a cada local y a cada rider, y el cierre que evita pagar dos veces |
| `0036_campanias_y_plus.sql` | campañas del local (publicidad y Plus) y suscripciones de MODO YA Plus |
| `0037_envio_gratis_con_plus.sql` | el local con campaña Plus paga el envío; al cliente le figura gratis |
| `0038_publicidad_una_vez_por_dia.sql` | arreglo: la publicidad se cobra un solo día por día |
| `0039_vista_de_campanias_y_alta_de_plus.sql` | `v_campanias` con lo gastado y lo disponible; alta de Plus |
| `0040_promociones.sql` | descuentos del local sobre su menú: todo, secciones o productos sueltos |
| `0041_renovacion_de_plus.sql` | Plus se renueva solo con la tarjeta guardada, y el cliente lo corta cuando quiere |
| `0042_promociones_con_el_local.sql` | `v_promociones` dice de qué local es cada una (pantalla de la administración) |
| `0043_plus_se_renueva_el_mismo_dia.sql` | Plus se cobra el mismo día de cada mes, no cada 30 días |
| `0044_avisos_de_mercado_pago.sql` | buzón de webhooks de Mercado Pago (`mp_notificaciones`) |

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

## Pagos con tarjeta

El cliente paga dentro de la app y la plata entra a la cuenta de MODO YA.

**Los datos de la tarjeta nunca pasan por la base ni por nuestro servidor.** La
app se los manda directo a Mercado Pago (Checkout API) con la clave pública
(`MY_MP_PUBLIC_KEY`), que devuelve un token de un solo uso. Con ese token cobra
la Edge Function `pagar-pedido`, la única que tiene el secreto
`MP_ACCESS_TOKEN`. De la tarjeta guardada solo queda la referencia de Mercado
Pago y "Visa ••••4218" (`tarjetas_guardadas`).

El pedido nace en `pendiente_pago` y **no le llega al local hasta que el pago
se aprueba**: si la tarjeta rebota, la cocina no llegó a empezar. Un rechazo no
cancela el pedido (se puede reintentar con otra tarjeta); los abandonados los
cierra `cerrar_pagos_vencidos()` a la media hora.

**Sin `MP_ACCESS_TOKEN` configurado, la función trabaja simulada**: aprueba sin
cobrar nada (o rechaza si el titular es "RECHAZADA"). Sirve para probar la
pantalla antes de tener la cuenta.

## Avisos de Mercado Pago (webhooks)

El cobro con tarjeta responde en el momento, así que para el caso feliz no hace
falta nada más. Los webhooks tapan lo que pasa **después**:

- un pago que quedó `in_process` y se aprueba diez minutos más tarde (hoy el
  pedido lo cierra `cerrar_pagos_vencidos()` sin enterarse);
- una devolución o un contracargo hechos desde el panel de Mercado Pago, que
  dejarían la liquidación de ese local mal;
- renovaciones de Plus que Mercado Pago resuelva en diferido.

La Edge Function **`mp-webhook`** recibe el aviso y lo guarda tal cual en
`mp_notificaciones`. **Por ahora solo guarda**: todavía no toca el pedido,
porque el cuerpo del aviso cambia según la aplicación de Mercado Pago sea de
Orders o de Payments y no hay credenciales para ver avisos reales. Guardar desde
el día uno permite reprocesar lo que ya llegó en vez de haberlo perdido.

Reglas de Mercado Pago que condicionan el diseño:

- Hay que contestar **200 o 201 en menos de 22 segundos**; si no, reintenta cada
  15 minutos. Por eso la función no llama a nadie ni hace nada lento.
- Un reintento trae el mismo `x-request-id`, así que ese campo tiene índice
  único: el mismo aviso no se guarda dos veces.
- El aviso viene firmado en `x-signature` (`ts=…,v1=…`). La firma es un
  HMAC-SHA256 del texto `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` con la
  clave secreta que Mercado Pago muestra al configurar la notificación, y que va
  como secreto `MP_WEBHOOK_SECRET`.

Sin `MP_WEBHOOK_SECRET` no se valida y se guarda igual con `firma_valida` en
null, para poder probar con el simulador de notificaciones antes de tener la
clave. **Antes de actuar sobre un pedido hay que exigir `firma_valida`**: si no,
cualquiera que conozca la URL podría darnos un pago por bueno.

URL a cargar en Mercado Pago (Tus integraciones → la aplicación → Webhooks):

```
https://wqahdncdqnzrusrmdyui.supabase.co/functions/v1/mp-webhook
```

## Liquidaciones

La plata la cobra MODO YA (tarjeta en la app) o la junta el rider (efectivo).
Después hay que repartirla:

- **Local** = lo que vendió en productos − mensualidad − publicidad − ajustes
  (`cargos_comercio`). El envío no entra: ese dinero es de MODO YA.
- **Rider** = la ganancia de los envíos que entregó − el efectivo que cobró en
  la puerta y todavía no rindió.

`pendiente_de_liquidar_comercios()` y `pendiente_de_liquidar_riders()` son lo
que muestra el panel; `cerrar_liquidacion_*()` la deja registrada y marca esos
pedidos y envíos, para que **no se paguen dos veces**. `supabase/tests/liquidaciones.sql`
recorre el circuito entero.

## Campañas y MODO YA Plus

El local pone plata en una **campaña** y elige para qué la usa:

- **Publicidad** — aparece primero en la lista de locales (`destacado`). Se
  cobra por día, una sola vez por día (`cobrar_dia_de_publicidad()`, cron
  `publicidad-del-dia` a las 03:05).
- **MODO YA Plus** — el local le regala el envío a los clientes con Plus. El
  rider cobra igual: la diferencia sale del fondo de la campaña
  (`pedidos.envio_cubierto` y la fila en `campania_gastos`).

El fondo se termina y la campaña queda `sin_fondo` sola: nadie paga de más ni
hay que acordarse de apagarla. `fondo_disponible()` descuenta lo ya gastado y
`rendimiento_campania()` devuelve lo que se ve en el panel (ingresos, pedidos,
costo y retorno por peso invertido).

**El cliente paga la mensualidad de Plus** (`tarifarios.precio_plus_mensual`,
$2.500) con la misma pantalla de tarjeta que el pedido, y durante 30 días no
paga envío en los locales adheridos. `cotizar_para_cliente` ya devuelve
`costo_envio` en 0, más `costo_envio_real`, `envio_gratis`, `local_adherido` y
`tiene_plus`, así el carrito puede decirle cuánto se ahorraría si se suscribe.

La plata de las campañas **se descuenta en la liquidación del local**, igual que
la mensualidad: es gasto suyo, no de MODO YA. `tests/campanias.sql` recorre el
circuito entero (fondo, envío cubierto, publicidad diaria, cierre por falta de
fondo y el descuento en la liquidación).

## Plus se renueva solo

Al vencerse, se le vuelve a cobrar con la tarjeta que dejó guardada. Lo maneja
el cron **`renovar-plus`** (07:10 UTC, 04:10 de Argentina):

1. `plus_por_renovar()` arma la lista del día: la última suscripción de cada
   cliente que ya se venció, con `renovar = true` y una tarjeta guardada.
2. Si hay alguien, `renovar_plus_del_dia()` le pega con `pg_net` a la Edge
   Function `pagar-pedido` (acción `renovar_plus`), que es la única que puede
   cobrar. La URL y la clave de servicio salen de **Vault**, no del código:
   las carga `scripts/guardar_secretos.ps1` leyéndolas de la Management API.
3. Cobrada, `activar_plus()` suma **un mes**, no 30 días: el que se suscribió un
   25 se le cobra todos los 25 (0043). Si la tarjeta rebota se anota el motivo y
   **al tercer intento se deja de insistir**: el cliente renueva a mano y ve el
   porqué en la pantalla de Plus.

**La suscripción se renueva sola desde el día uno**: el cliente no prende nada.
Lo único que tiene es la baja (`cortar_renovacion_plus`), que le deja los días
que ya pagó y no le vuelve a cobrar; si se arrepiente, al reactivarla se le
perdonan los rechazos anteriores. `tests/renovacion_plus.sql` cubre a quién le
toca, a quién no, y que el día del mes no se corra.

> Cobrar una tarjeta guardada sin pedir el código de seguridad es lo que
> Mercado Pago llama pago recurrente: se pide un token con el `card_id` y se
> cobra con ese token. Hace falta tenerlo habilitado en la cuenta.

## Promociones del local

El local baja el precio de **todo su menú**, de **las secciones que elija** o de
**productos sueltos**, con fecha de fin opcional y, si quiere, solo ciertos días
("martes de pizza"). A diferencia de una campaña, acá no se le paga nada a MODO
YA: el descuento sale de su propio precio, y como la liquidación se arma con lo
que realmente se vendió (`pedidos.subtotal`), se descuenta solo.

**El precio con descuento lo calcula la base.** `promociones_del_local()` le da
a la app los productos que hoy tienen promoción, y `crear_pedido` lo vuelve a
calcular antes de cobrar: una app vieja o modificada no puede inventarse un
precio. El renglón del pedido guarda `precio_lista` y `promocion_id`, así un
pedido de hace un mes sigue diciendo con qué promo se hizo.

Si dos promociones tocan el mismo producto gana la que más descuenta. El
descuento es sobre el producto, no sobre los agregados: la muzzarella con 20%
sigue cobrando el extra de jamón completo. `v_comercios.descuento` es el mejor
porcentaje vigente, que la vidriera muestra como "20% OFF".

`tests/promociones.sql` recorre el circuito entero (13 comprobaciones: alcances,
días, vencimiento, pausa, cuál gana, el precio cobrado y la liquidación).

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

**`tests/campanias.sql`** — campañas del local, envío gratis con Plus,
publicidad cobrada una vez por día y lo que termina en la liquidación.

**`tests/promociones.sql`** — descuentos del local: los tres alcances, los días,
vencida y pausada, cuál gana cuando hay dos, el precio que realmente se cobra y
cómo queda la liquidación.

**`tests/renovacion_plus.sql`** — a quién le toca renovar Plus hoy (y a quién
no), los tres intentos y el interruptor del cliente.

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

## Que no se pause el proyecto

El plan gratuito de Supabase pausa el proyecto a los 7 días sin actividad, y
despausarlo es a mano desde el panel. Los cron de la base corren *adentro* de
Postgres y no cuentan: hace falta una petición que entre por la API.

La hace el workflow **`.github/workflows/mantener-viva.yml`**, todos los días:
pide una fila de `ciudades` con la clave publicable y falla ruidosamente si no
responde 200. No escribe nada.

> GitHub apaga los workflows programados si el repositorio pasa 60 días sin
> commits (avisa por mail y se reactiva con un click).

## Pendiente

- **Custom Access Token Hook** para llevar el rol en el JWT. Hoy las políticas
  lo leen de `perfiles` con funciones `security definer`, que funciona bien; el
  hook ahorraría una consulta por request.
- **Zonas de cobertura**: la tabla existe, falta cargar el polígono de Malargüe
  y rechazar destinos fuera del área.
