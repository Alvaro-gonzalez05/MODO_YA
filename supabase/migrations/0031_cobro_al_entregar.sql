-- 0031 - El rider sabe cuanto cobrar al entregar
--
-- Desde 0027 el cliente elige con que paga. Si eligio efectivo o tarjeta
-- (posnet), el que cobra es el rider en la puerta, pero el envio no guardaba
-- nada de eso: el rider llegaba sin saber que tenia que cobrar ni cuanto.
--
-- Ahora el envio de un pedido copia el monto y el medio. Transferencia: el
-- cliente le transfiere a MODO YA, el rider no cobra nada.

alter table public.envios
  add column cobrar_al_entregar integer not null default 0 check (cobrar_al_entregar >= 0),
  add column cobro_metodo public.metodo_pago;

comment on column public.envios.cobrar_al_entregar is
  'Lo que el rider le cobra al cliente al entregar (efectivo o posnet). 0 si ya esta pago o es por transferencia.';

create or replace function public.copiar_cobro_del_pedido()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
begin
  if new.pedido_id is null then
    return new;
  end if;
  select * into ped from public.pedidos where id = new.pedido_id;
  if ped.metodo_pago in ('efectivo', 'tarjeta') then
    new.cobrar_al_entregar := ped.total;
    new.cobro_metodo := ped.metodo_pago;
  end if;
  return new;
end;
$$;

drop trigger if exists envios_copiar_cobro on public.envios;
create trigger envios_copiar_cobro
  before insert on public.envios
  for each row execute function public.copiar_cobro_del_pedido();

-- Envios de pedidos ya aceptados que todavia no se entregaron.
update public.envios e
   set cobrar_al_entregar = p.total, cobro_metodo = p.metodo_pago
  from public.pedidos p
 where p.id = e.pedido_id
   and p.metodo_pago in ('efectivo', 'tarjeta')
   and e.estado not in ('entregado', 'cancelado');

-- Las vistas del rider traen el cobro. Columnas nuevas al final ("create or
-- replace view" no deja moverlas).
create or replace view public.v_envios
with (security_invoker = true)
as
select
  e.id, e.codigo, e.ciudad_id, e.servicio, e.pedido_id,
  e.comercio_id, c.nombre as comercio_nombre,
  e.repartidor_id, public.nombre_repartidor(e.repartidor_id) as repartidor_nombre,
  e.origen_calle, e.origen_referencia,
  extensions.ST_Y(e.origen_ubicacion::extensions.geometry)  as origen_lat,
  extensions.ST_X(e.origen_ubicacion::extensions.geometry)  as origen_lng,
  e.destino_calle, e.destino_referencia,
  extensions.ST_Y(e.destino_ubicacion::extensions.geometry) as destino_lat,
  extensions.ST_X(e.destino_ubicacion::extensions.geometry) as destino_lng,
  e.cliente_nombre, e.cliente_telefono, e.cliente_indicaciones,
  e.distancia_km, e.km_adicionales, e.ganancia_repartidor, e.comision, e.total,
  e.minutos_estimados, e.paga, e.estado, e.codigo_entrega,
  e.creado_en, e.confirmado_en, e.asignado_en, e.en_local_en, e.retirado_en,
  e.entregado_en, e.cancelado_en, e.motivo_cancelacion,
  e.cobrar_al_entregar, e.cobro_metodo
from public.envios e
left join public.comercios c on c.id = e.comercio_id;

create or replace view public.ofertas_abiertas
with (security_invoker = true)
as
select
  o.id as oferta_id, o.envio_id, o.repartidor_id, o.distancia_al_retiro_km,
  o.ofrecida_en, o.expira_en,
  e.codigo, e.comercio_id, c.nombre as comercio_nombre,
  e.origen_calle, e.origen_referencia,
  extensions.ST_Y(e.origen_ubicacion::extensions.geometry) as origen_lat,
  extensions.ST_X(e.origen_ubicacion::extensions.geometry) as origen_lng,
  e.destino_calle,
  extensions.ST_Y(e.destino_ubicacion::extensions.geometry) as destino_lat,
  extensions.ST_X(e.destino_ubicacion::extensions.geometry) as destino_lng,
  e.distancia_km, e.minutos_estimados, e.ganancia_repartidor, e.estado,
  e.cobrar_al_entregar, e.cobro_metodo
from public.ofertas o
join public.envios e on e.id = o.envio_id
left join public.comercios c on c.id = e.comercio_id
where o.respuesta is null and o.expira_en > now();
