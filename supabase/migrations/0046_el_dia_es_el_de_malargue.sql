-- 0046 - El día es el de Malargüe, no el del servidor
--
-- La base corre en UTC. Mendoza está en UTC-3, así que todas las noches, entre
-- las 21:00 y la medianoche hora de Malargüe, el servidor ya cree que es el día
-- siguiente. Todo lo que se decidía con `current_date` (o con un
-- `timestamptz::date`, que castea con la zona de la sesión) usaba ese día
-- adelantado.
--
-- Se veía en `tests/promociones.sql`, que fallaba 9 de 13 comprobaciones si se
-- corría de noche: `promociones.desde` nacía con el día de mañana (default
-- `current_date`, UTC) mientras `promocion_vigente()` comparaba contra el día de
-- Mendoza. El local creaba una promo a las 21:30 y no regía hasta el otro día.
--
-- El mismo desfase, más silencioso, corría la liquidación: un pedido entregado a
-- las 22:00 del domingo contaba como del lunes, así que el cierre "hasta el
-- domingo" lo dejaba afuera y caía en el período siguiente. Justo la franja de
-- las cenas, que es cuando más se entrega.
--
-- La regla queda una sola: **el día es el de Malargüe**. Las dos funciones de
-- acá abajo son el único lugar donde se escribe la zona horaria, y las usan
-- tanto los defaults de las columnas `date` como las comparaciones.

-- ---------------------------------------------------------------------------
-- 1. Qué día es
-- ---------------------------------------------------------------------------

-- `stable`, no `immutable`: las reglas de husos horarios cambian con el tiempo.
create or replace function public.dia(p_momento timestamptz)
returns date
language sql stable
as $$
  select (p_momento at time zone 'America/Argentina/Mendoza')::date
$$;

create or replace function public.hoy()
returns date
language sql stable
as $$
  select public.dia(now())
$$;

comment on function public.dia(timestamptz) is
  'El día de Malargüe en que ocurrió un momento dado. Reemplaza a ::date, que castea con la zona de la sesión (UTC).';
comment on function public.hoy() is
  'El día de hoy en Malargüe. Reemplaza a current_date, que en el servidor va tres horas adelantado.';

-- ---------------------------------------------------------------------------
-- 2. Las fechas que se estampan solas
-- ---------------------------------------------------------------------------

alter table public.promociones        alter column desde set default public.hoy();
alter table public.campanias          alter column desde set default public.hoy();
alter table public.campania_gastos    alter column fecha set default public.hoy();
alter table public.suscripciones_plus alter column desde set default public.hoy();
alter table public.cargos_comercio    alter column fecha set default public.hoy();

-- Las filas ya cargadas no se tocan: como mucho están corridas un día y
-- reescribirlas podría mover una suscripción paga o una liquidación cerrada.

-- ---------------------------------------------------------------------------
-- 3. Campañas y MODO YA Plus
-- ---------------------------------------------------------------------------

create or replace function public.tiene_plus(p_cliente uuid default null)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.suscripciones_plus s
    where s.cliente_id = coalesce(p_cliente, public.mi_cliente_id())
      and public.hoy() between s.desde and s.hasta
  );
$$;

create or replace function public.campania_plus_activa(p_comercio uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select c.id
    from public.campanias c
   where c.comercio_id = p_comercio
     and c.tipo = 'plus'
     and c.estado = 'activa'
     and public.hoy() >= c.desde
     and (c.hasta is null or public.hoy() <= c.hasta)
     and public.fondo_disponible(c.id) > 0
   limit 1;
$$;

create or replace function public.cobrar_dia_de_publicidad()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  c public.campanias;
  n integer := 0;
  libre integer;
begin
  for c in
    select * from public.campanias
     where tipo = 'publicidad' and estado = 'activa'
       and public.hoy() >= desde and (hasta is null or public.hoy() <= hasta)
  loop
    libre := public.fondo_disponible(c.id);
    if libre <= 0 then
      update public.campanias set estado = 'sin_fondo' where id = c.id;
      continue;
    end if;

    insert into public.campania_gastos (campania_id, comercio_id, detalle, monto)
    values (c.id, c.comercio_id, 'Publicidad del dia', least(c.presupuesto_diario, libre))
    on conflict do nothing;

    if public.fondo_disponible(c.id) = 0 then
      update public.campanias set estado = 'sin_fondo' where id = c.id;
    end if;
    n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function public.plus_por_renovar()
returns table(suscripcion_id uuid, cliente_id uuid, mp_card_id text, precio integer)
language sql stable security definer set search_path = public
as $$
  select s.id, s.cliente_id, t.mp_card_id, public.precio_plus()
    from public.suscripciones_plus s
    join lateral (
      select g.mp_card_id
        from public.tarjetas_guardadas g
       where g.cliente_id = s.cliente_id
       order by g.predeterminada desc, g.creado_en desc
       limit 1
    ) t on true
   where s.renovar
     and s.intentos_fallidos < 3
     and s.hasta <= public.hoy()
     -- Solo la ultima: si ya se renovo, la vieja no se vuelve a cobrar.
     and s.hasta = (
       select max(x.hasta) from public.suscripciones_plus x where x.cliente_id = s.cliente_id
     );
$$;

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
   where cliente_id = p_cliente and hasta >= public.hoy();

  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, pago_id)
  values (
    p_cliente,
    coalesce(fin, public.hoy()),
    (coalesce(fin, public.hoy()) + interval '1 month')::date,
    p_precio,
    p_pago
  )
  returning * into s;

  return s;
end;
$$;

create or replace function public.rendimiento_campania(
  p_campania uuid,
  p_desde    date default null,
  p_hasta    date default null
)
returns table(ingresos integer, pedidos integer, costo integer, retorno numeric)
language sql stable security definer set search_path = public
as $$
  with c as (
    select * from public.campanias where id = p_campania
  ), rango as (
    select coalesce(p_desde, (select desde from c)) as d,
           coalesce(p_hasta, public.hoy()) as h
  ), ventas as (
    select coalesce(sum(p.subtotal), 0)::integer as ingresos, count(*)::integer as pedidos
      from public.pedidos p, c, rango
     where p.comercio_id = c.comercio_id
       and p.estado = 'entregado'
       and public.dia(p.entregado_en) between rango.d and rango.h
       -- Plus: solo los pedidos que efectivamente usaron el beneficio.
       and (c.tipo = 'publicidad'
            or exists (select 1 from public.campania_gastos g
                        where g.campania_id = c.id and g.pedido_id = p.id))
  ), gastos as (
    select coalesce(sum(g.monto), 0)::integer as costo
      from public.campania_gastos g, rango
     where g.campania_id = p_campania and g.fecha between rango.d and rango.h
  )
  select v.ingresos, v.pedidos, g.costo,
         case when g.costo = 0 then 0 else round(v.ingresos::numeric / g.costo, 2) end
    from ventas v, gastos g;
$$;

-- ---------------------------------------------------------------------------
-- 4. La vidriera: el local destacado deja de estarlo a la medianoche de acá
-- ---------------------------------------------------------------------------

create or replace view public.v_comercios
with (security_invoker = true)
as
select
  c.id, c.perfil_id, c.ciudad_id,
  c.nombre, c.rubro, c.rubro_id, r.nombre as rubro_nombre,
  c.telefono, c.calle, c.referencia,
  extensions.ST_Y(c.ubicacion::extensions.geometry) as lat,
  extensions.ST_X(c.ubicacion::extensions.geometry) as lng,
  c.logo_url, c.acepta_pedidos, c.demora_estimada_min,
  c.estado_aprobacion, c.creado_en,
  public.comercio_abierto(c.id) as abierto,
  c.portada_url,
  public.campania_plus_activa(c.id) is not null as plus,
  exists (
    select 1 from public.campanias ca
     where ca.comercio_id = c.id and ca.tipo = 'publicidad' and ca.estado = 'activa'
       and public.hoy() >= ca.desde and (ca.hasta is null or public.hoy() <= ca.hasta)
       and public.fondo_disponible(ca.id) > 0
  ) as destacado,
  (
    select max(pr.porcentaje) from public.promociones pr
     where pr.comercio_id = c.id and public.promocion_vigente(pr.id)
  ) as descuento
from public.comercios c
left join public.rubros r on r.id = c.rubro_id;

-- ---------------------------------------------------------------------------
-- 5. Liquidaciones: el período va de medianoche a medianoche de Malargüe
-- ---------------------------------------------------------------------------
--
-- `p_desde`/`p_hasta` son los días que elige la administración en el panel, o
-- sea días de Malargüe. Antes se comparaban contra `entregado_en::date`, que es
-- el día del servidor: la cena del último día del período se iba al siguiente.

create or replace function public.pendiente_de_liquidar_comercios(
  p_desde date,
  p_hasta date
)
returns table (
  comercio_id uuid,
  comercio    text,
  pedidos     integer,
  ventas      integer,
  cargos      integer,
  total       integer
)
language sql stable security definer set search_path = public
as $$
  with ventas as (
    select p.comercio_id, count(*)::integer as pedidos, coalesce(sum(p.subtotal), 0)::integer as ventas
      from public.pedidos p
     where p.estado = 'entregado'
       and p.liquidacion_id is null
       and public.dia(p.entregado_en) between p_desde and p_hasta
     group by p.comercio_id
  ), cargos as (
    select x.comercio_id, sum(x.monto)::integer as cargos from (
      select c.comercio_id, c.monto
        from public.cargos_comercio c
       where c.liquidacion_id is null and c.fecha between p_desde and p_hasta
      union all
      -- Publicidad y envios regalados con Plus.
      select g.comercio_id, g.monto
        from public.campania_gastos g
       where g.liquidacion_id is null and g.fecha between p_desde and p_hasta
    ) x group by x.comercio_id
  )
  select co.id, co.nombre,
         coalesce(v.pedidos, 0), coalesce(v.ventas, 0), coalesce(c.cargos, 0),
         coalesce(v.ventas, 0) - coalesce(c.cargos, 0)
    from public.comercios co
    left join ventas v on v.comercio_id = co.id
    left join cargos c on c.comercio_id = co.id
   where public.es_admin()
     and (v.pedidos is not null or c.cargos is not null)
   order by co.nombre;
$$;

create or replace function public.pendiente_de_liquidar_riders(
  p_desde date,
  p_hasta date
)
returns table (
  repartidor_id uuid,
  rider         text,
  envios        integer,
  ganancias     integer,
  efectivo      integer,
  total         integer
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.nombre,
         count(e.id)::integer,
         coalesce(sum(e.ganancia_repartidor), 0)::integer,
         coalesce(sum(e.cobrar_al_entregar) filter (where e.cobro_metodo = 'efectivo'), 0)::integer,
         (coalesce(sum(e.ganancia_repartidor), 0)
          - coalesce(sum(e.cobrar_al_entregar) filter (where e.cobro_metodo = 'efectivo'), 0))::integer
    from public.repartidores r
    join public.envios e on e.repartidor_id = r.id
   where public.es_admin()
     and e.estado = 'entregado'
     and public.dia(e.entregado_en) between p_desde and p_hasta
     and not exists (select 1 from public.liquidacion_items li where li.envio_id = e.id)
   group by r.id, r.nombre
   order by r.nombre;
$$;

create or replace function public.cerrar_liquidacion_comercio(
  p_comercio uuid,
  p_desde    date,
  p_hasta    date,
  p_observacion text default null
)
returns public.liquidaciones_comercio
language plpgsql security definer set search_path = public
as $$
declare
  liq public.liquidaciones_comercio;
  v   integer;
  c   integer;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion liquida' using errcode = '42501';
  end if;

  insert into public.liquidaciones_comercio (comercio_id, periodo_desde, periodo_hasta, observacion, creado_por)
  values (p_comercio, p_desde, p_hasta, p_observacion, auth.uid())
  returning * into liq;

  update public.pedidos set liquidacion_id = liq.id
   where comercio_id = p_comercio
     and estado = 'entregado'
     and liquidacion_id is null
     and public.dia(entregado_en) between p_desde and p_hasta;

  update public.cargos_comercio set liquidacion_id = liq.id
   where comercio_id = p_comercio and liquidacion_id is null
     and fecha between p_desde and p_hasta;

  update public.campania_gastos set liquidacion_id = liq.id
   where comercio_id = p_comercio and liquidacion_id is null
     and fecha between p_desde and p_hasta;

  select coalesce(sum(subtotal), 0) into v from public.pedidos where liquidacion_id = liq.id;
  select coalesce((select sum(monto) from public.cargos_comercio where liquidacion_id = liq.id), 0)
       + coalesce((select sum(monto) from public.campania_gastos where liquidacion_id = liq.id), 0)
    into c;

  update public.liquidaciones_comercio
     set ventas = v, cargos = c, total = v - c
   where id = liq.id
  returning * into liq;

  return liq;
end;
$$;

create or replace function public.cerrar_liquidacion_rider(
  p_rider uuid,
  p_desde date,
  p_hasta date,
  p_observacion text default null
)
returns public.liquidaciones
language plpgsql security definer set search_path = public
as $$
declare
  liq public.liquidaciones;
  g   integer;
  ef  integer;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion liquida' using errcode = '42501';
  end if;

  insert into public.liquidaciones (repartidor_id, periodo_desde, periodo_hasta, observacion, creado_por)
  values (p_rider, p_desde, p_hasta, p_observacion, auth.uid())
  returning * into liq;

  insert into public.liquidacion_items (liquidacion_id, envio_id, monto)
  select liq.id, e.id, e.ganancia_repartidor
    from public.envios e
   where e.repartidor_id = p_rider
     and e.estado = 'entregado'
     and public.dia(e.entregado_en) between p_desde and p_hasta
     and not exists (select 1 from public.liquidacion_items li where li.envio_id = e.id);

  select coalesce(sum(i.monto), 0),
         coalesce(sum(e.cobrar_al_entregar) filter (where e.cobro_metodo = 'efectivo'), 0)
    into g, ef
    from public.liquidacion_items i
    join public.envios e on e.id = i.envio_id
   where i.liquidacion_id = liq.id;

  update public.liquidaciones
     set ganancias = g, efectivo_cobrado = ef, total = g - ef
   where id = liq.id
  returning * into liq;

  return liq;
end;
$$;
