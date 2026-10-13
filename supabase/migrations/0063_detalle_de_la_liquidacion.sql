-- 0063 - El detalle de lo que se le va a pagar a un rider
--
-- El resumen dice "1 envío, ganó $3.000, cargos $4.000, saldo -$1.000". Para
-- poder discutirlo con el rider hace falta el renglón por renglón: qué envío,
-- de qué local, cuánto de ese envío y cuánto juntó en la puerta.
--
-- Va como función y no como consulta desde la app **para que los números no se
-- separen**: usa exactamente el mismo filtro que `pendiente_de_liquidar_riders`
-- (entregado, en el período, todavía sin liquidar). Si el detalle se armara por
-- otro lado, el día que uno de los dos cambie el resumen y el detalle van a
-- decir cosas distintas, que es lo peor que puede pasar en una liquidación.

create or replace function public.detalle_de_liquidar_rider(
  p_rider uuid,
  p_desde date,
  p_hasta date
)
returns table (
  envio_id    uuid,
  codigo      text,
  entregado   timestamptz,
  comercio    text,
  destino     text,
  ganancia    integer,
  efectivo    integer
)
language sql stable security definer set search_path = public
as $$
  select e.id, e.codigo, e.entregado_en,
         -- Un mandado no tiene local: lo pidió el cliente.
         coalesce(c.nombre, 'Mandado'),
         e.destino_calle,
         e.ganancia_repartidor,
         case when e.cobro_metodo = 'efectivo' then e.cobrar_al_entregar else 0 end
    from public.envios e
    left join public.comercios c on c.id = e.comercio_id
   where public.es_admin()
     and e.repartidor_id = p_rider
     and e.estado = 'entregado'
     and public.dia(e.entregado_en) between p_desde and p_hasta
     and not exists (select 1 from public.liquidacion_items li where li.envio_id = e.id)
   order by e.entregado_en;
$$;

revoke execute on function public.detalle_de_liquidar_rider(uuid, date, date) from public, anon;
grant execute on function public.detalle_de_liquidar_rider(uuid, date, date) to authenticated;

-- Lo mismo para el local: qué pedidos entraron en ese número.
create or replace function public.detalle_de_liquidar_comercio(
  p_comercio uuid,
  p_desde    date,
  p_hasta    date
)
returns table (
  pedido_id  uuid,
  codigo     text,
  entregado  timestamptz,
  cliente    text,
  productos  integer
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.codigo, p.entregado_en, p.cliente_nombre, p.subtotal
    from public.pedidos p
   where public.es_admin()
     and p.comercio_id = p_comercio
     and p.estado = 'entregado'
     and p.liquidacion_id is null
     and public.dia(p.entregado_en) between p_desde and p_hasta
   order by p.entregado_en;
$$;

revoke execute on function public.detalle_de_liquidar_comercio(uuid, date, date) from public, anon;
grant execute on function public.detalle_de_liquidar_comercio(uuid, date, date) to authenticated;
