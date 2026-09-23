-- 0035 - Liquidaciones: que le queda a cada local y a cada rider
--
-- La plata entra toda a MODO YA (tarjeta en la app) o la junta el rider
-- (efectivo). Despues hay que repartirla:
--
--   Local  = lo que vendio en productos
--            - la mensualidad del plan
--            - la publicidad que contrato
--            - ajustes (notas de credito, acuerdos)
--
--   Rider  = la ganancia de los envios que entrego
--            - el efectivo que cobro en la puerta y todavia no rindio
--            - ajustes
--
-- El envio no entra en la cuenta del local: ese dinero es de MODO YA, que le
-- paga al rider su parte y se queda con la comision.
--
-- Ya existian `liquidaciones` (riders) y `suscripciones` (mensualidad). Aca se
-- suman los cargos (publicidad, mensualidad, ajustes) y la liquidacion del
-- local, y se cierra el circulo: una liquidacion cerrada "consume" los pedidos
-- y envios de ese periodo para que no se paguen dos veces.

-- ---------------------------------------------------------------------------
-- 1. Cargos de un local: mensualidad, publicidad, ajustes
-- ---------------------------------------------------------------------------

create type public.concepto_cargo as enum ('mensualidad', 'publicidad', 'ajuste');

create table public.cargos_comercio (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  concepto    public.concepto_cargo not null,
  detalle     text not null,
  -- Positivo: se le descuenta al local. Negativo: se le suma (una devolucion).
  monto       integer not null check (monto <> 0),
  fecha       date not null default current_date,
  liquidacion_id uuid,
  creado_por  uuid references public.perfiles(id),
  creado_en   timestamptz not null default now()
);

create index cargos_comercio_idx on public.cargos_comercio (comercio_id, fecha desc);
create index cargos_comercio_liquidacion_idx on public.cargos_comercio (liquidacion_id);

alter table public.cargos_comercio enable row level security;

create policy cargos_comercio_leer on public.cargos_comercio
  for select to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy cargos_comercio_admin on public.cargos_comercio
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ---------------------------------------------------------------------------
-- 2. Liquidacion de un local
-- ---------------------------------------------------------------------------

create table public.liquidaciones_comercio (
  id            uuid primary key default gen_random_uuid(),
  comercio_id   uuid not null references public.comercios(id) on delete cascade,
  periodo_desde date not null,
  periodo_hasta date not null,

  ventas        integer not null default 0,   -- productos vendidos y cobrados
  cargos        integer not null default 0,   -- mensualidad + publicidad + ajustes
  total         integer not null default 0,   -- ventas - cargos (puede ser negativo)

  estado        public.estado_pago not null default 'pendiente',
  pagada_en     timestamptz,
  observacion   text,
  creado_por    uuid references public.perfiles(id),
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),

  constraint liquidaciones_comercio_periodo check (periodo_hasta >= periodo_desde)
);

create index liquidaciones_comercio_idx
  on public.liquidaciones_comercio (comercio_id, periodo_hasta desc);

create trigger liquidaciones_comercio_tocar
  before update on public.liquidaciones_comercio
  for each row execute function public.tocar_actualizado_en();

alter table public.liquidaciones_comercio enable row level security;

create policy liquidaciones_comercio_leer on public.liquidaciones_comercio
  for select to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy liquidaciones_comercio_admin on public.liquidaciones_comercio
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

alter table public.cargos_comercio
  add constraint cargos_comercio_liquidacion_fk
  foreign key (liquidacion_id) references public.liquidaciones_comercio(id) on delete set null;

-- Que pedido entro en que liquidacion (y que no entre dos veces).
alter table public.pedidos add column liquidacion_id uuid
  references public.liquidaciones_comercio(id) on delete set null;

create index pedidos_liquidacion_idx on public.pedidos (liquidacion_id);

-- ---------------------------------------------------------------------------
-- 3. La liquidacion del rider soporta descuentos
--
-- Antes solo sumaba ganancias (total >= 0). Ahora se le resta el efectivo que
-- cobro en la puerta: si junto mas de lo que gano, el saldo queda negativo y
-- el que tiene que poner plata es el rider.
-- ---------------------------------------------------------------------------

alter table public.liquidaciones
  drop constraint if exists liquidaciones_total_check,
  add column if not exists ganancias integer not null default 0,
  add column if not exists efectivo_cobrado integer not null default 0,
  add column if not exists ajustes integer not null default 0,
  add column if not exists creado_por uuid references public.perfiles(id);

comment on column public.liquidaciones.efectivo_cobrado is
  'Lo que el rider cobro en mano en ese periodo. Se le descuenta: esa plata es de MODO YA.';

-- ---------------------------------------------------------------------------
-- 4. Lo que hay para liquidar (sin cerrar nada): lo que muestra el panel
-- ---------------------------------------------------------------------------

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
       and p.entregado_en::date between p_desde and p_hasta
     group by p.comercio_id
  ), cargos as (
    select c.comercio_id, coalesce(sum(c.monto), 0)::integer as cargos
      from public.cargos_comercio c
     where c.liquidacion_id is null and c.fecha between p_desde and p_hasta
     group by c.comercio_id
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
     and e.entregado_en::date between p_desde and p_hasta
     and not exists (select 1 from public.liquidacion_items li where li.envio_id = e.id)
   group by r.id, r.nombre
   order by r.nombre;
$$;

-- ---------------------------------------------------------------------------
-- 5. Cerrar una liquidacion (queda registrada y no se puede repetir)
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
     and entregado_en::date between p_desde and p_hasta;

  update public.cargos_comercio set liquidacion_id = liq.id
   where comercio_id = p_comercio and liquidacion_id is null
     and fecha between p_desde and p_hasta;

  select coalesce(sum(subtotal), 0) into v from public.pedidos where liquidacion_id = liq.id;
  select coalesce(sum(monto), 0) into c from public.cargos_comercio where liquidacion_id = liq.id;

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
     and e.entregado_en::date between p_desde and p_hasta
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

-- Marcar una liquidacion como pagada (local o rider).
create or replace function public.marcar_liquidacion_pagada(
  p_liquidacion uuid,
  p_es_comercio boolean
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion liquida' using errcode = '42501';
  end if;

  if p_es_comercio then
    update public.liquidaciones_comercio
       set estado = 'acreditado', pagada_en = now() where id = p_liquidacion;
  else
    update public.liquidaciones
       set estado = 'acreditado', pagada_en = now() where id = p_liquidacion;
  end if;
end;
$$;

revoke execute on function public.pendiente_de_liquidar_comercios(date, date) from public, anon;
revoke execute on function public.pendiente_de_liquidar_riders(date, date) from public, anon;
revoke execute on function public.cerrar_liquidacion_comercio(uuid, date, date, text) from public, anon;
revoke execute on function public.cerrar_liquidacion_rider(uuid, date, date, text) from public, anon;
revoke execute on function public.marcar_liquidacion_pagada(uuid, boolean) from public, anon;
grant execute on function public.pendiente_de_liquidar_comercios(date, date) to authenticated;
grant execute on function public.pendiente_de_liquidar_riders(date, date) to authenticated;
grant execute on function public.cerrar_liquidacion_comercio(uuid, date, date, text) to authenticated;
grant execute on function public.cerrar_liquidacion_rider(uuid, date, date, text) to authenticated;
grant execute on function public.marcar_liquidacion_pagada(uuid, boolean) to authenticated;

-- El panel las ve en vivo.
do $$
declare t text;
begin
  foreach t in array array['cargos_comercio', 'liquidaciones_comercio', 'liquidaciones']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
