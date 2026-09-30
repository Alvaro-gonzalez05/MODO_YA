-- 0052 - El cliente puede pedir un rider para un mandado
--
-- Hasta ahora todo envio nacia de un local: `comercio_id` era obligatorio. Un
-- mandado no tiene local — el cliente dice "retirame esto de aca y llevalo
-- alla" — asi que el envio pasa a poder nacer de un comercio **o** de un
-- cliente, nunca de los dos ni de ninguno.
--
-- **El rider no adelanta plata.** Solo retira y entrega: un paquete, algo que
-- el cliente ya pago, la ropa de la tintoreria. Se cobra el envio y nada mas.
-- Que el rider ponga plata de su bolsillo abre un problema distinto (topes,
-- que pasa si el cliente no aparece) y se decidio dejarlo afuera.
--
-- El mandado se crea y sale a buscar rider **en una sola llamada**. El envio
-- del comercio lo hace en dos RPC sin transaccion, y si la segunda falla queda
-- un envio trabado en `cotizado` sin forma de confirmarlo (hallazgo 10 de
-- docs/hallazgos-de-la-revision.md). Aca no se repite ese hueco.

alter table public.envios
  alter column comercio_id drop not null,
  add column cliente_id uuid references public.clientes(id);

comment on column public.envios.cliente_id is
  'Quien pidio el mandado. Nulo en los envios de un local, que son los que tienen comercio_id.';

create index envios_cliente_idx on public.envios (cliente_id, creado_en desc);

-- Un envio es de un local o de un cliente. Las dos cosas a la vez no significa
-- nada, y ninguna de las dos dejaria sin saber a quien mostrarselo ni a quien
-- cobrarle.
alter table public.envios
  add constraint envios_de_un_local_o_de_un_cliente check (
    (comercio_id is not null and cliente_id is null)
    or (comercio_id is null and cliente_id is not null)
  );

-- ---------------------------------------------------------------------------
-- Quien lo ve y quien lo cancela
-- ---------------------------------------------------------------------------

drop policy if exists envios_leer on public.envios;

create policy envios_leer on public.envios
  for select to authenticated
  using (
    comercio_id = (select public.mi_comercio_id())
    or cliente_id = (select public.mi_cliente_id())
    or repartidor_id = (select public.mi_repartidor_id())
    or (select public.es_admin())
    or exists (
      select 1 from public.ofertas o
      where o.envio_id = envios.id
        and o.repartidor_id = (select public.mi_repartidor_id())
        and o.respuesta is null
        and o.expira_en > now()
    )
  );

create or replace function public.cancelar_envio(
  p_envio  uuid,
  p_motivo text
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare e public.envios;
begin
  update public.envios
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_envio
     and (comercio_id = public.mi_comercio_id()
          or cliente_id = public.mi_cliente_id()
          or repartidor_id = public.mi_repartidor_id()
          or public.es_admin())
  returning * into e;

  if e.id is null then
    raise exception 'El envio no existe o no podes cancelarlo' using errcode = '42501';
  end if;

  if e.repartidor_id is not null then
    update public.repartidores set ocupado = false where id = e.repartidor_id;
  end if;

  update public.ofertas set respuesta = 'expirada', respondida_en = now()
   where envio_id = p_envio and respuesta is null;

  return e;
end;
$$;

-- ---------------------------------------------------------------------------
-- Cuanto sale
-- ---------------------------------------------------------------------------

create or replace function public.cotizar_mandado(
  p_origen_lat  double precision,
  p_origen_lng  double precision,
  p_destino_lat double precision,
  p_destino_lng double precision
)
returns table (
  distancia_km      numeric,
  minutos_estimados integer,
  total             integer
)
language sql stable security definer set search_path = public, extensions
as $$
  select c.distancia_km, c.minutos_estimados, c.total
    from public.clientes cl
    cross join lateral public.cotizar(
      cl.ciudad_id,
      extensions.ST_SetSRID(extensions.ST_MakePoint(p_origen_lng, p_origen_lat), 4326)::extensions.geography,
      extensions.ST_SetSRID(extensions.ST_MakePoint(p_destino_lng, p_destino_lat), 4326)::extensions.geography
    ) c
   where cl.id = public.mi_cliente_id();
$$;

-- ---------------------------------------------------------------------------
-- Pedirlo
-- ---------------------------------------------------------------------------

create or replace function public.crear_mandado(
  p_origen_calle       text,
  p_origen_lat         double precision,
  p_origen_lng         double precision,
  p_destino_calle      text,
  p_destino_lat        double precision,
  p_destino_lng        double precision,
  p_que_retirar        text,
  p_destino_referencia text default null
)
returns public.envios
language plpgsql security definer set search_path = public, extensions
as $$
declare
  cli public.clientes;
  per public.perfiles;
  cot record;
  e   public.envios;
  origen  extensions.geography;
  destino extensions.geography;
begin
  select * into cli from public.clientes where id = public.mi_cliente_id();
  if cli.id is null then
    raise exception 'Solo un cliente puede pedir un mandado' using errcode = '42501';
  end if;

  if coalesce(trim(p_que_retirar), '') = '' then
    raise exception 'Hay que decir que tiene que retirar el rider' using errcode = 'MY006';
  end if;

  select * into per from public.perfiles where id = cli.perfil_id;
  if coalesce(trim(coalesce(per.telefono, cli.telefono, '')), '') = '' then
    raise exception 'Cargá un teléfono para que el rider pueda ubicarte' using errcode = 'MY006';
  end if;

  origen  := extensions.ST_SetSRID(extensions.ST_MakePoint(p_origen_lng, p_origen_lat), 4326)::extensions.geography;
  destino := extensions.ST_SetSRID(extensions.ST_MakePoint(p_destino_lng, p_destino_lat), 4326)::extensions.geography;

  select * into cot from public.cotizar(cli.ciudad_id, origen, destino);

  insert into public.envios (
    ciudad_id, cliente_id,
    origen_calle, origen_referencia, origen_ubicacion,
    destino_calle, destino_referencia, destino_ubicacion,
    cliente_nombre, cliente_telefono,
    tarifario_id, distancia_km, km_adicionales,
    ganancia_repartidor, comision, minutos_estimados,
    paga, estado,
    -- El mandado lo paga el cliente al rider, en la puerta. No hay pasarela
    -- de por medio: es el mismo cobro en mano que ya sabe hacer el rider.
    cobrar_al_entregar, cobro_metodo,
    confirmado_en
  ) values (
    cli.ciudad_id, cli.id,
    p_origen_calle, p_que_retirar, origen,
    p_destino_calle, p_destino_referencia, destino,
    cli.nombre, coalesce(per.telefono, cli.telefono),
    cot.tarifario_id, cot.distancia_km, cot.km_adicionales,
    cot.ganancia_repartidor, cot.comision, cot.minutos_estimados,
    'cliente', 'buscando_repartidor',
    cot.total, 'efectivo',
    now()
  ) returning * into e;

  perform public.ofrecer_al_siguiente(e.id);
  return e;
end;
$$;

revoke execute on function public.cotizar_mandado(double precision, double precision, double precision, double precision)
  from public, anon;
revoke execute on function public.crear_mandado(text, double precision, double precision, text, double precision, double precision, text, text)
  from public, anon;
grant execute on function public.cotizar_mandado(double precision, double precision, double precision, double precision)
  to authenticated;
grant execute on function public.crear_mandado(text, double precision, double precision, text, double precision, double precision, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- La vista dice de quien es
-- ---------------------------------------------------------------------------
-- La columna va al final a proposito: `create or replace view` deja agregar
-- columnas nuevas solo despues de las que ya estaban.

create or replace view public.v_envios
with (security_invoker = true)
as
select
  e.id, e.codigo, e.ciudad_id, e.servicio, e.pedido_id,
  e.comercio_id, c.nombre as comercio_nombre,
  e.repartidor_id, public.nombre_repartidor(e.repartidor_id) as repartidor_nombre,
  e.origen_calle, e.origen_referencia,
  extensions.ST_Y(e.origen_ubicacion::extensions.geometry) as origen_lat,
  extensions.ST_X(e.origen_ubicacion::extensions.geometry) as origen_lng,
  e.destino_calle, e.destino_referencia,
  extensions.ST_Y(e.destino_ubicacion::extensions.geometry) as destino_lat,
  extensions.ST_X(e.destino_ubicacion::extensions.geometry) as destino_lng,
  e.cliente_nombre, e.cliente_telefono, e.cliente_indicaciones,
  e.distancia_km, e.km_adicionales, e.ganancia_repartidor, e.comision, e.total,
  e.minutos_estimados, e.paga, e.estado, e.codigo_entrega,
  e.creado_en, e.confirmado_en, e.asignado_en, e.en_local_en, e.retirado_en,
  e.entregado_en, e.cancelado_en, e.motivo_cancelacion,
  e.cobrar_al_entregar, e.cobro_metodo,
  e.cliente_id
from public.envios e
left join public.comercios c on c.id = e.comercio_id;
