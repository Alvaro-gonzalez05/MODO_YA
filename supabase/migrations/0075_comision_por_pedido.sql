-- 0075 - Comisión por pedido y costo del cobro con tarjeta
--
-- Hasta acá MODO YA le cobraba al local la mensualidad, la publicidad y las
-- penalidades, pero nada por cada pedido. Y cada pedido le cuesta: todos se
-- cobran con tarjeta en la cuenta de Mercado Pago de MODO YA, que se queda con
-- un porcentaje (alrededor del 8% en Argentina, con la plata disponible en el
-- momento). Sin trasladarlo, cada venta del local le costaba plata a MODO YA.
--
-- Dos porcentajes nuevos en el tarifario, los dos editables desde Tarifas y
-- reglas, los dos sobre los **productos** del pedido (el envío es de MODO YA):
--
--   * `comision_pedido_pct`: la ganancia de MODO YA por pedido. Arranca en 10%.
--   * `costo_cobro_pct`: lo que cobra Mercado Pago, que se le traslada al
--     local. Arranca en 8%. En cero, MODO YA lo absorbe.
--
-- Se **congelan en cada pedido** al crearlo (`pedidos.comision_pct`,
-- `costo_cobro_pct` y sus montos). Si la administración cambia el porcentaje,
-- los pedidos que ya existían se liquidan con el que tenían: el local tiene que
-- poder reconstruir cada número, y un cambio de tarifa no puede ser retroactivo.
--
-- En la liquidación entran como dos renglones más de "Descuentos" (uno por
-- porcentaje), así la hoja, el PDF, el resumen y el cierre siguen sumando lo
-- mismo sin cambiar de forma.
--
-- De paso: `admin_nuevo_tarifario` no copiaba `penalidad_rechazo_pct` (0060) al
-- tarifario nuevo, así que guardar cualquier tarifa la devolvía al 50% por
-- defecto. El mismo error que 0049 arregló con el precio de Plus.

-- ---------------------------------------------------------------------------
-- El tarifario
-- ---------------------------------------------------------------------------

alter table public.tarifarios
  add column if not exists comision_pedido_pct numeric(5,2) not null default 0
    check (comision_pedido_pct between 0 and 100),
  add column if not exists costo_cobro_pct numeric(5,2) not null default 0
    check (costo_cobro_pct between 0 and 100);

comment on column public.tarifarios.comision_pedido_pct is
  'Ganancia de MODO YA por pedido, en % de los productos. Se le descuenta al local.';
comment on column public.tarifarios.costo_cobro_pct is
  'Lo que cobra Mercado Pago por cada pago con tarjeta, en % de los productos. Se le traslada al local; en 0 lo absorbe MODO YA.';

-- Los valores que pidió la clienta para arrancar.
update public.tarifarios
   set comision_pedido_pct = 10, costo_cobro_pct = 8
 where vigente_hasta is null and servicio = 'delivery';

-- ---------------------------------------------------------------------------
-- Cada pedido guarda los suyos
-- ---------------------------------------------------------------------------

-- Los pedidos que ya existían quedan en cero: cobrarles una comisión que no
-- existía cuando se hicieron sería retroactivo.
alter table public.pedidos
  add column if not exists comision_pct    numeric(5,2) not null default 0,
  add column if not exists comision        integer      not null default 0,
  add column if not exists costo_cobro_pct numeric(5,2) not null default 0,
  add column if not exists costo_cobro     integer      not null default 0;

-- Trigger y no un cambio en `crear_pedido`: así vale por cualquier camino por
-- el que nazca un pedido, y el monto se recalcula solo si cambia el subtotal
-- (`crear_pedido` inserta el pedido y recién después suma los renglones).
create or replace function public.pedido_congela_comision()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  t public.tarifarios;
begin
  if tg_op = 'INSERT' then
    t := public.tarifario_vigente(new.ciudad_id, 'delivery');
    new.comision_pct    := coalesce(t.comision_pedido_pct, 0);
    new.costo_cobro_pct := coalesce(t.costo_cobro_pct, 0);
  end if;
  new.comision    := round(coalesce(new.subtotal, 0) * new.comision_pct / 100);
  new.costo_cobro := round(coalesce(new.subtotal, 0) * new.costo_cobro_pct / 100);
  return new;
end;
$$;

revoke execute on function public.pedido_congela_comision() from public, anon, authenticated;

drop trigger if exists pedidos_congela_comision on public.pedidos;
create trigger pedidos_congela_comision
  before insert or update of subtotal on public.pedidos
  for each row execute function public.pedido_congela_comision();

-- "10%" y no "10.00%"; "8,5%" y no "8.50%".
create or replace function public.pct_legible(p numeric)
returns text
language sql immutable set search_path = public
as $$
  select replace(rtrim(rtrim(p::text, '0'), '.'), '.', ',') || '%';
$$;

-- "$45.000", como lo escribe la app.
create or replace function public.pesos_legibles(p bigint)
returns text
language sql immutable set search_path = public
as $$
  select '$' || replace(to_char(p, 'FM999,999,999,990'), ',', '.');
$$;

-- ---------------------------------------------------------------------------
-- La liquidación: lo que hay para liquidar
-- ---------------------------------------------------------------------------

-- Misma firma que 0069. Las comisiones de los pedidos del período entran en
-- `cargos`, igual que la mensualidad.
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
         and g.revertido_en is null
      union all
      -- Comisión y costo del cobro, congelados en cada pedido (0075).
      select p.comercio_id, p.comision + p.costo_cobro
        from public.pedidos p
       where p.estado = 'entregado'
         and p.liquidacion_id is null
         and public.dia(p.entregado_en) between p_desde and p_hasta
         and p.comision + p.costo_cobro > 0
    ) x group by x.comercio_id
  )
  select co.id, co.nombre,
         coalesce(v.pedidos, 0), coalesce(v.ventas, 0), coalesce(c.cargos, 0),
         coalesce(v.ventas, 0) - coalesce(c.cargos, 0)
    from public.comercios co
    left join ventas v on v.comercio_id = co.id
    left join cargos c on c.comercio_id = co.id
   where ((select public.es_admin()) or co.id = (select public.mi_comercio_id()))
     and (v.pedidos is not null or c.cargos is not null)
   order by co.nombre;
$$;

-- Los renglones de "Descuentos" del período. Las comisiones van agrupadas por
-- porcentaje: un renglón por "10% de $45.000 en 5 pedidos", no uno por pedido,
-- que en un mes cargado serían cientos.
create or replace function public.cargos_a_liquidar_comercio(
  p_comercio uuid,
  p_desde    date,
  p_hasta    date
)
returns table (
  fecha    date,
  concepto text,
  detalle  text,
  monto    integer
)
language sql stable security definer set search_path = public
as $$
  with suyos as (
    select p.*
      from public.pedidos p
     where p.comercio_id = p_comercio
       and p.estado = 'entregado'
       and p.liquidacion_id is null
       and public.dia(p.entregado_en) between p_desde and p_hasta
  )
  select x.fecha, x.concepto, x.detalle, x.monto
    from (
      select c.fecha, c.concepto::text as concepto, c.detalle, c.monto, c.creado_en
        from public.cargos_comercio c
       where c.comercio_id = p_comercio
         and c.liquidacion_id is null
         and c.fecha between p_desde and p_hasta
      union all
      select g.fecha, 'campania'::text, g.detalle, g.monto, g.creado_en
        from public.campania_gastos g
       where g.comercio_id = p_comercio
         and g.liquidacion_id is null
         and g.fecha between p_desde and p_hasta
         and g.revertido_en is null
      union all
      select max(public.dia(s.entregado_en)), 'comision'::text,
             public.pct_legible(s.comision_pct) || ' de ' || public.pesos_legibles(sum(s.subtotal))
               || ' en ' || count(*) || case when count(*) = 1 then ' pedido' else ' pedidos' end,
             sum(s.comision)::integer, max(s.entregado_en)
        from suyos s where s.comision > 0
       group by s.comision_pct
      union all
      select max(public.dia(s.entregado_en)), 'costo_cobro'::text,
             public.pct_legible(s.costo_cobro_pct) || ' de ' || public.pesos_legibles(sum(s.subtotal))
               || ': lo que cobra Mercado Pago por las tarjetas',
             sum(s.costo_cobro)::integer, max(s.entregado_en)
        from suyos s where s.costo_cobro > 0
       group by s.costo_cobro_pct
    ) x
   where ((select public.es_admin()) or p_comercio = (select public.mi_comercio_id()))
   order by x.fecha, x.creado_en;
$$;

-- ---------------------------------------------------------------------------
-- La liquidación: el cierre y lo cerrado
-- ---------------------------------------------------------------------------

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
     and fecha between p_desde and p_hasta
     and revertido_en is null;

  select coalesce(sum(subtotal), 0) into v from public.pedidos where liquidacion_id = liq.id;
  select coalesce((select sum(monto) from public.cargos_comercio where liquidacion_id = liq.id), 0)
       + coalesce((select sum(monto) from public.campania_gastos where liquidacion_id = liq.id), 0)
       + coalesce((select sum(comision + costo_cobro) from public.pedidos where liquidacion_id = liq.id), 0)
    into c;

  update public.liquidaciones_comercio
     set ventas = v, cargos = c, total = v - c
   where id = liq.id
  returning * into liq;

  return liq;
end;
$$;

-- Los renglones de una liquidación ya cerrada, con las comisiones agrupadas
-- igual que en el período en curso.
create or replace function public.renglones_de_liquidacion_comercio(p_liquidacion uuid)
returns table (
  seccion text,
  titulo  text,
  cuando  timestamptz,
  detalle text,
  monto   integer
)
language sql stable security definer set search_path = public
as $$
  with mia as (
    select l.id
      from public.liquidaciones_comercio l
     where l.id = p_liquidacion
       and ((select public.es_admin()) or l.comercio_id = (select public.mi_comercio_id()))
  ), suyos as (
    select p.* from public.pedidos p where p.liquidacion_id in (select id from mia)
  )
  select 'pedidos'::text, s.codigo, s.entregado_en, s.cliente_nombre, s.subtotal
    from suyos s
  union all
  select 'cargos'::text, c.concepto::text, c.fecha::timestamptz, c.detalle, c.monto
    from public.cargos_comercio c
   where c.liquidacion_id in (select id from mia)
  union all
  select 'cargos'::text, 'campania'::text, g.fecha::timestamptz, g.detalle, g.monto
    from public.campania_gastos g
   where g.liquidacion_id in (select id from mia)
  union all
  select 'cargos'::text, 'comision'::text, max(s.entregado_en),
         public.pct_legible(s.comision_pct) || ' de ' || public.pesos_legibles(sum(s.subtotal))
           || ' en ' || count(*) || case when count(*) = 1 then ' pedido' else ' pedidos' end,
         sum(s.comision)::integer
    from suyos s where s.comision > 0
   group by s.comision_pct
  union all
  select 'cargos'::text, 'costo_cobro'::text, max(s.entregado_en),
         public.pct_legible(s.costo_cobro_pct) || ' de ' || public.pesos_legibles(sum(s.subtotal))
           || ': lo que cobra Mercado Pago por las tarjetas',
         sum(s.costo_cobro)::integer
    from suyos s where s.costo_cobro > 0
   group by s.costo_cobro_pct
  order by 1 desc, 3;
$$;

-- ---------------------------------------------------------------------------
-- Guardar el tarifario
-- ---------------------------------------------------------------------------

-- Cambia la firma (dos parámetros nuevos): hay que borrar la de 0049, o queda
-- una segunda función y la llamada se vuelve ambigua.
drop function if exists public.admin_nuevo_tarifario(
  uuid, integer, integer, integer, numeric, numeric, integer, integer, tipo_servicio, integer);

create or replace function public.admin_nuevo_tarifario(
  p_ciudad                   uuid,
  p_ganancia_repartidor_base integer,
  p_comision_modo_ya         integer,
  p_precio_km_adicional      integer,
  p_km_incluidos             numeric,
  p_radio_busqueda_km        numeric,
  p_segundos_para_aceptar    integer,
  p_precio_suscripcion_mensual integer default null,
  p_servicio                 tipo_servicio default 'delivery',
  p_precio_plus_mensual      integer default null,
  p_comision_pedido_pct      numeric default null,
  p_costo_cobro_pct          numeric default null
)
returns public.tarifarios
language plpgsql security definer set search_path = public
as $$
declare
  t      public.tarifarios;
  previo public.tarifarios;
begin
  perform public.exigir_admin();

  if coalesce(p_comision_pedido_pct, 0) not between 0 and 100
     or coalesce(p_costo_cobro_pct, 0) not between 0 and 100 then
    raise exception 'Los porcentajes van de 0 a 100' using errcode = 'MY006';
  end if;

  -- Se lee antes de cerrarlo: de ahi sale lo que no vino por parametro. Todo
  -- lo que no está en la pantalla tiene que venir de acá, o guardar una tarifa
  -- lo devuelve a su valor por defecto sin que nadie se entere (0049, 0075).
  select * into previo from public.tarifarios
   where ciudad_id = p_ciudad and servicio = p_servicio and vigente_hasta is null;

  update public.tarifarios set vigente_hasta = now()
   where ciudad_id = p_ciudad and servicio = p_servicio and vigente_hasta is null;

  insert into public.tarifarios (
    ciudad_id, servicio, ganancia_repartidor_base, comision_modo_ya,
    precio_km_adicional, km_incluidos, radio_busqueda_km, segundos_para_aceptar,
    precio_suscripcion_mensual, precio_plus_mensual, penalidad_rechazo_pct,
    comision_pedido_pct, costo_cobro_pct, creado_por
  ) values (
    p_ciudad, p_servicio, p_ganancia_repartidor_base, p_comision_modo_ya,
    p_precio_km_adicional, p_km_incluidos, p_radio_busqueda_km, p_segundos_para_aceptar,
    coalesce(p_precio_suscripcion_mensual, previo.precio_suscripcion_mensual),
    coalesce(p_precio_plus_mensual, previo.precio_plus_mensual, 2500),
    coalesce(previo.penalidad_rechazo_pct, 50),
    coalesce(p_comision_pedido_pct, previo.comision_pedido_pct, 0),
    coalesce(p_costo_cobro_pct, previo.costo_cobro_pct, 0),
    auth.uid()
  ) returning * into t;

  return t;
end;
$$;

revoke execute on function public.admin_nuevo_tarifario(
  uuid, integer, integer, integer, numeric, numeric, integer, integer, tipo_servicio, integer, numeric, numeric)
  from public, anon;
grant execute on function public.admin_nuevo_tarifario(
  uuid, integer, integer, integer, numeric, numeric, integer, integer, tipo_servicio, integer, numeric, numeric)
  to authenticated;
