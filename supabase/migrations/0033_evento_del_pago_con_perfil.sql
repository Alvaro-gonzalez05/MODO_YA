-- 0033 - Arreglo: el evento del pedido guarda el perfil, no el cliente
--
-- `pedido_eventos.actor_id` referencia a `perfiles`; confirmar_pago_online
-- (0032) estaba guardando ahi el id de `clientes` y el pago aprobado no
-- llegaba a mover el pedido (violaba la clave foranea). Se ve en el flujo de
-- prueba: la tarjeta quedaba guardada pero el pedido seguia esperando pago.

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
    insert into public.pagos (metodo, estado, monto, mp_payment_id, cuotas, detalle,
                              acreditado_en)
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

  -- Rechazado: el pedido no queda colgado esperando para siempre.
  if p_estado = 'rechazado' and ped.estado = 'pendiente_pago' then
    update public.pedidos
       set estado = 'cancelado', cancelado_en = now(),
           motivo_cancelacion = coalesce(p_detalle, 'El pago no se pudo completar')
     where id = ped.id
    returning * into ped;
  end if;

  return ped;
end;
$$;

