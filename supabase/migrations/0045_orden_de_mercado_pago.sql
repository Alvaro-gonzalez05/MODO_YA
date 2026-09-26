-- 0045 - El pago guarda tambien el id de la orden de Mercado Pago
--
-- Con la API de Orders, un cobro genera dos identificadores: la **orden**
-- (`ORD01…`) y adentro el **pago** (`PAY01…`). Los webhooks de Orders avisan
-- con el id de la orden, asi que sin guardarlo no hay forma de saber de que
-- pedido esta hablando el aviso.
--
-- `mp_payment_id` se mantiene con el pago, que es lo que se busca cuando hay
-- que reclamar algo puntual.

alter table public.pagos
  add column mp_order_id text;

create index pagos_mp_order_idx on public.pagos (mp_order_id);

comment on column public.pagos.mp_order_id is
  'Id de la orden en Mercado Pago (ORD01...). Es el que viaja en los webhooks.';

-- La firma cambia (entra el id de la orden), asi que se borra la vieja: si
-- quedaran las dos, PostgREST no sabria cual llamar.
drop function if exists public.confirmar_pago_online(uuid, text, public.estado_pago, smallint, text);

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

    -- actor_id apunta a `perfiles`, no a `clientes`.
    insert into public.pedido_eventos (pedido_id, estado_nuevo, actor_id, actor_rol)
    values (ped.id, 'pagado', (select perfil_id from public.clientes where id = ped.cliente_id), 'cliente');
  end if;

  -- Rechazado: el pedido NO se cancela. Queda esperando para que el cliente
  -- pruebe con otra tarjeta; si lo abandona, lo cierra cerrar_pagos_vencidos().
  return ped;
end;
$$;

revoke execute on function public.confirmar_pago_online(uuid, text, public.estado_pago, smallint, text, text)
  from public, anon, authenticated;
