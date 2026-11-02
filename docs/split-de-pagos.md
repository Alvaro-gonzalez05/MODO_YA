# Split de pagos con Mercado Pago

Qué haría falta para que la plata de cada pedido le llegue **directo al local**
y MODO YA se quede con su parte en el mismo cobro, en vez de cobrar todo
nosotros y liquidarle al local cada semana.

Fecha: 02/11/2026. Nada de esto está hecho: es el análisis para decidir.

---

## Cómo funciona del lado de Mercado Pago

Mercado Pago lo llama **Split de pagos 1:1** (modelo "Marketplace"). Está
disponible en Argentina.

- **Cada local vincula su cuenta una sola vez** (OAuth). No es una suscripción
  ni algo del cliente: el local toca "Conectar Mercado Pago" en la app, entra a
  Mercado Pago, autoriza a MODO YA y vuelve. Con eso nos queda un token para
  cobrar **en nombre de ese local**.
- El cliente no hace nada distinto: paga con tarjeta como hoy.
- En cada cobro se manda cuánto es para MODO YA (`application_fee` en la API de
  pagos). Mercado Pago le descuenta primero su comisión al local y después la
  nuestra del resto.
- **Es 1 a 1**: un cobro, un local. Repartir un mismo cobro entre varios (por
  ejemplo local + rider) es el modelo 1:N y solo se habilita a cuentas grandes
  hablando con el equipo comercial.

## Lo que cambia en MODO YA

**1. La API de cobro.** Hoy se usa la Orders API (`POST /v1/orders`). La
documentación del split solo habla de Checkout Pro, Checkout API
(`POST /v1/payments`) y Bricks: la Orders API no aparece. Antes de escribir una
línea hay que confirmarlo con Mercado Pago; si no lo soporta, `pagar-pedido`,
`reembolsar` y el webhook pasan a `/v1/payments`. Es el cambio más grande.

**2. La aplicación de Mercado Pago de Carolina** tiene que estar creada como
"Pagos online → Marketplace", con una Redirect URL fija (una Edge Function
nueva, `mp-vincular`). Además del access token hace falta el **client secret**,
que va como secreto de Supabase con `guardar_secreto.ps1`, igual que el resto.

**3. Guardar el token de cada local.** Una tabla nueva sin acceso desde la app
(solo la leen las Edge Functions con la service role). Dura **180 días**: hay
que renovarlo con el `refresh_token` antes de que venza (un cron, como los que
ya hay), o el local tiene que volver a vincular.

**4. La parte de MODO YA en cada pedido** sería: comisión del pedido (hoy 10%)
+ envío (el rider lo cobra de MODO YA, así que esa plata tiene que quedar de
nuestro lado) + lo que el local pone por Plus.

**5. Lo que hoy se descuenta en la liquidación deja de poder descontarse.** Las
penalidades por rechazar o por no aceptar a tiempo (0060, 0076) hoy salen de lo
que le pagamos al local. Con el split el local ya cobró: esas deudas habría que
cobrárselas aparte (o sumarlas a la comisión de los pedidos siguientes).

**6. Devoluciones.** Mercado Pago las reparte **proporcional** entre el local y
MODO YA. Si el local ya retiró la plata y no tiene saldo, no se puede devolver
el total desde nuestro lado: devolvemos nuestra parte y lo demás queda a cargo
del local.

## Requisitos para cada local

- Cuenta de Mercado Pago de vendedor, con la identidad validada.
- Que la vincule desde la app. Un local sin vincular no podría vender con el
  split; habría que decidir si sigue con el sistema actual (cobra MODO YA y se
  liquida) mientras tanto. Lo razonable es que convivan los dos.

## Lo que sí conviene

- El local ve la plata de cada venta en su Mercado Pago, sin esperar la
  liquidación semanal.
- MODO YA deja de tener en su cuenta plata que no es suya (menos riesgo
  impositivo y menos trabajo de transferencias).

## Para probarlo sin riesgo

1. Confirmar con Mercado Pago si la Orders API acepta el split.
2. En la aplicación de MODO YA, pasarla a modelo Marketplace y cargar la
   Redirect URL.
3. Hacer el vínculo (OAuth) con **una cuenta de prueba** de vendedor, desde un
   local de prueba.
4. Cobrar un pedido de $100 con split y ver en las dos cuentas que la plata
   se repartió bien. Devolverlo y ver que se descuente proporcional.

Fuentes: documentación de Split de pagos 1:1 de Mercado Pago Argentina
(integración, configuración, OAuth y renovación del token).
