-- 0036 - Campañas del local y MODO YA Plus
--
-- Dos formas de que un local invierta para vender mas, las dos con un tope de
-- gasto que el pone:
--
--   * publicidad: aparece destacado en la app. Gasta hasta X por dia.
--   * plus: a los clientes con MODO YA Plus les regala el envio. El local
--     absorbe ese envio (el rider y la comision se pagan igual).
--
-- El local NO pone la plata por adelantado: cada gasto se le descuenta de lo
-- que vende, en la liquidacion (0035). Por eso la campania tiene un
-- presupuesto: es el tope de lo que esta dispuesto a gastar.
--
-- MODO YA Plus del lado del cliente es una suscripcion mensual: mientras este
-- al dia, en los locales adheridos ve "Envio gratis".

create type public.tipo_campania as enum ('publicidad', 'plus');
create type public.estado_campania as enum ('activa', 'pausada', 'sin_fondo', 'finalizada');

create table public.campanias (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  tipo        public.tipo_campania not null,
  estado      public.estado_campania not null default 'activa',

  -- Tope total de la campania y tope por dia (publicidad).
  presupuesto       integer not null check (presupuesto > 0),
  presupuesto_diario integer check (presupuesto_diario > 0),

  desde       date not null default current_date,
  hasta       date,

  creado_por  uuid references public.perfiles(id),
  creado_en   timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),

  constraint campanias_periodo check (hasta is null or hasta >= desde),
  -- La publicidad se cobra por dia; Plus se cobra por envio regalado.
  constraint campanias_diario check (
    (tipo = 'publicidad' and presupuesto_diario is not null) or
    (tipo = 'plus' and presupuesto_diario is null)
  )
);

create index campanias_comercio_idx on public.campanias (comercio_id, estado);

create trigger campanias_tocar
  before update on public.campanias
  for each row execute function public.tocar_actualizado_en();

-- Cada peso gastado, con su motivo. Es lo que despues se le descuenta.
create table public.campania_gastos (
  id          uuid primary key default gen_random_uuid(),
  campania_id uuid not null references public.campanias(id) on delete cascade,
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  fecha       date not null default current_date,
  detalle     text not null,
  monto       integer not null check (monto > 0),
  -- Plus: el pedido cuyo envio se regalo.
  pedido_id   uuid references public.pedidos(id) on delete set null,
  liquidacion_id uuid references public.liquidaciones_comercio(id) on delete set null,
  creado_en   timestamptz not null default now(),

  -- La publicidad se cobra una vez por dia.
  constraint campania_gastos_un_dia unique (campania_id, fecha, pedido_id)
);

create index campania_gastos_comercio_idx on public.campania_gastos (comercio_id, fecha desc);
create index campania_gastos_liquidacion_idx on public.campania_gastos (liquidacion_id);

alter table public.campanias enable row level security;
alter table public.campania_gastos enable row level security;

-- El local maneja las suyas; la administracion ve todo.
create policy campanias_propias on public.campanias
  for all to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()))
  with check (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy campania_gastos_leer on public.campania_gastos
  for select to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy campania_gastos_admin on public.campania_gastos
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ---------------------------------------------------------------------------
-- MODO YA Plus: la suscripcion del cliente
-- ---------------------------------------------------------------------------

create table public.suscripciones_plus (
  id         uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  desde      date not null default current_date,
  hasta      date not null,
  precio     integer not null check (precio >= 0),
  pago_id    uuid references public.pagos(id),
  renovar    boolean not null default true,
  creado_en  timestamptz not null default now(),

  constraint suscripciones_plus_periodo check (hasta > desde)
);

create index suscripciones_plus_cliente_idx on public.suscripciones_plus (cliente_id, hasta desc);

alter table public.suscripciones_plus enable row level security;

create policy suscripciones_plus_propias on public.suscripciones_plus
  for select to authenticated
  using (cliente_id = (select public.mi_cliente_id()) or (select public.es_admin()));

create policy suscripciones_plus_admin on public.suscripciones_plus
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- Precio de Plus: donde ya viven las demas reglas configurables.
alter table public.tarifarios
  add column precio_plus_mensual integer not null default 2500 check (precio_plus_mensual >= 0);

comment on column public.tarifarios.precio_plus_mensual is
  'Lo que paga por mes un cliente de MODO YA Plus (envio gratis en los locales adheridos).';

-- ---------------------------------------------------------------------------
-- Lo que la app necesita preguntar
-- ---------------------------------------------------------------------------

-- ¿Este cliente tiene Plus al día?
create or replace function public.tiene_plus(p_cliente uuid default null)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.suscripciones_plus s
    where s.cliente_id = coalesce(p_cliente, public.mi_cliente_id())
      and current_date between s.desde and s.hasta
  );
$$;

-- Lo que le queda por gastar a una campaña (nunca menos de cero).
create or replace function public.fondo_disponible(p_campania uuid)
returns integer
language sql stable security definer set search_path = public
as $$
  select greatest(
    0,
    (select c.presupuesto from public.campanias c where c.id = p_campania)
    - coalesce((select sum(g.monto) from public.campania_gastos g where g.campania_id = p_campania), 0)
  );
$$;

-- La campaña Plus activa de un local, si todavía tiene fondo.
create or replace function public.campania_plus_activa(p_comercio uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select c.id
    from public.campanias c
   where c.comercio_id = p_comercio
     and c.tipo = 'plus'
     and c.estado = 'activa'
     and current_date >= c.desde
     and (c.hasta is null or current_date <= c.hasta)
     and public.fondo_disponible(c.id) > 0
   limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Rendimiento de una campaña (lo que ve el local)
-- ---------------------------------------------------------------------------

create or replace function public.rendimiento_campania(
  p_campania uuid,
  p_desde date default null,
  p_hasta date default null
)
returns table (
  ingresos  integer,   -- lo que vendio en productos en ese periodo
  pedidos   integer,
  costo     integer,   -- lo que gasto la campania
  retorno   numeric    -- ingresos / costo
)
language sql stable security definer set search_path = public
as $$
  with c as (
    select * from public.campanias where id = p_campania
  ), rango as (
    select coalesce(p_desde, (select desde from c)) as d,
           coalesce(p_hasta, current_date) as h
  ), ventas as (
    select coalesce(sum(p.subtotal), 0)::integer as ingresos, count(*)::integer as pedidos
      from public.pedidos p, c, rango
     where p.comercio_id = c.comercio_id
       and p.estado = 'entregado'
       and p.entregado_en::date between rango.d and rango.h
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
-- Gasto diario de la publicidad (pg_cron, una vez por dia)
-- ---------------------------------------------------------------------------

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
       and current_date >= desde and (hasta is null or current_date <= hasta)
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

select cron.schedule('publicidad-del-dia', '5 3 * * *', 'select public.cobrar_dia_de_publicidad()')
 where not exists (select 1 from cron.job where jobname = 'publicidad-del-dia');

-- ---------------------------------------------------------------------------
-- La liquidacion del local descuenta tambien lo gastado en campanias
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

revoke execute on function public.cobrar_dia_de_publicidad() from public, anon, authenticated;
revoke execute on function public.tiene_plus(uuid) from public, anon;
revoke execute on function public.fondo_disponible(uuid) from public, anon;
revoke execute on function public.campania_plus_activa(uuid) from public, anon;
revoke execute on function public.rendimiento_campania(uuid, date, date) from public, anon;
grant execute on function public.tiene_plus(uuid) to authenticated;
grant execute on function public.fondo_disponible(uuid) to authenticated;
grant execute on function public.campania_plus_activa(uuid) to authenticated;
grant execute on function public.rendimiento_campania(uuid, date, date) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['campanias', 'campania_gastos', 'suscripciones_plus']
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
