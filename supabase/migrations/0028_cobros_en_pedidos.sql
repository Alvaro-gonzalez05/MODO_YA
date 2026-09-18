-- 0028 - Estado del cobro en la vista de pedidos
--
-- La administracion ya no aprueba pedidos: lleva los cobros (0027). Para eso
-- la vista trae el estado del pago. Es security_invoker: el cliente y el
-- local no leen `pagos` (RLS), asi que para ellos la columna viene vacia.

create or replace view public.v_pedidos
with (security_invoker = true)
as
select
  p.id, p.codigo, p.ciudad_id, p.estado,
  p.cliente_id, p.cliente_nombre, p.cliente_telefono,
  p.comercio_id, c.nombre as comercio_nombre, c.logo_url as comercio_logo_url,
  p.entrega_calle, p.entrega_referencia,
  extensions.ST_Y(p.entrega_ubicacion::extensions.geometry) as entrega_lat,
  extensions.ST_X(p.entrega_ubicacion::extensions.geometry) as entrega_lng,
  p.subtotal, p.costo_envio, p.total, p.metodo_pago,
  p.envio_id, p.envio_minutos_estimados,
  p.nota_cliente, p.motivo_rechazo, p.motivo_cancelacion,
  p.creado_en, p.pagado_en, p.aceptado_en, p.listo_en, p.entregado_en, p.cancelado_en,
  pg.estado as pago_estado
from public.pedidos p
left join public.comercios c on c.id = p.comercio_id
left join public.pagos pg on pg.id = p.pago_id;

-- Los cobros se ven en vivo en el panel de la administracion.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pagos'
  ) then
    alter publication supabase_realtime add table public.pagos;
  end if;
end;
$$;
