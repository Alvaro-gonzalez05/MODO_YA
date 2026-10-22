# Segunda auditoría — 21 de octubre de 2026

Revisión de solo lectura hecha después de cerrar los 5 hallazgos de severidad
alta de `hallazgos-de-la-revision.md`. Son hallazgos **nuevos**: ninguno repite
los de aquel documento.

**Contexto que importa para leer esto:** el cobro real nunca se encendió.
Ninguna versión publicada contiene la clave pública de producción, así que todo
lo instalado simula el pago. Nada de lo que está acá le hizo daño a nadie
todavía — pero varios son exactamente el tipo de error que no se nota hasta que
hay plata real de por medio.

**Estado al 22/10/2026:** 4 de 13 arreglados (B3, C1, C2, C3). Los 9 que quedan
abiertos no se tocaron por decisión del proyecto: los tres de pagos (A1, A2, A3)
porque Mercado Pago está en pausa, y el resto porque nadie los tomó todavía.
**Los tres de pagos bloquean encender el cobro real.**

Cada hallazgo dice si está **verificado** (lo comprobé contra el código o la
base) o **sin verificar** (viene del informe de la auditoría y es creíble, pero
no lo chequeé renglón por renglón).

---

## Bloquean encender el cobro real

### A1. Un pago "en revisión" se cobra y nunca se devuelve — *sin verificar*

Cuando el banco deja un pago en revisión, Mercado Pago devuelve `processing` y
el pago queda `pendiente`. A partir de ahí no hay camino de vuelta:

- `cerrar_pagos_vencidos()` cancela el pedido a los 30 minutos con un `update`
  crudo que **no pasa por `cancelar_pedido`**, así que no dispara el reembolso.
- Los dos disparadores de devolución (`rechazar_pedido`, `cancelar_pedido`)
  exigen que el pago esté `acreditado`. Uno `pendiente` no califica.
- El webhook **solo guarda** en `mp_notificaciones`. Nadie lee esa tabla.
  (Esto último sí está verificado.)

Resultado: el cliente queda cobrado, sin pedido y sin devolución. La app le
dijo "Te avisamos apenas se confirme", que es una promesa que ningún código
puede cumplir hoy.

### A2. La renovación de Plus cobrada y no activada se vuelve a cobrar todos los días — *sin verificar*

Si el cobro sale bien pero `activar_plus` falla, el `catch` no toca
`intentos_fallidos` a propósito ("sería contarle un rechazo que no existió").
Pero ese contador es lo único que acota los reintentos, y la suscripción sigue
vencida: mañana el cron la cobra de nuevo. La clave de idempotencia es la misma
todos los días, así que o se cobra de más o nunca se activa. El único rastro es
un `console.error`.

### A3. Dos toques de "Pagar" pueden generar dos cobros — *sin verificar*

La clave de idempotencia se deriva del token de la tarjeta, y se pide un token
nuevo en cada intento: dos intentos = dos claves = dos órdenes. El mensaje "El
banco está revisando el pago" se muestra en la tarjeta **roja de error** con el
botón habilitado, así que el cliente lo lee como un fallo y vuelve a tocar.

---

## Plata del local y del cliente

### B1. Se le cobra al local el envío de pedidos que nunca existieron — *verificado*

Con Plus, el gasto del envío se asienta en `campania_gastos` **cuando el pedido
todavía está en `pendiente_pago`**. Si el pedido se cancela, se rechaza o vence,
el gasto queda.

`campania_gastos` **nunca se borra** en ninguna migración, y la columna tiene
`check (monto > 0)`, así que tampoco se puede asentar una fila negativa para
compensar — a diferencia de `cargos_comercio`, que admite negativos a propósito.
Repetir la secuencia vacía el presupuesto de Plus de cualquier local adherido.

### B2. El carrito promete "Gratis con Plus" y la pantalla de pago cobra el envío entero — *verificado*

El mismo número con dos reglas distintas:

- `cotizar_para_pedido` (el carrito): gratis si la campaña tiene **algo** de
  fondo (`campania_plus_activa` solo exige `fondo_disponible > 0`).
- `crear_pedido`: exige `fondo_disponible(camp) >= cot.total`. Si no alcanza,
  descarta la campaña y cobra el envío completo, **sin avisar**.

Con $500 de fondo y un envío de $2.500, el cliente ve "Gratis con Plus",
confirma, y en la pantalla siguiente el total subió $2.500 sin explicación.
No es una carrera: pasa siempre.

### B3. "Pedidos por cobrar" de la administración puede hacer que se cobre dos veces — *verificado* — **ARREGLADO**

La pantalla quedó como antes de la migración `0058` (solo tarjeta). Su filtro es
`pago_estado = 'pendiente'`, que ahora significa **todo pedido nuevo mientras el
cliente carga la tarjeta**. El vacío dice "Cada pedido nuevo aparece acá hasta
que registres el cobro", o sea que invita a hacerlo, y el diálogo ofrece
`MetodoPago.values` entero, incluido efectivo.

Si se marca como cobrado en efectivo, el trigger `copiar_cobro_del_pedido` pone
`cobrar_al_entregar = total` y el rider sale a cobrar en la puerta un pedido que
el cliente quizá ya pagó.

---

**Arreglado.** El filtro excluye ahora `pendiente_pago`, así que un pedido nuevo
no aparece mientras el cliente carga la tarjeta. El diálogo ofrece solo el medio
que el cliente eligió más "Otro (entró por fuera de la app)", de modo que ya no
se puede marcar en efectivo un pedido pagado con tarjeta — que era lo que
disparaba `copiar_cobro_del_pedido` y mandaba al rider a cobrar en la puerta.
Los tres textos se reescribieron: dejaron de nombrar efectivo, posnet y
transferencia, y el vacío dejó de invitar al error. Probado en
`tests/cobros_sin_registrar.sql` y `apps/modo_ya/test/cobros_sin_registrar_test.dart`.

Los pedidos viejos colgados (P-1022 y P-1065) siguen listados a propósito: es
justamente para lo que sirve la pantalla. Se cierran a mano con "Cobrado" o
"Cancelar", y como su pago está en `pendiente` y no en `acreditado`, cancelarlos
no dispara ningún reembolso.

## El rider

### C1. El rider no tiene forma de bajarse de un envío — *verificado* — **ARREGLADO**

En `0061` se construyó `abandonar_envio()` y en la misma migración se le sacó al
rider el permiso de `cancelar_envio`. Pero `abandonar_envio` **no se llama desde
ningún archivo Dart**: se cerró la puerta vieja y nunca se abrió la nueva.

Hoy, si un rider no puede completar un envío, el envío se queda con él. De
arrastre: `abandonos_envio` nunca tiene filas, la vista `v_abandonos` y
`watchAbandonos` devuelven siempre vacío, y el concepto `'abandono'` de
`cargos_repartidor` no tiene de dónde salir.

**Arreglado.** El rider tiene "No puedo seguir con este envío" en `asignado` y
`en_local` (desde `retirado` la base lo rebota, así que no se le ofrece un botón
que va a fallar). Pide el motivo, sin el cual no se puede confirmar, porque es
lo único que después lee la administración para decidir si corresponde un cargo.
El aviso dice que "te **puede** cobrar un cargo", a propósito: 0062 establece que
lo decide una persona. No se tocó nada de 0061. Probado en
`apps/repartidor/test/bajarse_del_envio_test.dart`.

### C2. La liquidación cerrada del rider no muestra los ajustes — *verificado* — **ARREGLADO**

`Liquidacion.deRider` lee `ganancias`, `efectivo_cobrado` y `total`, pero nunca
`ajustes`. Desde `0062` el total es `ganancias − efectivo_cobrado − ajustes`.

Un rider con $10.000 ganados, $2.000 de efectivo y $4.000 de cargos ve
"ganó $10.000 · efectivo $2.000" y al lado un saldo de $4.000: faltan $4.000 sin
explicación, en la única pantalla que le queda del pago ya hecho.

**Arreglado.** `Liquidacion.ajustes` se lee y se muestra en el cierre de la hoja,
en el historial de la administración y en el del rider, así que la resta da el
total que está guardado.

### C3. La hoja y el PDF listan cargos ya liquidados que el total no cuenta — *sin verificar* — **ARREGLADO**

`watchCargosRider` trae **todos** los cargos del rider, sin filtrar por
liquidación, y la hoja los recorta por fecha en Dart. Un cargo ya liquidado
vuelve a listarse en un período viejo, pero el renglón de cierre no lo cuenta.
Es justo lo que `0063` se propuso evitar al poner el detalle en una función que
repite el filtro del resumen.

**Arreglado.** La hoja ya no lee todos los cargos para recortarlos por fecha en
la app: los trae `cargos_a_liquidar_rider`, que repite el mismo filtro del
resumen (`liquidacion_id is null` más el rango). Un cargo ya liquidado dejó de
listarse en un período viejo. Hay un test que compara el total de los renglones
contra el `cargos` del resumen.

### C4. "Mis ganancias" muestra lo ganado y nada de lo que se le descuenta — *sin verificar*

Suma solo la ganancia de los entregados: no resta el efectivo juntado en la
puerta ni los cargos. Con dos mandados en el día el cartel dice "HOY $6.000"
cuando la liquidación va a dar negativa y el rider es el que tiene que poner
plata. Además la semana se calcula sobre los últimos 100 envíos, así que una
semana cargada subcuenta sin decirlo.

---

## Menores

### D1. No hay forma de devolverle plata a un local desde la pantalla — *sin verificar*

El monto se parsea borrando el signo, así que no se puede cargar un ajuste
negativo. El esquema sí lo contempla ("Negativo: se le suma") y el formulario
del rider sí lo permite. Si un local reclama una penalidad con razón, hay que
entrar por SQL.

### D2. Borrar un cargo de un local no tiene el guard de "ya liquidado" — *sin verificar*

Para riders, la base exige `liquidacion_id is null` y revienta si no. Para
locales el borrado va directo a la tabla, protegido solo por que la interfaz
esconde el botón.

### D3. `confirmar_entrega` no mira el estado: repetirla infla `viajes_completados` — *sin verificar*

Si el envío ya está `entregado`, el trigger de transiciones no se dispara
(el estado no cambia), no se valida nada y el contador se incrementa de nuevo.

---

## Revisado y descartado

Lo que la auditoría miró y encontró bien, para no volver a gastar tiempo ahí:

- **Zonas horarias en la plata:** `0046` reemplazó `::date` por `public.dia()`
  en todas las funciones de liquidación, y `0062`/`0063` mantuvieron el criterio.
- **Máquinas de estado:** no se puede saltar a un estado ilegal ni revivir un
  pedido cancelado; los triggers de transición lo frenan.
- **Carreras de asignación:** dos riders aceptando la misma oferta, y el local
  cancelando mientras el rider acepta, terminan bien en los dos órdenes.
- **Doble pago en liquidaciones:** ni un envío ni un pedido pueden entrar dos
  veces.
- **Idempotencia del reembolso:** la clave por pago más el filtro
  `reembolsado_en is null` impiden devolver dos veces.
- **Permisos de lo nuevo:** `abandonos_envio` y `cargos_repartidor` tienen RLS
  correcta, y los RPC internos están revocados de `authenticated`.
- **Mandados:** se re-cotizan del lado del servidor y la cuenta del efectivo es
  consistente entre resumen, detalle y cierre.
