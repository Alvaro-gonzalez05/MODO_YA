# Hallazgos de la revisión de pantallas y flujos

Revisión de código de toda la app buscando pantallas, flujos y funciones a
medio hacer. Cada hallazgo dice cómo reproducirlo o por qué es un problema.

Fecha: 28/09/2026. Nada de esto está arreglado todavía salvo lo que se marque.

Vale una aclaración sobre el estado general: **no hay código a medio escribir**.
No aparecen `TODO`, `UnimplementedError`, botones muertos ni pantallas de
relleno. Lo incompleto de este proyecto está en otro lado: en los **huecos entre
el backend y las pantallas**. Hay funcionalidad construida y probada en la base
que ninguna pantalla expone, y textos en la app que prometen cosas que ningún
flujo puede cumplir.

---

## Alta

### 1. "Transferencia" promete un alias que nunca se muestra — ARREGLADO

`packages/my_core/lib/src/models/estados.dart:134` dice
`transferencia => 'Te pasamos el alias al confirmar'`. No existe ningún CBU ni
alias en el código. Al confirmar, `carrito_page.dart:63-68` muestra "¡Pedido
confirmado!" y manda a seguimiento, y la pantalla de seguimiento no dice nada
del pago. Mientras tanto la base deja `cobrar_al_entregar = 0` para transferencia
(`0031_cobro_al_entregar.sql:17-35`) y `crear_pedido` lo marca `pagado` al
instante (`0040_promociones.sql:288`).

**Reproducir:** carrito → "Transferencia" → Confirmar. El pedido entra a la
cocina como pagado, el rider no cobra nada, y el cliente nunca supo a dónde
transferir.

**Arreglado (0058):** transferencia y efectivo salieron de la pantalla del
cliente y de `crear_pedido`. En la app solo se paga con tarjeta.

### 2. Se le promete al cliente un reembolso que ningún flujo puede hacer — ARREGLADO

`pedido_seguimiento_page.dart:89`, `:90` y `:258` dicen "Te devolvemos el
dinero". El valor `'reembolsado'` del enum `estado_pago` no se escribe en ningún
lado, no hay RPC de devolución, y `admin/pedidos_pago_page.dart` solo sabe
marcar "Cobrado". El comentario de `0013_pedidos.sql:486` decía que dependía de
la pasarela "que todavía no está definida", pero la pasarela ya está (0032-0045).

**Reproducir:** pedido pagado con tarjeta → el local lo rechaza → el cliente lee
que le devuelven la plata y no hay pantalla ni función para devolverla, ni
siquiera para registrar que se devolvió por afuera.

**Arreglado (0060):** al rechazar un pedido cobrado se le devuelve el 100% al
cliente (cron `reembolsar-pedidos` + Edge Function `reembolsar`) y se le cobra
la penalidad al local, que aparece en la liquidación.

### 3. Un pedido con tarjeta abandonado no se puede volver a pagar — ARREGLADO

La ruta `/cliente/pagar/:id` tiene **un solo enlace en toda la app**:
`carrito_page.dart:58`, justo después de crear el pedido. Desde "Mis pedidos" se
va a `/cliente/pedidos/:id`, que solo ofrece "Cancelar pedido"
(`pedido_seguimiento_page.dart:251-273`). La migración `0034_reintentar_el_pago.sql`
diseñó el reintento a propósito ("puede pagar con otra tarjeta"), pero solo
funciona si el cliente no se va de esa pantalla.

**Reproducir:** elegir "Tarjeta" → cerrar la app en la pantalla de pago → volver
a "Mis pedidos" → el pedido queda "Esperando pago" sin forma de pagarlo. A la
media hora lo cierra `cerrar_pagos_vencidos()`.

**Arreglado:** el seguimiento del pedido muestra "Pagar $X" cuando quedó
esperando el pago, y el texto dejó de decirle que esperara.

### 4. Guardar tarifas resetea en silencio el precio de MODO YA Plus — ARREGLADO

> Arreglado en `0049_el_precio_de_plus_no_se_pierde.sql`: el parámetro ahora
> existe y, si no viene, se conserva el valor del tarifario que se cierra (que
> es lo que importaba: el bug no era mandar un valor equivocado, era no mandar
> ninguno). Cubierto por `tests/tarifario.sql`.


`admin_nuevo_tarifario` (`0016_permisos_por_columna.sql:212-220`) hace un
`insert` con las columnas nombradas una por una, y **no incluye
`precio_plus_mensual`** — columna agregada después en `0036_campanias_y_plus.sql:119`
con `not null default 2500`. `precio_plus()` lee justamente esa columna, y es el
importe que el cliente ve y paga.

**Reproducir:** poner `precio_plus_mensual = 4000` → el cliente ve "Suscribirme
por $4.000" → la administración toca cualquier cosa en `/admin/tarifas` y guarda
→ el tarifario nuevo nace con 2500 → el precio de Plus baja a $2.500 sin que
nadie lo pida ni se entere.

### 5. El precio de Plus no se puede cambiar desde ninguna pantalla — ARREGLADO

> Arreglado junto con el 4: ahora es un campo más en Admin → Tarifas y reglas
> ("MODO YA Plus · lo que paga el cliente por mes para no pagar envío"). Los
> dos iban juntos: sin el 4, poner un precio desde la pantalla lo habría
> borrado el siguiente guardado.


`admin/tarifas_page.dart:61-122` expone seis campos y ninguno es el precio de
Plus. El comentario de `0039:19` dice "lo fija la administración en el
tarifario", pero hoy solo se puede tocar con SQL a mano.

Ojo con un parecido: `Tarifario.precioSuscripcionMensual`
(`tarifas_repository.dart:36`) es **otra** columna (`precio_suscripcion_mensual`,
de 0003, la mensualidad del local) y tampoco la lee nadie.

---

## Media

### 6. Reclamos: backend completo, cero pantallas — ARREGLADO

Existe la tabla `reclamos`, el `grant insert` para que un usuario abra uno, el
trigger `completar_reclamo` y la RPC `admin_resolver_reclamo`. La palabra
"reclamo" **no aparece en ningún archivo `.dart`** de las tres apps. Nadie puede
abrir un reclamo ni resolverlo.

**Arreglado:** el cliente abre un reclamo desde el seguimiento del pedido o
desde "Mi cuenta → Mis reclamos"; el local desde "Mi local → Reclamos" y el
rider desde "Perfil → Mis reclamos". La administración los ve, los toma, los
responde y los cierra en `/admin/reclamos`, con contador en la barra lateral.

Dos cosas que faltaban en la base y se agregaron en `0066`: `reclamos` solo
podía apuntar a un `envio_id`, y el envío del pedido recién existe cuando el
local lo acepta, así que un reclamo de un pedido rechazado no se podía atar a
nada (ahora hay `pedido_id`); y nada controlaba que el pedido o el envío fueran
del que reclama (ahora sí, con el trigger `reclamos_de_lo_mio`).

### 7. Documentación del rider: permisos y semilla, ninguna pantalla — ARREGLADO

`documentos_exigidos` se siembra por vehículo (`0007_semilla.sql:42`),
`documentos_repartidor` tiene grants para que el rider suba sus archivos
(`0016:43-48`) y existe `admin_validar_documento`. No hay una sola referencia en
Dart: el rider nunca sube nada y la administración lo aprueba a ciegas.

**Arreglado:** el rider ve en "Perfil → Mi documentación" qué se le pide según
su vehículo, saca la foto y la sube al bucket privado `documentos`; el inicio le
avisa mientras le falte algo. La administración la revisa en la ficha del rider,
donde aprueba o rechaza cada documento con un motivo que el rider lee en su app.

Faltaba un paso en la base, agregado en `0066`: el rider puede escribir
`archivo_url` pero no `estado`, así que un documento rechazado seguía rechazado
aunque volviera a subir la foto buena. Ahora cambiar el archivo lo devuelve a
'pendiente' (trigger `documentos_repartidor_a_revision`).

### 8. Las liquidaciones son invisibles para quien las cobra — ARREGLADO

> **Arreglado (0065).** Las funciones de liquidación aceptan ahora al dueño de
> los datos además del admin, así que el rider y el local leen **el mismo
> documento** que mira la administración: el resumen del período, el renglón
> por renglón, los descuentos y el neto, más el historial de lo ya cerrado y el
> PDF. La hoja y su PDF se movieron a `my_ui` / `my_core` para que no haya un
> segundo renderizador ni un segundo cálculo. `tests/mi_liquidacion.sql` prueba
> que nadie vea la liquidación de otro.
>
> Al local le aparecen todos sus descuentos juntos —mensualidad, publicidad,
> penalidad por rechazar un pedido cobrado y los envíos que regaló con Plus—,
> que es lo que hace que el número le cierre. El texto falso de
> `ganancias_page.dart` salió; lo que no se promete es **cada cuánto** se paga,
> porque eso lo decide una persona al cerrar el período y no hay nada en el
> código que lo fije.

El RLS ya habilita al rider a leer sus `liquidaciones` y al local sus
`liquidaciones_comercio` y `cargos_comercio`, pero no hay pantalla en
`apps/repartidor` ni en `features/comercio`
(`liquidaciones_repository.dart:162`: "Todo esto lo usa solo la administración").

Peor: `apps/repartidor/lib/features/ganancias_page.dart:9-10` y `:64` siguen
diciendo que la liquidación *"todavía no está definida"* / *"se están
definiendo"*. Ese texto es anterior a la migración 0035 y hoy es falso. El local
tampoco ve nunca la mensualidad ni la publicidad que se le descuenta.

### 9. El panel de administración muestra ceros y "Todo en orden" cuando falla — ARREGLADO

`admin/dashboard_page.dart:17-20` lee los cuatro providers con `.value ?? const []`,
sin `MyAsync`, a diferencia del resto de la app. Si la consulta falla, los
números quedan en 0 y el cartel verde dice "Todo en orden. Si pasa algo que
necesite tu intervención, aparece acá." Además el `onRefresh` (`:79-82`) solo
invalida comercios y riders.

**Reproducir:** cortar la red y entrar a `/admin`: la operación se ve vacía y
sana, sin mensaje de error ni botón de reintentar.

**Arreglado:** `resumenAdminProvider` junta las cinco consultas del panel en un
solo `AsyncValue`, así que si cualquiera falla se ve el cartel de error con
"Reintentar" en vez de ceros y "Todo en orden". Si ya había datos cargados se
siguen mostrando, que es la política del resto de la app. Probado en
`apps/modo_ya/test/resumen_admin_test.dart`.

### 10. Un envío puede quedar trabado en `cotizado` sin salida — ARREGLADO

`envios_repository.dart:88-102` (`crearYBuscar`) llama `crear_envio` y
`confirmar_envio` como **dos RPC sin transacción**. Si la segunda falla, el
envío queda en `cotizado` y no hay ninguna acción para confirmarlo: la bajada
del seguimiento cae en `_ => ''`, `_Progreso` no marca ningún paso, el filtro
"En curso" lo excluye (`esActivo` descarta `cotizado`) y lo único que queda es
"Cancelar envío".

**Arreglado (0067).** Tres salidas: `pedir_envio` crea y confirma en una sola
transacción, así que el hueco no se vuelve a abrir; el seguimiento del local
explica el estado y ofrece "Buscar rider ahora"; y el cron `vencer-cotizados`
cancela los de cadetería con más de 15 minutos parados.

Cancela y no confirma solo, porque confirmar sería mandarle un rider al local
por un viaje que no sabe que existe y que alguien tiene que pagar. El cron mira
solo `pedido_id is null`: el envío de un pedido espera en `cotizado` **a
propósito** mientras el local cocina, y un cron ciego habría cancelado pedidos
pagos en el horno. Probado en `tests/envio_cotizado.sql`.

### 11. El buzón de avisos de Mercado Pago no tiene pantalla — ARREGLADO

`0044_avisos_de_mercado_pago.sql:58-62` crea la política con el comentario "los
mira la administración", pero `mp_notificaciones` no se referencia en Dart. Que
el webhook todavía no *actúe* sobre el pedido está explicado y es intencional;
que nadie pueda *ver* lo que se guardó, no.

**Arreglado:** `mostrarAvisosDeMercadoPago` muestra lo que hay en
`mp_notificaciones` — acción, recurso, y si la firma vino verificada, inválida o
sin clave para verificar, porque un aviso con firma inválida no lo mandó
Mercado Pago. Se despliega el JSON crudo con botón de copiar.

Quedó como panel desde la pantalla de cobros y no como sección del menú: cuando
un cobro no cerró, lo primero que se quiere mirar es qué dijo Mercado Pago.

### 12. El local ve "$0" como costo del envío en los pedidos con Plus — ARREGLADO

`comercio/pedidos_local_page.dart:270-273` muestra
`'El envío (${Formato.pesos(pedido.costoEnvio)}) lo cobra MODO YA.'`. Con Plus,
`crear_pedido` guarda `costo_envio = 0` y el importe real va a `envio_cubierto`
— que es plata que se le carga **al propio local** en `campania_gastos`. La
pantalla del cliente sí distingue el caso ("Gratis con Plus"); la del local
afirma un importe falso sobre un gasto que es suyo.

---

**Arreglado:** `Pedido.envioReal` y `Pedido.envioLoPoneElLocal`. El local lee
"El envío ($4.200) lo ponés vos con tu campaña Plus: se te descuenta de tus
ventas" en lugar de "$0", y el seguimiento del cliente dice "Gratis con Plus"
igual que la pantalla de pago. Probado en
`apps/modo_ya/test/pedido_del_local_test.dart`.

## Baja

### 13. Erratas de acentuación y voseo en texto que ve el usuario — ARREGLADO

El resto de la app está acentuada y vosea, así que son erratas, no una
convención:

- `auth/cuenta_no_habilitada_page.dart:27` — "Tu local no **esta** habilitado"
- `auth/cuenta_no_habilitada_page.dart:23` — "**Entra** con el mismo email"
- `apps/modo_ya/lib/main.dart:95` — "La app no **esta** configurada"
- `apps/repartidor/lib/features/inicio_page.dart:105` — "Tu cuenta **esta** …
  **Hablalo** con la **administracion**."
- `apps/repartidor/lib/features/inicio_page.dart:129` — "**Usa** el centro de
  Malargüe…"

**Arreglado:** las cinco del documento más veinte encontradas barriendo los
literales de las dos apps. Las que más pesaban estaban en
`packages/my_core/lib/src/backend.dart`: **todos** los mensajes de error que ve
el usuario iban sin tildes y sin voseo. También el validador que usan todos los
formularios y los botones que el rider toca todo el día.

### 14. El botón "Confirmar" del código de entrega queda habilitado y no hace nada — ARREGLADO

`apps/repartidor/lib/features/servicio_page.dart:296-299`:
`onPressed: () => _c.text.length == 4 ? Navigator.pop(...) : null`. El callback
nunca es `null`, así que el botón siempre se ve activo, y no hay `onChanged` que
lo reevalúe. Con 1 a 3 dígitos el rider toca "Confirmar" y no pasa nada, sin
ningún mensaje.

**Arreglado:** el botón se habilita recién con los cuatro dígitos. El mismo
error estaba en `pedirTexto`, el diálogo compartido que usan el local para
cancelar un envío y la administración para rechazar un pedido, y se arregló
igual. Al escribir ese test apareció otro, preexistente: `pedirTexto` liberaba
el controlador del campo antes de que terminara la animación de salida y
rompía. Probado en `apps/repartidor/test/codigo_de_entrega_test.dart` y
`packages/my_ui/test/pedir_texto_test.dart`.

### 15. `EstadoAprobacion.rechazado` es inalcanzable desde la app — ARREGLADO A MEDIAS

`admin/comercios_page.dart:319-331` y `admin/repartidores_page.dart:315-327`
solo ofrecen `aprobado` y `suspendido`, y el alta crea aprobado. El estado
existe en el enum, tiene label "Rechazado" y lo soporta
`admin_aprobacion_comercio`, pero ninguna pantalla lo puede fijar.

**Arreglado del lado del rider**, que es donde el rechazo tiene sentido natural:
la revisión de la documentación rechaza cada documento con una observación que
el rider lee (`admin_validar_documento` con `'rechazado'`), y la ficha de un
rider en revisión ofrece "No aprobar" pidiendo el motivo
(`admin_aprobacion_repartidor` con `'rechazado'`).

**Falta el local:** `admin/comercios_page.dart` sigue ofreciendo solo aprobar y
suspender. Es el mismo arreglo de tres líneas, pero se dejó afuera para no
pisar un archivo de otra tanda de trabajo.

---

## Revisado y descartado

Para que no vuelva a aparecer en el backlog: `sin_repartidor` y el retorno a la
búsqueda están resueltos (`0027:353-355`); el fallback de carteles del home, el
`catch (_) {}` de `catalogo_repository.dart:182` y las baldosas de OpenStreetMap
están explicados en comentarios y son intencionales; la ausencia de "Club MODO
YA" y cupones es una decisión documentada en `home_page.dart:16-19`; y
`activar_plus` y `confirmar_pago_online` no se llaman desde Dart a propósito,
porque las invoca la Edge Function con `service_role`.
