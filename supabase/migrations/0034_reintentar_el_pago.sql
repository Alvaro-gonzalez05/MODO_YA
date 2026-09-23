-- 0034 - Si la tarjeta rebota, se puede probar con otra
--
-- Antes (0032) un pago rechazado cancelaba el pedido en el acto: el cliente
-- veia "El pedido se cancelo" y tenia que armar el carrito de nuevo. Ahora el
-- pedido sigue esperando el pago, se muestra el motivo y puede pagar con otra
-- tarjeta. Los que quedan abandonados los cierra un cron a la media hora.

create or replace function public.confirmar_pago_online(
  p_pedido     uuid,
  p_mp_payment text,
  p_estado     public.estado_pago,
  p_cuotas     smallint default 1,
  p_detalle    text default null
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
    insert into public.pagos (metodo, estado, monto, mp_payment_id, cuotas, detalle, acreditado_en)
    values ('mercado_pago', p_estado, ped.total, p_mp_payment, p_cuotas, p_detalle,
            case when p_estado = 'acreditado' then now() end)
    returning * into pg;
    update public.pedidos set pago_id = pg.id where id = ped.id;
  else
    update public.pagos
       set estado = p_estado, mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           cuotas = coalesce(p_cuotas, cuotas), detalle = p_detalle,
           acreditado_en = case when p_estado = 'acreditado' then now() else acreditado_en end
     where id = ped.pago_id;
  end if;

  -- Aprobado: el pedido entra al local (le suena el timbre).
  if p_estado = 'acreditado' and ped.estado = 'pendiente_pago' then
    update public.pedidos
       set estado = 'pagado', pagado_en = now(), metodo_pago = 'mercado_pago'
     where id = ped.id
    returning * into ped;

    -- actor_id apunta a `perfiles`, no a `clientes`.
    insert into public.pedido_eventos (pedido_id, estado_nuevo, actor_id, actor_rol)
    values (ped.id, 'pagado', (select perfil_id from public.clientes where id = ped.cliente_id), 'cliente');
  end if;

  -- Rechazado: el pedido NO se cancela. Queda esperando para que el cliente
  -- pruebe con otra tarjeta; si lo abandona, lo cierra cerrar_pagos_vencidos().
  return ped;
end;
$$;

revoke execute on function public.confirmar_pago_online(uuid, text, public.estado_pago, smallint, text)
  from public, anon, authenticated;

-- Cierra los pedidos que quedaron a medio pagar. Corre cada 5 minutos.
create or replace function public.cerrar_pagos_vencidos()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n integer;
begin
  with cerrados as (
    update public.pedidos
       set estado = 'cancelado', cancelado_en = now(),
           motivo_cancelacion = 'El pago no se completó a tiempo'
     where estado = 'pendiente_pago'
       and creado_en < now() - interval '30 minutes'
    returning id
  )
  select count(*) into n from cerrados;
  return n;
end;
$$;

revoke execute on function public.cerrar_pagos_vencidos() from public, anon, authenticated;

select cron.schedule('cerrar-pagos-vencidos', '*/5 * * * *', 'select public.cerrar_pagos_vencidos()')
 where not exists (select 1 from cron.job where jobname = 'cerrar-pagos-vencidos');
