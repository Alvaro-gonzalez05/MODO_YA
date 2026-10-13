-- 0062 - Cargos del rider: lo que se le descuenta de lo que cobra
--
-- Los locales ya tenían `cargos_comercio` —de ahí sale la mensualidad, la
-- publicidad y la penalidad por rechazar—. Los riders no tenían nada: su
-- liquidación era ganancias menos el efectivo que no rindió, y no había forma
-- de cobrarle una bajada, una entrega que no llegó o un faltante.
--
-- **La liquidación es la única vía de cobro que funciona de verdad.** Una
-- tarjeta guardada no se puede retener: el rider puede desconocer el cargo o
-- dar de baja la tarjeta. Lo que sí se puede es descontar de lo que se le va a
-- pagar, que es lo que hacen todas las plataformas.
--
-- **Lo carga la administración, no el sistema.** Que un rider se baje queda
-- registrado solo (`abandonos_envio`, 0061), pero cobrarlo o no lo decide una
-- persona: no es lo mismo bajarse porque sí que porque lo chocaron, y
-- automatizar esa diferencia sale caro de los dos lados.
--
-- Un cargo puede ser negativo: así se devuelve algo cobrado de más sin tener
-- que borrar el registro, igual que en los locales.

create type public.concepto_cargo_rider as enum (
  'abandono',   -- se bajó de un envío que ya había aceptado
  'faltante',   -- el pedido no llegó: comida, plata o ambas
  'ajuste'      -- cualquier otra cosa, con el detalle escrito
);

create table public.cargos_repartidor (
  id            uuid primary key default gen_random_uuid(),
  repartidor_id uuid not null references public.repartidores(id) on delete cascade,
  concepto      public.concepto_cargo_rider not null,
  detalle       text not null,
  -- Positivo: se le descuenta. Negativo: se le devuelve algo cobrado de más.
  monto         integer not null check (monto <> 0),
  fecha         date not null default public.hoy(),
  -- De qué envío salió, cuando sale de uno: sin esto, "Ajuste $8.000" en la
  -- liquidación no se puede explicar tres semanas después.
  envio_id      uuid references public.envios(id) on delete set null,
  liquidacion_id uuid references public.liquidaciones(id) on delete set null,
  creado_por    uuid references public.perfiles(id),
  creado_en     timestamptz not null default now()
);

create index cargos_repartidor_idx on public.cargos_repartidor (repartidor_id, fecha desc);
create index cargos_repartidor_liquidacion_idx on public.cargos_repartidor (liquidacion_id);
create index cargos_repartidor_envio_idx on public.cargos_repartidor (envio_id);

comment on table public.cargos_repartidor is
  'Lo que se le descuenta a un rider en su liquidacion. Lo carga la administracion.';

alter table public.cargos_repartidor enable row level security;

-- El rider ve lo suyo: tiene que poder saber por qué cobra menos.
create policy cargos_repartidor_leer on public.cargos_repartidor
  for select to authenticated
  using (repartidor_id = (select public.mi_repartidor_id()) or (select public.es_admin()));

create policy cargos_repartidor_admin on public.cargos_repartidor
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ---------------------------------------------------------------------------
-- Cargar y sacar un cargo
-- ---------------------------------------------------------------------------

create or replace function public.admin_cargar_a_rider(
  p_rider    uuid,
  p_concepto public.concepto_cargo_rider,
  p_detalle  text,
  p_monto    integer,
  p_envio    uuid default null
)
returns public.cargos_repartidor
language plpgsql security definer set search_path = public
as $$
declare c public.cargos_repartidor;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion carga cargos' using errcode = '42501';
  end if;
  if p_monto = 0 then
    raise exception 'Un cargo de cero no es un cargo' using errcode = 'MY006';
  end if;
  if coalesce(trim(p_detalle), '') = '' then
    raise exception 'Escribí por qué se le cobra' using errcode = 'MY006';
  end if;

  insert into public.cargos_repartidor (repartidor_id, concepto, detalle, monto, envio_id, creado_por)
  values (p_rider, p_concepto, trim(p_detalle), p_monto, p_envio, auth.uid())
  returning * into c;

  return c;
end;
$$;

-- Solo mientras no esté liquidado: después ya se le pagó con ese número.
create or replace function public.admin_borrar_cargo_rider(p_cargo uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion' using errcode = '42501';
  end if;

  delete from public.cargos_repartidor
   where id = p_cargo and liquidacion_id is null;

  if not found then
    raise exception 'El cargo no existe o ya esta liquidado' using errcode = 'MY004';
  end if;
end;
$$;

revoke execute on function public.admin_cargar_a_rider(uuid, public.concepto_cargo_rider, text, integer, uuid) from public, anon;
revoke execute on function public.admin_borrar_cargo_rider(uuid) from public, anon;
grant execute on function public.admin_cargar_a_rider(uuid, public.concepto_cargo_rider, text, integer, uuid) to authenticated;
grant execute on function public.admin_borrar_cargo_rider(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- La liquidación del rider los descuenta
-- ---------------------------------------------------------------------------

drop function if exists public.pendiente_de_liquidar_riders(date, date);

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
  cargos        integer,
  total         integer
)
language sql stable security definer set search_path = public
as $$
  with trabajo as (
    select r.id as repartidor_id, r.nombre,
           count(e.id)::integer as envios,
           coalesce(sum(e.ganancia_repartidor), 0)::integer as ganancias,
           coalesce(sum(e.cobrar_al_entregar) filter (where e.cobro_metodo = 'efectivo'), 0)::integer as efectivo
      from public.repartidores r
      join public.envios e on e.repartidor_id = r.id
     where e.estado = 'entregado'
       and public.dia(e.entregado_en) between p_desde and p_hasta
       and not exists (select 1 from public.liquidacion_items li where li.envio_id = e.id)
     group by r.id, r.nombre
  ), cargos as (
    select c.repartidor_id, coalesce(sum(c.monto), 0)::integer as cargos
      from public.cargos_repartidor c
     where c.liquidacion_id is null and c.fecha between p_desde and p_hasta
     group by c.repartidor_id
  )
  select r.id, r.nombre,
         coalesce(t.envios, 0), coalesce(t.ganancias, 0),
         coalesce(t.efectivo, 0), coalesce(c.cargos, 0),
         coalesce(t.ganancias, 0) - coalesce(t.efectivo, 0) - coalesce(c.cargos, 0)
    from public.repartidores r
    left join trabajo t on t.repartidor_id = r.id
    left join cargos c on c.repartidor_id = r.id
   where public.es_admin()
     and (t.envios is not null or c.cargos is not null)
   order by r.nombre;
$$;

revoke execute on function public.pendiente_de_liquidar_riders(date, date) from public, anon;
grant execute on function public.pendiente_de_liquidar_riders(date, date) to authenticated;

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
  ca  integer;
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

  update public.cargos_repartidor set liquidacion_id = liq.id
   where repartidor_id = p_rider and liquidacion_id is null
     and fecha between p_desde and p_hasta;

  select coalesce(sum(i.monto), 0),
         coalesce(sum(e.cobrar_al_entregar) filter (where e.cobro_metodo = 'efectivo'), 0)
    into g, ef
    from public.liquidacion_items i
    join public.envios e on e.id = i.envio_id
   where i.liquidacion_id = liq.id;

  select coalesce(sum(monto), 0) into ca
    from public.cargos_repartidor where liquidacion_id = liq.id;

  -- El total puede dar negativo: ahí el rider debe, y queda asentado en vez de
  -- perderse.
  update public.liquidaciones
     set ganancias = g, efectivo_cobrado = ef, ajustes = ca, total = g - ef - ca
   where id = liq.id
  returning * into liq;

  return liq;
end;
$$;

-- ---------------------------------------------------------------------------
-- La bandeja de la administración: quién se bajó y si ya se le cobró
-- ---------------------------------------------------------------------------

create or replace view public.v_abandonos
with (security_invoker = true)
as
select
  a.id, a.envio_id, a.repartidor_id, r.nombre as rider,
  a.motivo, a.estado_al_bajarse, a.creado_en,
  e.codigo as envio_codigo,
  e.estado as envio_estado,
  co.nombre as comercio_nombre,
  -- Si ya hay un cargo por ese envío y ese rider, no hay nada que decidir.
  exists (
    select 1 from public.cargos_repartidor c
     where c.envio_id = a.envio_id and c.repartidor_id = a.repartidor_id
  ) as ya_cobrado
from public.abandonos_envio a
left join public.repartidores r on r.id = a.repartidor_id
left join public.envios e on e.id = a.envio_id
left join public.comercios co on co.id = e.comercio_id;
