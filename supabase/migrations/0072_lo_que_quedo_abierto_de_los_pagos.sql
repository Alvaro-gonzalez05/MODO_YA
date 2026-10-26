-- 0072 - Lo que quedó abierto de los pagos después de 0068
--
-- Tres huecos que 0068 dejó anotados en docs/hallazgos-de-la-auditoria-2.md:
--
-- 1. **Si el aviso de Mercado Pago no llega, el pago en revisión no se resuelve
--    nunca.** 0068 construyó el consumidor de avisos, pero todo dependía de que
--    el aviso llegara, y el webhook todavía no recibió ninguno real. Si el banco
--    aprobaba el pago después del día de gracia, el pedido ya estaba cancelado y
--    la plata no se devolvía. Ahora la base también **pregunta**: cada pago en
--    revisión con una orden real se le consulta a Mercado Pago cada 10 minutos,
--    durante una semana, aunque no haya llegado ningún aviso.
--
-- 2. **El alta de Plus se podía cobrar dos veces.** Es el mismo agujero que A3
--    pero en la suscripción: la clave de idempotencia salía del token de la
--    tarjeta, y la app pide uno nuevo en cada intento. `tomar_el_cobro_plus()`
--    hace para Plus lo que `tomar_el_cobro()` hace para los pedidos. De arrastre,
--    un alta que quedaba en revisión y el banco aprobaba después no se activaba
--    sola ("lo tiene que mirar una persona"): ahora el pago sabe de qué cliente
--    es y el aviso, o la consulta, le activa el mes.
--
-- 3. **Una devolución parcial se anotaba como total.** El consumidor tomaba
--    cualquier devolución como el pago entero. Ahora recibe el monto: si es el
--    total el pago pasa a `reembolsado`; si es una parte, se anota cuánto y el
--    pago sigue acreditado, con una nota para que la mire una persona (la
--    liquidación del local no se recalcula sola).
--
-- Todo es compatible con la `pagar-pedido` publicada hoy: no se cambia ninguna
-- firma que ella use.

-- ---------------------------------------------------------------------------
-- Columnas
-- ---------------------------------------------------------------------------

alter table public.pagos
  -- El cliente que paga un alta de Plus. Un pago de Plus no tiene pedido, y sin
  -- esto no había forma de saber de quién era cuando el banco lo aprobaba tarde.
  add column if not exists plus_cliente_id uuid references public.clientes(id) on delete set null,
  -- Cuándo se le preguntó por última vez a Mercado Pago por este pago.
  add column if not exists consultado_en timestamptz;

create index if not exists pagos_plus_cliente_idx
  on public.pagos (plus_cliente_id, creado_en desc) where plus_cliente_id is not null;

create index if not exists pagos_en_revision_idx
  on public.pagos (creado_en) where estado = 'pendiente' and mp_order_id is not null;

-- ---------------------------------------------------------------------------
-- 1. Preguntar por los pagos en revisión sin esperar el aviso
-- ---------------------------------------------------------------------------

-- Los pagos que hay que consultar: en revisión, con una orden real (no
-- simulada), con más de 5 minutos —antes casi siempre llega el aviso— y menos de
-- una semana. Cada uno a lo sumo cada 10 minutos, para no golpear a Mercado
-- Pago cada minuto con el mismo pago.
create or replace function public.pagos_por_consultar()
returns table (pago_id uuid, mp_order_id text, mp_payment_id text)
language sql stable security definer set search_path = public
as $$
  select p.id, p.mp_order_id, p.mp_payment_id
    from public.pagos p
   where p.estado = 'pendiente'
     and p.mp_order_id is not null
     and p.mp_order_id not like 'simulado%'
     and coalesce(p.cobro_tomado_en, p.creado_en) < now() - interval '5 minutes'
     and p.creado_en > now() - interval '7 days'
     and (p.consultado_en is null or p.consultado_en < now() - interval '10 minutes')
   order by p.consultado_en nulls first, p.creado_en
   limit 20;
$$;

create or replace function public.pago_consultado(p_pago uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.pagos set consultado_en = now() where id = p_pago;
$$;

revoke execute on function public.pagos_por_consultar() from public, anon, authenticated;
revoke execute on function public.pago_consultado(uuid) from public, anon, authenticated;

-- El disparador ahora también despierta a la Edge Function si hay pagos para
-- consultar, aunque no haya ningún aviso. Misma firma que en 0068.
create or replace function public.procesar_avisos_de_mp()
returns bigint
language plpgsql security definer set search_path = public, extensions
as $$
declare
  url   text;
  clave text;
begin
  -- Si no hay nada, no se molesta a la Edge Function (corre cada minuto).
  if not exists (select 1 from public.mp_avisos_por_procesar())
     and not exists (select 1 from public.pagos_por_consultar()) then
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

-- ---------------------------------------------------------------------------
-- 2. El alta de Plus se cobra una sola vez
-- ---------------------------------------------------------------------------

-- La clave con la que se puede cobrar un alta de Plus, o el motivo por el que
-- no. Mismo razonamiento que `tomar_el_cobro` (0068), con dos diferencias:
--
--   * el pago no cuelga de un pedido sino del cliente (`plus_cliente_id`), y se
--     mira solo el último día: un alta de ayer no tiene nada que ver con hoy;
--   * si el último alta se cobró hace menos de 10 minutos, no se deja cobrar
--     otra. Es el toque que llega cuando la pantalla todavía no se enteró de
--     que el primero salió bien.
create or replace function public.tomar_el_cobro_plus(p_cliente uuid)
returns table (clave text, pago_id uuid, monto integer, motivo text, mensaje text)
language plpgsql security definer set search_path = public
as $$
declare
  pg public.pagos;
  n  smallint;
  precio integer := public.precio_plus();
begin
  -- El lock del cliente ordena dos toques simultáneos: el segundo ve el pago
  -- que dejó el primero.
  perform 1 from public.clientes where id = p_cliente for update;
  if not found then
    return query select null::text, null::uuid, null::integer, 'sin_cliente'::text, 'No encontramos tu cuenta.'::text;
    return;
  end if;

  select * into pg from public.pagos
   where plus_cliente_id = p_cliente
     and creado_en > now() - interval '1 day'
   order by creado_en desc
   limit 1
     for update;

  if pg.id is null or pg.estado = 'reembolsado'
     or (pg.estado = 'acreditado' and pg.acreditado_en < now() - interval '10 minutes') then
    insert into public.pagos (metodo, estado, monto, plus_cliente_id, intentos, cobro_tomado_en)
    values ('mercado_pago', 'pendiente', precio, p_cliente, 1, now())
    returning * into pg;
    n := 1;

  elsif pg.estado = 'acreditado' then
    return query select null::text, pg.id, pg.monto, 'ya_pago'::text,
                        'Ya te cobramos MODO YA Plus hace un momento. No hace falta pagarlo de nuevo.'::text;
    return;

  elsif pg.estado = 'rechazado' then
    -- Intento nuevo, clave nueva: con la vieja Mercado Pago devolvería el
    -- rechazo que tiene guardado.
    n := (pg.intentos + 1)::smallint;
    update public.pagos
       set estado = 'pendiente', intentos = n, cobro_tomado_en = now(), monto = precio,
           detalle = null, mp_order_id = null, mp_payment_id = null
     where id = pg.id;

  elsif pg.mp_order_id is not null then
    return query select null::text, pg.id, pg.monto, 'en_revision'::text,
                        'El banco está revisando tu pago de Plus. Si lo aprueba te lo activamos solo: no lo pagues de nuevo.'::text;
    return;

  elsif pg.cobro_tomado_en > now() - interval '3 minutes' then
    return query select null::text, pg.id, pg.monto, 'en_curso'::text,
                        'Estamos procesando tu pago. Esperá unos segundos antes de volver a intentar.'::text;
    return;

  else
    -- El intento anterior se murió en el medio: misma clave, para que si
    -- Mercado Pago llegó a cobrar devuelva esa orden y no cree otra.
    n := greatest(pg.intentos, 1)::smallint;
    update public.pagos set intentos = n, cobro_tomado_en = now() where id = pg.id;
  end if;

  return query select 'plus-alta-' || pg.id::text || '-' || n::text, pg.id, pg.monto, null::text, null::text;
end;
$$;

-- Lo que contestó Mercado Pago sobre un alta de Plus. Si salió aprobado, el
-- pago y el mes se asientan en la misma transacción, como en `plus_cobrado`.
--
-- Es idempotente: la llaman la Edge Function al cobrar y, si el pago quedó en
-- revisión, después el aviso o la consulta. El mes se da una sola vez.
create or replace function public.plus_alta_resultado(
  p_pago       uuid,
  p_estado     public.estado_pago,
  p_mp_payment text default null,
  p_mp_order   text default null,
  p_detalle    text default null
)
returns public.suscripciones_plus
language plpgsql security definer set search_path = public
as $$
declare
  pg public.pagos;
  s  public.suscripciones_plus;
begin
  select * into pg from public.pagos where id = p_pago for update;
  if pg.id is null or pg.plus_cliente_id is null then
    raise exception 'Ese pago no es un alta de Plus' using errcode = 'MY004';
  end if;

  if p_estado = 'acreditado' then
    select * into s from public.suscripciones_plus where pago_id = pg.id;
    if s.id is not null then
      return s;
    end if;

    update public.pagos
       set estado = 'acreditado',
           mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           mp_order_id = coalesce(p_mp_order, mp_order_id),
           acreditado_en = coalesce(acreditado_en, now()),
           detalle = null
     where id = pg.id;

    return public.activar_plus(pg.plus_cliente_id, pg.monto, pg.id);
  end if;

  -- Un pago acreditado no vuelve atrás con un "rechazado" que llega tarde.
  if pg.estado <> 'acreditado' then
    update public.pagos
       set estado = p_estado,
           mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           mp_order_id = coalesce(p_mp_order, mp_order_id),
           detalle = coalesce(p_detalle, detalle)
     where id = pg.id;
  end if;
  return null;
end;
$$;

revoke execute on function public.tomar_el_cobro_plus(uuid) from public, anon, authenticated;
revoke execute on function public.plus_alta_resultado(uuid, public.estado_pago, text, text, text)
  from public, anon, authenticated;

-- La renovación también deja dicho de quién es el pago. Misma firma que 0068.
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
                            cuotas, acreditado_en, plus_cliente_id)
  values ('mercado_pago', 'acreditado', p_precio, p_mp_payment, p_mp_order, 1, now(), p_cliente)
  returning * into pg;

  return public.activar_plus(p_cliente, p_precio, pg.id);
end;
$$;

revoke execute on function public.plus_cobrado(uuid, integer, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. El consumidor: Plus que se aprueba tarde y devoluciones parciales
-- ---------------------------------------------------------------------------

-- Cambia la firma (se agrega el monto devuelto), así que hay que borrarla: un
-- `create or replace` con un parámetro más crea una segunda función y la
-- llamada queda ambigua. La única que la llama es `mp-procesar-avisos`, que
-- todavía no está publicada.
drop function if exists public.resolver_pago_de_mp(text, text, public.estado_pago, text);

create or replace function public.resolver_pago_de_mp(
  p_mp_order          text,
  p_mp_payment        text,
  p_estado            public.estado_pago,
  p_detalle           text default null,
  p_monto_reembolsado integer default null
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
      if pg.plus_cliente_id is not null then
        -- Un alta de Plus que el banco aprobó después: se le da el mes.
        -- `plus_alta_resultado` es idempotente, así que un aviso repetido o
        -- una renovación ya activada no le dan un mes de más.
        perform public.plus_alta_resultado(
          pg.id, 'acreditado', p_mp_payment, p_mp_order, null
        );
        return 'acreditado: MODO YA Plus quedó activo';
      end if;
      -- Un pago sin pedido ni cliente: datos de prueba que se borraron, o algo
      -- de antes de 0072. Queda asentado y lo mira una persona.
      update public.pagos
         set estado = 'acreditado',
             mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
             mp_order_id = coalesce(p_mp_order, mp_order_id),
             acreditado_en = coalesce(acreditado_en, now())
       where id = pg.id;
      return 'acreditado, pero el pago no tiene pedido: lo tiene que mirar una persona';
    end if;

    if ped.estado = 'pendiente_pago' then
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

    update public.pagos
       set estado = 'acreditado', acreditado_en = coalesce(acreditado_en, now())
     where id = pg.id and estado <> 'acreditado';
    return 'ya estaba resuelto';
  end if;

  if p_estado = 'rechazado' then
    if pg.estado = 'acreditado' then
      return 'el pago ya estaba acreditado: no se toca';
    end if;
    update public.pagos
       set estado = 'rechazado',
           detalle = coalesce(p_detalle, detalle),
           mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           mp_order_id = coalesce(p_mp_order, mp_order_id)
     where id = pg.id;
    return 'rechazado: el cliente puede pagar con otra tarjeta';
  end if;

  if p_estado = 'reembolsado' then
    if pg.estado = 'reembolsado' then
      -- La devolución la hicimos nosotros (rechazo del local, 0060) y este es
      -- el aviso de Mercado Pago confirmándola.
      return 'ya estaba devuelto';
    end if;

    if p_monto_reembolsado is not null and p_monto_reembolsado < pg.monto then
      -- Una parte. El pago sigue acreditado por la diferencia: marcarlo
      -- reembolsado diría que no entró nada. Se anota cuánto volvió y lo mira
      -- una persona, porque el pedido pudo haberse entregado igual.
      update public.pagos
         set monto_reembolsado = p_monto_reembolsado,
             mp_refund_id = coalesce(mp_refund_id, p_mp_payment)
       where id = pg.id;
      return format('devolución parcial de $%s de $%s desde Mercado Pago: revisar la liquidación del local',
                    p_monto_reembolsado, pg.monto);
    end if;

    update public.pagos
       set estado = 'reembolsado',
           reembolsado_en = coalesce(reembolsado_en, now()),
           monto_reembolsado = coalesce(p_monto_reembolsado, monto_reembolsado, monto),
           mp_refund_id = coalesce(mp_refund_id, p_mp_payment)
     where id = pg.id;
    return 'devuelto desde Mercado Pago: revisar la liquidación del local';
  end if;

  return 'el aviso no cambia nada (' || p_estado::text || ')';
end;
$$;

revoke execute on function public.resolver_pago_de_mp(text, text, public.estado_pago, text, integer)
  from public, anon, authenticated;
