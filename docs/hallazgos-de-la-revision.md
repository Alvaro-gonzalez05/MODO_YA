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

### 1. "Transferencia" promete un alias que nunca se muestra

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

### 2. Se le promete al cliente un reembolso que ningún flujo puede hacer

`pedido_seguimiento_page.dart:89`, `:90` y `:258` dicen "Te devolvemos el
dinero". El valor `'reembolsado'` del enum `estado_pago` no se escribe en ningún
lado, no hay RPC de devolución, y `admin/pedidos_pago_page.dart` solo sabe
marcar "Cobrado". El comentario de `0013_pedidos.sql:486` decía que dependía de
la pasarela "que todavía no está definida", pero la pasarela ya está (0032-0045).

**Reproducir:** pedido pagado con tarjeta → el local lo rechaza → el cliente lee
que le devuelven la plata y no hay pantalla ni función para devolverla, ni
siquiera para registrar que se devolvió por afuera.

### 3. Un pedido con tarjeta abandonado no se puede volver a pagar

La ruta `/cliente/pagar/:id` tiene **un solo enlace en toda la app**:
`carrito_page.dart:58`, justo después de crear el pedido. Desde "Mis pedidos" se
va a `/cliente/pedidos/:id`, que solo ofrece "Cancelar pedido"
(`pedido_seguimiento_page.dart:251-273`). La migración `0034_reintentar_el_pago.sql`
diseñó el reintento a propósito ("puede pagar con otra tarjeta"), pero solo
funciona si el cliente no se va de esa pantalla.

**Reproducir:** elegir "Tarjeta" → cerrar la app en la pantalla de pago → volver
a "Mis pedidos" → el pedido queda "Esperando pago" sin forma de pagarlo. A la
media hora lo cierra `cerrar_pagos_vencidos()`.

### 4. Guardar tarifas resetea en silencio el precio de MODO YA Plus

`admin_nuevo_tarifario` (`0016_permisos_por_columna.sql:212-220`) hace un
`insert` con las columnas nombradas una por una, y **no incluye
`precio_plus_mensual`** — columna agregada después en `0036_campanias_y_plus.sql:119`
con `not null default 2500`. `precio_plus()` lee justamente esa columna, y es el
importe que el cliente ve y paga.

**Reproducir:** poner `precio_plus_mensual = 4000` → el cliente ve "Suscribirme
por $4.000" → la administración toca cualquier cosa en `/admin/tarifas` y guarda
→ el tarifario nuevo nace con 2500 → el precio de Plus baja a $2.500 sin que
nadie lo pida ni se entere.

### 5. El precio de Plus no se puede cambiar desde ninguna pantalla

`admin/tarifas_page.dart:61-122` expone seis campos y ninguno es el precio de
Plus. El comentario de `0039:19` dice "lo fija la administración en el
tarifario", pero hoy solo se puede tocar con SQL a mano.

Ojo con un parecido: `Tarifario.precioSuscripcionMensual`
(`tarifas_repository.dart:36`) es **otra** columna (`precio_suscripcion_mensual`,
de 0003, la mensualidad del local) y tampoco la lee nadie.

---

## Media

### 6. Reclamos: backend completo, cero pantallas

Existe la tabla `reclamos`, el `grant insert` para que un usuario abra uno, el
trigger `completar_reclamo` y la RPC `admin_resolver_reclamo`. La palabra
"reclamo" **no aparece en ningún archivo `.dart`** de las tres apps. Nadie puede
abrir un reclamo ni resolverlo.

### 7. Documentación del rider: permisos y semilla, ninguna pantalla

`documentos_exigidos` se siembra por vehículo (`0007_semilla.sql:42`),
`documentos_repartidor` tiene grants para que el rider suba sus archivos
(`0016:43-48`) y existe `admin_validar_documento`. No hay una sola referencia en
Dart: el rider nunca sube nada y la administración lo aprueba a ciegas.

### 8. Las liquidaciones son invisibles para quien las cobra

El RLS ya habilita al rider a leer sus `liquidaciones` y al local sus
`liquidaciones_comercio` y `cargos_comercio`, pero no hay pantalla en
`apps/repartidor` ni en `features/comercio`
(`liquidaciones_repository.dart:162`: "Todo esto lo usa solo la administración").

Peor: `apps/repartidor/lib/features/ganancias_page.dart:9-10` y `:64` siguen
diciendo que la liquidación *"todavía no está definida"* / *"se están
definiendo"*. Ese texto es anterior a la migración 0035 y hoy es falso. El local
tampoco ve nunca la mensualidad ni la publicidad que se le descuenta.

### 9. El panel de administración muestra ceros y "Todo en orden" cuando falla

`admin/dashboard_page.dart:17-20` lee los cuatro providers con `.value ?? const []`,
sin `MyAsync`, a diferencia del resto de la app. Si la consulta falla, los
números quedan en 0 y el cartel verde dice "Todo en orden. Si pasa algo que
necesite tu intervención, aparece acá." Además el `onRefresh` (`:79-82`) solo
invalida comercios y riders.

**Reproducir:** cortar la red y entrar a `/admin`: la operación se ve vacía y
sana, sin mensaje de error ni botón de reintentar.

### 10. Un envío puede quedar trabado en `cotizado` sin salida

`envios_repository.dart:88-102` (`crearYBuscar`) llama `crear_envio` y
`confirmar_envio` como **dos RPC sin transacción**. Si la segunda falla, el
envío queda en `cotizado` y no hay ninguna acción para confirmarlo: la bajada
del seguimiento cae en `_ => ''`, `_Progreso` no marca ningún paso, el filtro
"En curso" lo excluye (`esActivo` descarta `cotizado`) y lo único que queda es
"Cancelar envío".

### 11. El buzón de avisos de Mercado Pago no tiene pantalla

`0044_avisos_de_mercado_pago.sql:58-62` crea la política con el comentario "los
mira la administración", pero `mp_notificaciones` no se referencia en Dart. Que
el webhook todavía no *actúe* sobre el pedido está explicado y es intencional;
que nadie pueda *ver* lo que se guardó, no.

### 12. El local ve "$0" como costo del envío en los pedidos con Plus

`comercio/pedidos_local_page.dart:270-273` muestra
`'El envío (${Formato.pesos(pedido.costoEnvio)}) lo cobra MODO YA.'`. Con Plus,
`crear_pedido` guarda `costo_envio = 0` y el importe real va a `envio_cubierto`
— que es plata que se le carga **al propio local** en `campania_gastos`. La
pantalla del cliente sí distingue el caso ("Gratis con Plus"); la del local
afirma un importe falso sobre un gasto que es suyo.

---

## Baja

### 13. Erratas de acentuación y voseo en texto que ve el usuario

El resto de la app está acentuada y vosea, así que son erratas, no una
convención:

- `auth/cuenta_no_habilitada_page.dart:27` — "Tu local no **esta** habilitado"
- `auth/cuenta_no_habilitada_page.dart:23` — "**Entra** con el mismo email"
- `apps/modo_ya/lib/main.dart:95` — "La app no **esta** configurada"
- `apps/repartidor/lib/features/inicio_page.dart:105` — "Tu cuenta **esta** …
  **Hablalo** con la **administracion**."
- `apps/repartidor/lib/features/inicio_page.dart:129` — "**Usa** el centro de
  Malargüe…"

### 14. El botón "Confirmar" del código de entrega queda habilitado y no hace nada

`apps/repartidor/lib/features/servicio_page.dart:296-299`:
`onPressed: () => _c.text.length == 4 ? Navigator.pop(...) : null`. El callback
nunca es `null`, así que el botón siempre se ve activo, y no hay `onChanged` que
lo reevalúe. Con 1 a 3 dígitos el rider toca "Confirmar" y no pasa nada, sin
ningún mensaje.

### 15. `EstadoAprobacion.rechazado` es inalcanzable desde la app

`admin/comercios_page.dart:319-331` y `admin/repartidores_page.dart:315-327`
solo ofrecen `aprobado` y `suspendido`, y el alta crea aprobado. El estado
existe en el enum, tiene label "Rechazado" y lo soporta
`admin_aprobacion_comercio`, pero ninguna pantalla lo puede fijar.

---

## Revisado y descartado

Para que no vuelva a aparecer en el backlog: `sin_repartidor` y el retorno a la
búsqueda están resueltos (`0027:353-355`); el fallback de carteles del home, el
`catch (_) {}` de `catalogo_repository.dart:182` y las baldosas de OpenStreetMap
están explicados en comentarios y son intencionales; la ausencia de "Club MODO
YA" y cupones es una decisión documentada en `home_page.dart:16-19`; y
`activar_plus` y `confirmar_pago_online` no se llaman desde Dart a propósito,
porque las invoca la Edge Function con `service_role`.
