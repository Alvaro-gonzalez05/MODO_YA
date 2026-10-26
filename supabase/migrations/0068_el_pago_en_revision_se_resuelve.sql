-- 0068 - Un pago que el banco deja en revisión se resuelve solo
--
-- Cierra los tres agujeros que bloqueaban encender el cobro real
-- (docs/hallazgos-de-la-auditoria-2.md, A1, A2 y A3).
--
-- ---------------------------------------------------------------------------
-- A1 - El consumidor de avisos que faltaba
-- ---------------------------------------------------------------------------
--
-- Cuando el banco manda un pago a revisión, Mercado Pago contesta `processing`
-- y el pago queda `pendiente`. Desde ahí no había camino de vuelta: el aviso
-- que Mercado Pago manda después se guardaba en `mp_notificaciones` y nadie lo
-- leía (0044 lo dejó así a propósito, "hasta tener credenciales"). A los 30
-- minutos `cerrar_pagos_vencidos()` cancelaba el pedido con un `update` crudo
-- que no marcaba ningún reembolso, y los dos disparadores de devolución piden
-- que el pago esté `acreditado`. El cliente quedaba cobrado, sin pedido y sin
-- devolución.
--
-- Lo que se construye acá es el consumidor:
--
--   * `mp_avisos_por_procesar()` entrega los avisos **con firma válida** que
--     todavía nadie resolvió.
--   * `resolver_pago_de_mp()` es el que decide: si el pedido todavía vive, lo
--     acredita y lo manda al local; si ya murió, pide la devolución.
--   * `mp_aviso_procesado()` lo tacha con una nota, que es lo que después se ve
--     en la pantalla de avisos de la administración.
--   * el cron `procesar-avisos-mp` llama cada minuto a la Edge Function
--     `mp-procesar-avisos`, que es la que tiene el access token para
--     preguntarle a Mercado Pago cómo terminó la orden.
--
-- Por qué la decisión vive en la base y no en la Edge Function: mover un pedido
-- y pedir un reembolso es lógica de negocio, y en este proyecto eso va en
-- funciones `security definer`. La Edge Function hace lo único que no se puede
-- hacer desde la base: hablar con Mercado Pago.
--
-- Por qué por cron y no dentro de `mp-webhook`: Mercado Pago exige un 200 en
-- menos de 22 segundos y reintenta cada 15 minutos si no llega. Preguntarle por
-- la orden desde ahí adentro arriesga el timeout, y un timeout es un aviso
-- repetido. Es el mismo reparto que ya usa el reembolso (0060): la tabla es el
-- buzón y el cron el que lo vacía.
--
-- **El plazo de los 30 minutos cambia.** Treinta minutos alcanzan para un
-- carrito abandonado, pero son demasiado apurados para un cobro que el banco
-- está revisando: cancelar ahí deja al cliente cobrado y sin pedido, y después
-- hay que devolverle la plata de algo que podría haber salido bien. Ahora el
-- plazo depende de si hay un cobro hecho o no (ver `cerrar_pagos_vencidos`).
--
-- ---------------------------------------------------------------------------
-- A2 - La renovación de Plus cobrada y no activada
-- ---------------------------------------------------------------------------
--
-- La clave de idempotencia era `plus-renovacion-<suscripcion>`, la misma todos
-- los días, y lo único que acotaba los reintentos era `intentos_fallidos` — que
-- el `catch` no tocaba a propósito cuando el cobro había salido bien. Con la
-- suscripción todavía vencida, el cron la devolvía al día siguiente: si la
-- ventana de idempotencia de Mercado Pago ya había vencido (las corridas están
-- a 24 h) era un cobro nuevo, y si no había vencido era la respuesta cacheada y
-- la renovación no se activaba nunca.
--
-- Acá va la mitad que corresponde a la base: `plus_cobrado()` mete el pago y
-- activa el mes **en una sola transacción** (antes el insert en `pagos`
-- descartaba su error y `activar_plus` se llamaba con `p_pago: null`, así que
-- el cliente podía recibir el mes sin que quedara registro del cobro), y
-- `plus_renovacion_trabada()` saca de la cola a la suscripción que se cobró y
-- no se pudo activar. La otra mitad —que la clave identifique el período— va en
-- la Edge Function.
--
-- ---------------------------------------------------------------------------
-- A3 - Dos toques de "Pagar" y dos cobros
-- ---------------------------------------------------------------------------
--
-- La clave de idempotencia era `pedido-<id>-<últimos 16 del token>`, y la app
-- pide un token nuevo en cada intento: dos intentos con la misma tarjeta daban
-- dos claves y Mercado Pago cobraba dos veces. `tomar_el_cobro()` da la clave
-- del lado de la base, contando el intento del pedido, y **no la da** si ya hay
-- un cobro hecho esperando al banco. `estado_del_pago_de_mi_pedido()` deja que
-- la app se entere de eso sin poder leer `pagos` (que el cliente no puede).

-- ---------------------------------------------------------------------------
-- Columnas nuevas
-- ---------------------------------------------------------------------------

alter table public.pagos
  -- Cuántas veces se le pidió a Mercado Pago cobrar este pago. Es lo que hace
  -- única la clave de idempotencia de cada intento.
  add column if not exists intentos smallint not null default 0 check (intentos >= 0),
  -- Cuándo se tomó el cobro por última vez. Sirve para distinguir "hay un
  -- intento en vuelo ahora mismo" de "el intento anterior murió en el medio".
  add column if not exists cobro_tomado_en timestamptz;

comment on column public.pagos.intentos is
  'Intentos de cobro. Entra en la clave de idempotencia para que un reintento legítimo no reciba la respuesta cacheada del anterior.';

alter table public.suscripciones_plus
  add column if not exists cobrada_sin_activar_en timestamptz,
  add column if not exists cobrada_sin_activar_pago text;

comment on column public.suscripciones_plus.cobrada_sin_activar_en is
  'Se le cobró el mes y no se pudo activar. Mientras esté puesto el cron NO vuelve a cobrarle: lo resuelve una persona.';
comment on column public.suscripciones_plus.cobrada_sin_activar_pago is
  'El id del pago en Mercado Pago de ese cobro que quedó sin mes. Es el rastro para encontrarlo en el panel.';

-- ---------------------------------------------------------------------------
-- A3 - Tomar el cobro antes de cobrar
-- ---------------------------------------------------------------------------

-- Devuelve la clave de idempotencia con la que se puede cobrar este pedido, o
-- el motivo por el cual no se puede.
--
-- `motivo` es un código para la Edge Function y `mensaje` lo que se le muestra
-- al cliente. `en_revision` y `en_curso` **no son errores**: hay un cobro hecho
-- o en vuelo, y mostrárselos en rojo es lo que hacía que el cliente volviera a
-- tocar "Pagar" y se le cobrara dos veces.
create or replace function public.tomar_el_cobro(p_pedido uuid)
returns table (clave text, motivo text, mensaje text)
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
  pg  public.pagos;
  n   smallint;
begin
  -- El lock del pedido es lo que hace atómica la toma: dos pedidos de cobro a
  -- la vez se ordenan acá, y el segundo ve el pago que dejó el primero.
  select * into ped from public.pedidos where id = p_pedido for update;
  if ped.id is null then
    return query select null::text, 'sin_pedido'::text, 'El pedido no existe.'::text;
    return;
  end if;
  if ped.estado <> 'pendiente_pago' then
    return query select null::text, 'otro_estado'::text,
                        'Este pedido ya no está esperando el pago.'::text;
    return;
  end if;

  if ped.pago_id is not null then
    select * into pg from public.pagos where id = ped.pago_id for update;
  end if;

  if pg.id is null then
    -- Primer intento: el pago nace acá, antes de hablar con Mercado Pago. Nace
    -- antes a propósito: es lo que le permite al segundo toque darse cuenta de
    -- que ya hay un cobro en vuelo.
    insert into public.pagos (metodo, estado, monto, intentos, cobro_tomado_en)
    values ('mercado_pago', 'pendiente', ped.total, 1, now())
    returning * into pg;
    update public.pedidos set pago_id = pg.id where id = ped.id;
    n := 1;

  elsif pg.estado = 'acreditado' then
    return query select null::text, 'ya_pago'::text, 'Este pedido ya está pago.'::text;
    return;

  elsif pg.estado = 'reembolsado' then
    return query select null::text, 'devuelto'::text, 'Este pago ya se devolvió.'::text;
    return;

  elsif pg.estado = 'rechazado' then
    -- El banco dijo que no: este es un intento nuevo y tiene que llevar una
    -- clave nueva. Con la clave vieja Mercado Pago contestaría el rechazo que
    -- tiene cacheado y el cliente no podría pagar nunca más este pedido.
    --
    -- Los ids de la orden rechazada se borran: son del intento que ya terminó.
    -- Si quedaran, el intento siguiente que muriera en el medio dejaría el pago
    -- `pendiente` con una orden vieja, y de ahí en adelante este mismo bloque
    -- lo leería como "el banco lo está revisando" — el cliente no podría pagar
    -- nunca más ese pedido. Y no se pierde nada: un rechazo no tiene plata que
    -- devolver, y el motivo queda en `pedido_eventos`.
    n := (pg.intentos + 1)::smallint;
    update public.pagos
       set estado = 'pendiente', intentos = n, cobro_tomado_en = now(),
           detalle = null, mp_order_id = null, mp_payment_id = null
     where id = pg.id;

  elsif pg.mp_order_id is not null then
    -- Hay una orden hecha y el banco todavía no se decidió (processing, 3DS).
    -- Dejarlo cobrar de nuevo es cobrarle dos veces. Lo resuelve el aviso de
    -- Mercado Pago, y si no llega, `cerrar_pagos_vencidos()` al día.
    return query select null::text, 'en_revision'::text,
                        'El banco está revisando tu pago. Te avisamos apenas se confirme: no lo pagues de nuevo.'::text;
    return;

  elsif pg.cobro_tomado_en > now() - interval '3 minutes' then
    -- Otro intento está en vuelo ahora mismo (dos toques, dos pantallas).
    return query select null::text, 'en_curso'::text,
                        'Estamos procesando tu pago. Esperá unos segundos antes de volver a intentar.'::text;
    return;

  else
    -- El intento anterior tomó el cobro y no dejó orden: se murió en el medio y
    -- no sabemos si Mercado Pago llegó a cobrar. Se reintenta con **la misma**
    -- clave, así si la orden existía Mercado Pago devuelve esa en lugar de
    -- crear otra. Subir el contador acá sería arriesgar el cobro doble que
    -- justamente se está tratando de evitar.
    n := greatest(pg.intentos, 1)::smallint;
    update public.pagos set intentos = n, cobro_tomado_en = now() where id = pg.id;
  end if;

  return query select 'pedido-' || p_pedido::text || '-' || n::text, null::text, null::text;
end;
$$;

revoke execute on function public.tomar_el_cobro(uuid) from public, anon, authenticated;

-- Qué pasó con el cobro de un pedido del cliente que está usando la app.
--
-- Existe porque el cliente **no puede leer `pagos`** (RLS, 0008), y sin esto la
-- pantalla de pago le vuelve a pedir la tarjeta a alguien que ya tiene un cobro
-- hecho esperando al banco.
create or replace function public.estado_del_pago_de_mi_pedido(p_pedido uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select case
           when pg.id is null then 'sin_pago'
           -- Hay una orden hecha sin respuesta del banco, o hay un intento en
           -- vuelo ahora mismo. En los dos casos lo que no se puede hacer es
           -- pedirle la tarjeta otra vez. El plazo es el mismo que usa
           -- `tomar_el_cobro` para soltar un intento que se murió.
           when pg.estado = 'pendiente'
                and (pg.mp_order_id is not null
                     or pg.cobro_tomado_en > now() - interval '3 minutes')
             then 'en_revision'
           else pg.estado::text
         end
    from public.pedidos p
    left join public.pagos pg on pg.id = p.pago_id
   where p.id = p_pedido
     -- Solo el dueño del pedido. Sin este filtro cualquier cliente podría
     -- preguntar por el pedido de otro.
     and p.cliente_id = public.mi_cliente_id();
$$;

revoke execute on function public.estado_del_pago_de_mi_pedido(uuid) from public, anon;
grant execute on function public.estado_del_pago_de_mi_pedido(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- A1 - Si la plata entró y el pedido ya murió, se devuelve
-- ---------------------------------------------------------------------------

-- Igual que la de 0059 más un caso que faltaba: que el pago se acredite cuando
-- el pedido ya está cancelado o rechazado. Pasa por el camino sincrónico (el
-- cliente paga justo cuando `cerrar_pagos_vencidos()` lo cierra) y pasa por el
-- aviso de Mercado Pago, que llega siempre después. Sin esto la plata se queda.
create or replace function public.confirmar_pago_online(
  p_pedido     uuid,
  p_mp_payment text,
  p_estado     public.estado_pago,
  p_cuotas     smallint default 1,
  p_detalle    text default null,
  p_mp_order   text default null
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
  pg  public.pagos;
begin
  select * into ped from public.pedidos where id = p_pedido for update;
  if ped.id is null then
    raise exception 'El pedido no existe' using errcode = 'MY004';
  end if;

  if ped.pago_id is null then
    insert into public.pagos (metodo, estado, monto, mp_payment_id, mp_order_id,
                              cuotas, detalle, acreditado_en)
    values ('mercado_pago', p_estado, ped.total, p_mp_payment, p_mp_order, p_cuotas, p_detalle,
            case when p_estado = 'acreditado' then now() end)
    returning * into pg;
    update public.pedidos set pago_id = pg.id where id = ped.id;
  else
    -- Pisar `mp_payment_id` / `mp_order_id` solo es correcto porque un segundo
    -- cobro sobre el mismo pedido ya no puede existir: `tomar_el_cobro()` no
    -- deja arrancar otro mientras el anterior no tenga respuesta. Antes sí
    -- podía, y el primer cobro quedaba sin referencia — con lo cual el
    -- reembolso, que sale de `mp_order_id`, solo podía devolver uno.
    update public.pagos
       set estado = p_estado, mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           mp_order_id = coalesce(p_mp_order, mp_order_id),
           cuotas = coalesce(p_cuotas, cuotas), detalle = p_detalle,
           acreditado_en = case when p_estado = 'acreditado' then now() else acreditado_en end
     where id = ped.pago_id
    returning * into pg;
  end if;

  -- Aprobado: el pedido entra al local (le suena el timbre).
  if p_estado = 'acreditado' and ped.estado = 'pendiente_pago' then
    update public.pedidos
       set estado = 'pagado', pagado_en = now(), metodo_pago = 'mercado_pago'
     where id = ped.id
    returning * into ped;

    -- El trigger `registrar_cambio_pedido` ya asentó el cambio; acá solo se le
    -- pone quién fue (0059). El trigger lo deja sin actor porque la Edge
    -- Function corre con service_role y `auth.uid()` viene nulo. `actor_id`
    -- apunta a `perfiles`, no a `clientes`.
    update public.pedido_eventos
       set actor_id = (select perfil_id from public.clientes where id = ped.cliente_id),
           actor_rol = 'cliente'
     where pedido_id = ped.id and estado_nuevo = 'pagado' and actor_id is null;
  end if;

  -- La plata entró y el pedido ya no existe como pedido: hay que devolverla. El
  -- cron `reembolsar-pedidos` (0060) la devuelve solo con esta marca puesta.
  if p_estado = 'acreditado' and ped.estado in ('cancelado', 'rechazado') then
    update public.pagos
       set reembolso_pedido_en = coalesce(reembolso_pedido_en, now())
     where id = pg.id and reembolsado_en is null;
  end if;

  -- Rechazado: el pedido NO se cancela. Queda esperando para que el cliente
  -- pruebe con otra tarjeta; si lo abandona, lo cierra cerrar_pagos_vencidos().
  return ped;
end;
$$;

revoke execute on function public.confirmar_pago_online(uuid, text, public.estado_pago, smallint, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- A1 - El consumidor de avisos
-- ---------------------------------------------------------------------------

-- Los avisos que todavía nadie resolvió.
--
-- **Exigir `firma_valida` es lo que impide que cualquiera que conozca la URL
-- nos dé un pago por bueno.** Un aviso sin firma válida se sigue guardando (eso
-- permite probar con el simulador de notificaciones de Mercado Pago) pero nunca
-- mueve plata.
--
-- El límite de 30 días es para que un aviso que no se puede resolver no quede
-- reintentándose para siempre. Lo que queda sin tachar se ve en la pantalla de
-- avisos de la administración.
create or replace function public.mp_avisos_por_procesar()
returns table (aviso_id uuid, tipo text, accion text, recurso_id text, cuerpo jsonb)
language sql stable security definer set search_path = public
as $$
  select n.id, n.tipo, n.accion, n.recurso_id, n.cuerpo
    from public.mp_notificaciones n
   where not n.procesada
     and n.firma_valida is true
     and n.recurso_id is not null
     and n.recibido_en > now() - interval '30 days'
   order by n.recibido_en
   limit 50;
$$;

create or replace function public.mp_aviso_procesado(p_aviso uuid, p_nota text)
returns void
language sql security definer set search_path = public
as $$
  update public.mp_notificaciones
     set procesada = true, procesada_en = now(), nota = p_nota
   where id = p_aviso;
$$;

-- El consumidor: qué se hace cuando Mercado Pago dice cómo terminó un cobro.
--
-- Devuelve en texto qué se hizo, que es lo que queda como nota del aviso.
--
-- La decisión de fondo es una sola: **el pago sigue al pedido**. Si el pedido
-- todavía vive, la plata que entró lo empuja adelante; si el pedido ya murió, la
-- plata vuelve. Nunca se revive un pedido cancelado — el cliente ya no lo
-- espera, la cocina nunca lo vio, y el envío no existe — así que la única
-- salida honesta es devolver.
create or replace function public.resolver_pago_de_mp(
  p_mp_order   text,
  p_mp_payment text,
  p_estado     public.estado_pago,
  p_detalle    text default null
)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  pg  public.pagos;
  ped public.pedidos;
begin
  -- Los avisos de Orders traen el id de la orden; los de la API vieja
  -- (Payments) solo traen el del pago. Se busca por los dos.
  select * into pg
    from public.pagos
   where (p_mp_order is not null and mp_order_id = p_mp_order)
      or (p_mp_payment is not null and mp_payment_id = p_mp_payment)
   order by creado_en desc
   limit 1
     for update;

  if pg.id is null then
    return 'no corresponde a ningún pago nuestro';
  end if;

  select * into ped from public.pedidos where pago_id = pg.id for update;

  if p_estado = 'acreditado' then
    if ped.id is null then
      -- Un pago sin pedido: la suscripción a Plus, o datos de prueba que se
      -- borraron. No hay pedido que mover ni reembolso que pedir (el cron de
      -- reembolsos sale de los pedidos), así que queda asentado y lo mira una
      -- persona en la pantalla de avisos.
      update public.pagos
         set estado = 'acreditado',
             mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
             mp_order_id = coalesce(p_mp_order, mp_order_id),
             acreditado_en = coalesce(acreditado_en, now())
       where id = pg.id;
      return 'acreditado, pero el pago no tiene pedido: lo tiene que mirar una persona';
    end if;

    if ped.estado = 'pendiente_pago' then
      -- El pedido sigue vivo: se acredita y entra al local, igual que si el
      -- banco hubiera contestado en el momento.
      perform public.confirmar_pago_online(
        ped.id,
        coalesce(p_mp_payment, pg.mp_payment_id),
        'acreditado',
        coalesce(pg.cuotas, 1)::smallint,
        null,
        coalesce(p_mp_order, pg.mp_order_id)
      );
      return 'acreditado y mandado al local';
    end if;

    if ped.estado in ('cancelado', 'rechazado') then
      -- Esto es el corazón de A1: el pedido se cerró esperando y la plata entró
      -- después. Se devuelve entera.
      update public.pagos
         set estado = 'acreditado',
             mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
             mp_order_id = coalesce(p_mp_order, mp_order_id),
             acreditado_en = coalesce(acreditado_en, now()),
             reembolso_pedido_en = coalesce(reembolso_pedido_en, now())
       where id = pg.id and reembolsado_en is null;
      return 'acreditado tarde, el pedido ya estaba ' || ped.estado::text ||
             ': se pidió la devolución';
    end if;

    -- El pedido ya está andando: el cobro se había resuelto por el camino
    -- sincrónico y el aviso no agrega nada.
    update public.pagos
       set estado = 'acreditado', acreditado_en = coalesce(acreditado_en, now())
     where id = pg.id and estado <> 'acreditado';
    return 'ya estaba resuelto';
  end if;

  if p_estado = 'rechazado' then
    if pg.estado = 'acreditado' then
      -- Mercado Pago no da marcha atrás un pago acreditado con un "failed". Si
      -- llegara a pasar, pisar el estado dejaría la liquidación mal: queda como
      -- está y lo mira una persona.
      return 'el pago ya estaba acreditado: no se toca';
    end if;
    -- El pedido NO se cancela: el cliente puede probar con otra tarjeta, igual
    -- que cuando la tarjeta rebota en el momento (0034). Si lo abandona, lo
    -- cierra `cerrar_pagos_vencidos()`.
    update public.pagos
       set estado = 'rechazado',
           detalle = coalesce(p_detalle, detalle),
           mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           mp_order_id = coalesce(p_mp_order, mp_order_id)
     where id = pg.id;
    return 'rechazado: el cliente puede pagar con otra tarjeta';
  end if;

  if p_estado = 'reembolsado' then
    -- Una devolución o un contracargo hechos desde el panel de Mercado Pago. Se
    -- asienta para que la liquidación no cuente plata que ya no está. El pedido
    -- no se toca solo: puede estar en la calle, y decidir si se entrega igual
    -- es de una persona.
    update public.pagos
       set estado = 'reembolsado',
           reembolsado_en = coalesce(reembolsado_en, now()),
           monto_reembolsado = coalesce(monto_reembolsado, monto),
           mp_refund_id = coalesce(mp_refund_id, p_mp_payment)
     where id = pg.id;
    return 'devuelto desde Mercado Pago: revisar la liquidación del local';
  end if;

  return 'el aviso no cambia nada (' || p_estado::text || ')';
end;
$$;

revoke execute on function public.mp_avisos_por_procesar() from public, anon, authenticated;
revoke execute on function public.mp_aviso_procesado(uuid, text) from public, anon, authenticated;
revoke execute on function public.resolver_pago_de_mp(text, text, public.estado_pago, text)
  from public, anon, authenticated;

-- El disparador: le avisa a la Edge Function que hay avisos para resolver. La
-- URL y la clave salen de Vault, igual que en 0041 y 0060.
create or replace function public.procesar_avisos_de_mp()
returns bigint
language plpgsql security definer set search_path = public, extensions
as $$
declare
  url   text;
  clave text;
begin
  -- Si no hay nada, no se molesta a la Edge Function (corre cada minuto).
  if not exists (select 1 from public.mp_avisos_por_procesar()) then
    return null;
  end if;

  select decrypted_secret into url   from vault.decrypted_secrets where name = 'url_funciones';
  select decrypted_secret into clave from vault.decrypted_secrets where name = 'clave_de_servicio';
  if url is null or clave is null then
    raise warning 'Falta el secreto para procesar los avisos (correr guardar_secretos.ps1)';
    return null;
  end if;

  return net.http_post(
    url := url || '/mp-procesar-avisos',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || clave
    ),
    body := jsonb_build_object('accion', 'procesar'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function public.procesar_avisos_de_mp() from public, anon, authenticated;

select cron.schedule('procesar-avisos-mp', '* * * * *', $$select public.procesar_avisos_de_mp()$$)
 where not exists (select 1 from cron.job where jobname = 'procesar-avisos-mp');

-- ---------------------------------------------------------------------------
-- A1 - El plazo para cerrar un pedido sin pagar
-- ---------------------------------------------------------------------------

-- Antes esto cancelaba a los 30 minutos **todo** pedido en `pendiente_pago`,
-- con un `update` crudo que no marcaba ningún reembolso. Dos cambios:
--
--   1. El plazo depende de si hay un cobro hecho. Treinta minutos están bien
--      para un carrito abandonado o una tarjeta que rebotó: no hay plata en
--      juego. Para un cobro que el banco está revisando son demasiado
--      apurados — Mercado Pago puede tardar horas en resolver un `processing`,
--      y cancelar antes deja al cliente cobrado y esperando una devolución de
--      algo que podía salir bien. A esos se les da un día, que es también el
--      plazo que `reembolsos_pendientes()` usa para rendirse.
--   2. Si la plata entró, se marca el reembolso. **No se puede pasar por
--      `cancelar_pedido`**: esa función pide ser el cliente, el local o la
--      administración, y acá corre el cron sin sesión. Lo que importaba de
--      `cancelar_pedido` era justamente esta marca, así que se repite.
create or replace function public.cerrar_pagos_vencidos()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n integer := 0;
  r record;
begin
  for r in
    select p.id, p.pago_id, pg.estado as pago_estado, pg.mp_order_id
      from public.pedidos p
      left join public.pagos pg on pg.id = p.pago_id
     where p.estado = 'pendiente_pago'
       and case
             when pg.id is null
                  or pg.estado = 'rechazado'
                  or (pg.estado = 'pendiente' and pg.mp_order_id is null)
               then p.creado_en < now() - interval '30 minutes'
             else p.creado_en < now() - interval '1 day'
           end
     for update of p
  loop
    update public.pedidos
       set estado = 'cancelado', cancelado_en = now(),
           motivo_cancelacion = case
             when r.pago_estado = 'pendiente' and r.mp_order_id is not null
               then 'El banco no confirmó el pago a tiempo'
             else 'El pago no se completó a tiempo'
           end
     where id = r.id and estado = 'pendiente_pago';
    if not found then continue; end if;

    if r.pago_estado = 'acreditado' then
      update public.pagos
         set reembolso_pedido_en = coalesce(reembolso_pedido_en, now())
       where id = r.pago_id and reembolsado_en is null;
    end if;

    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke execute on function public.cerrar_pagos_vencidos() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- A2 - Plus: el cobro y el mes van juntos, y la que falló sale de la cola
-- ---------------------------------------------------------------------------

-- El pago y la activación en una sola transacción.
--
-- Antes la Edge Function insertaba en `pagos` descartando el `error` del insert
-- y después llamaba a `activar_plus` con `p_pago: pago?.id ?? null`: si el
-- insert fallaba, el cliente recibía el mes y no quedaba registro del cobro.
-- Acá o pasan las dos cosas o no pasa ninguna, y la Edge Function se entera.
create or replace function public.plus_cobrado(
  p_cliente    uuid,
  p_precio     integer,
  p_mp_payment text,
  p_mp_order   text default null
)
returns public.suscripciones_plus
language plpgsql security definer set search_path = public
as $$
declare
  pg public.pagos;
begin
  insert into public.pagos (metodo, estado, monto, mp_payment_id, mp_order_id,
                            cuotas, acreditado_en)
  values ('mercado_pago', 'acreditado', p_precio, p_mp_payment, p_mp_order, 1, now())
  returning * into pg;

  return public.activar_plus(p_cliente, p_precio, pg.id);
end;
$$;

-- Se le cobró y no se le pudo dar el mes.
--
-- No se cuenta como intento fallido —la tarjeta no rebotó, y sería contarle un
-- rechazo que no existió— pero el cron **no puede** volver a intentarlo: la
-- suscripción sigue vencida y mañana se la devolvería, con la ventana de
-- idempotencia de Mercado Pago ya vencida (hay 24 h entre corridas). Eso es un
-- cobro nuevo todos los días, que es exactamente el hallazgo A2. Queda trabada
-- hasta que una persona la mire, con el id del pago para encontrarlo en el
-- panel de Mercado Pago.
create or replace function public.plus_renovacion_trabada(
  p_suscripcion uuid,
  p_mp_payment  text,
  p_error       text
)
returns void
language sql security definer set search_path = public
as $$
  update public.suscripciones_plus
     set cobrada_sin_activar_en = coalesce(cobrada_sin_activar_en, now()),
         cobrada_sin_activar_pago = coalesce(cobrada_sin_activar_pago, p_mp_payment),
         ultimo_error = p_error
   where id = p_suscripcion;
$$;

-- Misma firma y mismas columnas que en 0046 (la migración es aditiva): lo único
-- que cambia es que la suscripción trabada sale de la cola.
create or replace function public.plus_por_renovar()
returns table(suscripcion_id uuid, cliente_id uuid, mp_card_id text, precio integer)
language sql stable security definer set search_path = public
as $$
  select s.id, s.cliente_id, t.mp_card_id, public.precio_plus()
    from public.suscripciones_plus s
    join lateral (
      select g.mp_card_id
        from public.tarjetas_guardadas g
       where g.cliente_id = s.cliente_id
       order by g.predeterminada desc, g.creado_en desc
       limit 1
    ) t on true
   where s.renovar
     and s.intentos_fallidos < 3
     -- Se le cobró y no se le pudo dar el mes: volver a cobrarle es el bug.
     and s.cobrada_sin_activar_en is null
     and s.hasta <= public.hoy()
     -- Solo la ultima: si ya se renovo, la vieja no se vuelve a cobrar.
     and s.hasta = (
       select max(x.hasta) from public.suscripciones_plus x where x.cliente_id = s.cliente_id
     );
$$;

revoke execute on function public.plus_cobrado(uuid, integer, text, text)
  from public, anon, authenticated;
revoke execute on function public.plus_renovacion_trabada(uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.plus_por_renovar() from public, anon, authenticated;
