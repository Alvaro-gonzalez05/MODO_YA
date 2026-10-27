# Probar Mercado Pago con plata de verdad

Guía para el primer cobro real. La idea es cobrar poco, ver que todo cierre y
devolverlo. Lleva una media hora.

**No hace falta abrir ninguna cuenta nueva en Mercado Pago.** Lo único que
importa es que **el que paga no sea el dueño de la cuenta que cobra**: Mercado
Pago rechaza los pagos en los que comprador y vendedor son la misma persona. Si
la cuenta de Mercado Pago es de Carolina, pagá con tu tarjeta y con una cuenta
de cliente de MODO YA con **tu** email, no con el de ella.

---

## 1. Antes de probar

**Publicar las dos Edge Functions.** La `pagar-pedido` que está en el servidor
es del 28/09 y no tiene la protección contra el doble cobro. La que procesa los
avisos de Mercado Pago (`mp-procesar-avisos`) no está publicada.

```powershell
powershell -NoProfile -Command "& './supabase/scripts/desplegar_funcion.ps1' -Nombre mp-procesar-avisos"
powershell -NoProfile -Command "& './supabase/scripts/desplegar_funcion.ps1' -Nombre pagar-pedido"
```

**Mirar el panel de Mercado Pago** (Tus integraciones → la aplicación de MODO
YA):

- **Credenciales de producción activadas.** Si la aplicación todavía pide
  "Activar credenciales" (rubro, sitio web), los cobros fallan. Es la causa más
  probable de los tres rechazos del 13/10, junto con pagarse a uno mismo.
- **Webhooks en modo productivo**, con la URL
  `https://wqahdncdqnzrusrmdyui.supabase.co/functions/v1/mp-webhook` y el
  evento de órdenes tildado. Esto ya funciona: el 13/10 llegaron tres avisos
  reales con firma válida.
- En **Actividad**, buscá los tres intentos del 13/10 (alrededor de las 14:40):
  el detalle dice por qué rebotaron.

**Un local de prueba.** Desde la app, como administración, dá de alta un local
"Prueba" con horario de 00:00 a 23:59 y un producto de $100. El total va a ser
$100 más el envío (hoy $3.550).

## 2. El cobro

1. Instalá la `v1.15.0` (o la que salga después) en un celular. Las versiones
   anteriores a la 1.15 **no cobran**: simulan el pago.
2. Registrate como cliente con tu email.
3. Guardá una dirección **dentro de Malargüe**. Desde 0071 la app rechaza un pin
   fuera de la ciudad: si probás desde otro lado, mové el pin a Malargüe.
4. Pedí el producto de $100 al local "Prueba" y pagá con tu tarjeta (crédito o
   débito, en una cuota).

Lo que tiene que pasar:

| Dónde | Qué ves |
|---|---|
| La app del cliente | "¡Pedido confirmado!" y el seguimiento |
| La app del local | El pedido entra y suena |
| Mercado Pago → Actividad | El cobro aprobado |
| MODO YA → Administración → Liquidaciones → Avisos de Mercado Pago | Un aviso `order.processed`, firma verificada, con la nota "ya estaba resuelto" |

## 3. La devolución

Entrá como el local "Prueba" y **rechazá el pedido**. En menos de un minuto el
cron `reembolsar-pedidos` le devuelve el 100% al cliente.

| Dónde | Qué ves |
|---|---|
| La app del cliente | El pedido dice que se devuelve la plata |
| Mercado Pago → Actividad | El cobro como "Devuelto" |
| MODO YA → Avisos | Un aviso de devolución con la nota "ya estaba devuelto" |

La plata vuelve a la tarjeta en los días que tarde el banco. Al local "Prueba"
le queda cargada la penalidad por rechazar: borrala desde Liquidaciones →
Cargos, o borrá el local.

## 4. Opcional: MODO YA Plus

Suscribite a Plus con la misma tarjeta ($2.500). Tiene que quedar activo en el
momento. Para devolverlo, hacelo desde el panel de Mercado Pago: el aviso llega
y el pago queda como devuelto (si devolvés una parte, queda anotada la parte).

La **renovación automática** de Plus no se puede probar todavía: necesita que
Mercado Pago habilite los cobros recurrentes (Card on File MIT) para la cuenta.
Hay que pedírselo.

## Si algo falla

- **El cliente ve "No se pudo procesar la tarjeta"**: mirá el log de
  `pagar-pedido` en Supabase (Edge Functions → pagar-pedido → Logs). Ahí está la
  respuesta cruda de Mercado Pago.
- **El pago queda "en revisión"**: no hagas nada. `mp-procesar-avisos` le
  pregunta a Mercado Pago cada 10 minutos y lo resuelve solo; si el banco no lo
  aprueba en un día, el pedido se cancela y, si la plata entró igual, se
  devuelve.
- **El pago queda `action_required`**: el banco pidió validar con 3D Secure, y
  la app todavía no tiene esa pantalla. Si pasa seguido con tarjetas de
  Malargüe, hay que agregarla.
