-- 0039 - Vista de campañas y alta de MODO YA Plus
--
-- La vista evita que la app pregunte el fondo campaña por campaña.
-- `activar_plus` la llama la Edge Function `pagar-pedido` cuando el cliente
-- paga la suscripcion con tarjeta (service_role): crea o extiende el mes.

create or replace view public.v_campanias
with (security_invoker = true)
as
select
  c.id, c.comercio_id, co.nombre as comercio_nombre,
  c.tipo, c.estado, c.presupuesto, c.presupuesto_diario,
  c.desde, c.hasta, c.creado_en,
  coalesce((select sum(g.monto) from public.campania_gastos g where g.campania_id = c.id), 0)::integer as gastado,
  public.fondo_disponible(c.id) as disponible
from public.campanias c
left join public.comercios co on co.id = c.comercio_id;

-- Precio mensual de Plus (lo fija la administracion en el tarifario).
create or replace function public.precio_plus()
returns integer
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select t.precio_plus_mensual from public.tarifarios t
      where t.vigente_hasta is null
      order by t.vigente_desde desc limit 1),
    2500);
$$;

-- Activa o renueva Plus por 30 dias. Solo la Edge Function (service_role).
create or replace function public.activar_plus(
  p_cliente uuid,
  p_precio  integer,
  p_pago    uuid default null
)
returns public.suscripciones_plus
language plpgsql security definer set search_path = public
as $$
declare
  s public.suscripciones_plus;
  fin date;
begin
  -- Si ya tiene, se le suma un mes a lo que le quedaba.
  select max(hasta) into fin from public.suscripciones_plus
   where cliente_id = p_cliente and hasta >= current_date;

  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, pago_id)
  values (p_cliente, coalesce(fin, current_date), coalesce(fin, current_date) + 30, p_precio, p_pago)
  returning * into s;

  return s;
end;
$$;

-- Cuando vence, deja de aplicar solo (tiene_plus mira las fechas): no hace
-- falta ningun proceso que lo apague.

revoke execute on function public.activar_plus(uuid, integer, uuid) from public, anon, authenticated;
revoke execute on function public.precio_plus() from public, anon;
grant execute on function public.precio_plus() to authenticated;
