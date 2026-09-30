-- 0051 - El local puede tener su propio rider
--
-- Un local que ya tiene un cadete de confianza quiere que sus envios los haga
-- el, no cualquiera del pool.
--
-- **Lo unico que cambia es a quien se le ofrece primero.** La plata sigue igual
-- que siempre: MODO YA cobra su comision y le liquida al rider como a cualquier
-- otro. Asi no hay dos formas de cobrar el mismo servicio ni un caso aparte en
-- la liquidacion.
--
-- Y es *preferencia*, no exclusividad: si el rider del local no contesta a
-- tiempo, la busqueda sigue con el resto. Un pedido no se puede quedar trabado
-- porque el cadete de confianza dejo el celular en la mochila.

create table public.comercio_riders (
  comercio_id   uuid not null references public.comercios(id) on delete cascade,
  repartidor_id uuid not null references public.repartidores(id) on delete cascade,
  creado_en     timestamptz not null default now(),

  primary key (comercio_id, repartidor_id)
);

comment on table public.comercio_riders is
  'Riders de confianza de un local: se les ofrece primero sus envios. No cambia como se cobra ni como se liquida.';

create index comercio_riders_rider_idx on public.comercio_riders (repartidor_id);

alter table public.comercio_riders enable row level security;

-- El local arma su propia lista.
create policy comercio_riders_del_local on public.comercio_riders
  for all to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()))
  with check (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

-- El rider ve para que locales quedo anotado. No lo decide el: que lo elijan
-- no le saca nada (sigue pudiendo rechazar la oferta), pero tiene derecho a
-- saberlo.
create policy comercio_riders_el_rider on public.comercio_riders
  for select to authenticated
  using (repartidor_id = (select public.mi_repartidor_id()));

-- ---------------------------------------------------------------------------
-- El motor ofrece primero al rider del local
-- ---------------------------------------------------------------------------
--
-- Dos cambios sobre la version anterior:
--
--   1. El orden: primero los del local, despues por cercania.
--   2. El rider del local **no pasa por el filtro de radio**. El radio existe
--      para no ofrecerle un envio a alguien que esta lejos y va a tardar; pero
--      si el local lo eligio a proposito, que este a cuatro cuadras o a tres
--      kilometros lo decide el local, no nosotros.
--
-- Lo demas se mantiene: tiene que estar aprobado, conectado y libre.

create or replace function public.repartidores_cercanos(p_envio uuid)
returns table (repartidor_id uuid, distancia_km numeric)
language sql stable security definer set search_path = public, extensions
as $$
  select r.id,
         round((extensions.ST_Distance(r.ultima_ubicacion, e.origen_ubicacion)
                / 1000)::numeric, 2)
  from public.envios e
  join public.tarifarios t on t.id = e.tarifario_id
  join public.repartidores r
    on r.ciudad_id = e.ciudad_id
   and r.estado_aprobacion = 'aprobado'
   and r.conectado
   and not r.ocupado
   and r.ultima_ubicacion is not null
   and (
     exists (select 1 from public.comercio_riders cr
              where cr.comercio_id = e.comercio_id and cr.repartidor_id = r.id)
     or extensions.ST_DWithin(
          r.ultima_ubicacion, e.origen_ubicacion, t.radio_busqueda_km * 1000
        )
   )
  where e.id = p_envio
    and not exists (
      select 1 from public.ofertas o
      where o.repartidor_id = r.id and o.respuesta is null and o.expira_en > now()
    )
    and not exists (
      select 1 from public.ofertas o
      where o.envio_id = e.id and o.repartidor_id = r.id
        and o.ofrecida_en > now() - interval '1 minute'
    )
  order by
    not exists (select 1 from public.comercio_riders cr
                 where cr.comercio_id = e.comercio_id and cr.repartidor_id = r.id),
    2
$$;

-- ---------------------------------------------------------------------------
-- Lo que consulta el panel del local
-- ---------------------------------------------------------------------------

-- Los riders que el local puede elegir: los aprobados de su ciudad. En un
-- pueblo se conocen por nombre, asi que alcanza con el nombre y el vehiculo.
create or replace function public.riders_para_elegir()
returns table (
  repartidor_id uuid,
  nombre        text,
  vehiculo      public.vehiculo,
  conectado     boolean,
  es_mio        boolean
)
language sql stable security definer set search_path = public
as $$
  select r.id, r.nombre, r.vehiculo, r.conectado,
         exists (select 1 from public.comercio_riders cr
                  where cr.comercio_id = public.mi_comercio_id()
                    and cr.repartidor_id = r.id)
    from public.repartidores r
   where public.mi_comercio_id() is not null
     and r.estado_aprobacion = 'aprobado'
     and r.ciudad_id = (select ciudad_id from public.comercios
                         where id = public.mi_comercio_id())
   order by r.nombre;
$$;

revoke execute on function public.riders_para_elegir() from public, anon;
grant execute on function public.riders_para_elegir() to authenticated;

-- El local ve en vivo si su rider se conecta.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'comercio_riders'
  ) then
    alter publication supabase_realtime add table public.comercio_riders;
  end if;
end $$;
