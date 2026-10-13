-- 0059 - Un solo evento "pagado" por pedido
--
-- `confirmar_pago_online` insertaba un evento de auditoria para dejar asentado
-- que el pago lo hizo el cliente, pero el trigger `registrar_cambio_pedido` ya
-- venia registrando el mismo cambio: quedaban dos filas "pagado" en el detalle
-- del pedido.
--
-- No se veia porque hasta ahora el camino comun era efectivo, donde el pedido
-- nace pagado y esta funcion no se llama. Desde 0058 todos los pedidos se
-- pagan con tarjeta y pasan por aca, asi que se duplicaria en todos.

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
    update public.pagos
       set estado = p_estado, mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           mp_order_id = coalesce(p_mp_order, mp_order_id),
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

    -- El trigger `registrar_cambio_pedido` ya asento el cambio; aca solo se le
    -- pone quien fue. Antes se insertaba un evento aparte y quedaban dos
    -- "pagado" en la auditoria: no se veia porque con efectivo el pedido nacia
    -- pagado y este camino no se recorria. Ahora todos los pedidos pasan por
    -- aca (0058), asi que se duplicaria siempre.
    --
    -- El trigger lo deja sin actor porque la Edge Function corre con
    -- service_role y `auth.uid()` viene nulo. actor_id apunta a `perfiles`, no
    -- a `clientes`.
    update public.pedido_eventos
       set actor_id = (select perfil_id from public.clientes where id = ped.cliente_id),
           actor_rol = 'cliente'
     where pedido_id = ped.id and estado_nuevo = 'pagado' and actor_id is null;
  end if;

  -- Rechazado: el pedido NO se cancela. Queda esperando para que el cliente
  -- pruebe con otra tarjeta; si lo abandona, lo cierra cerrar_pagos_vencidos().
  return ped;
end;
$$;

revoke execute on function public.confirmar_pago_online(uuid, text, public.estado_pago, smallint, text, text)
  from public, anon, authenticated;
