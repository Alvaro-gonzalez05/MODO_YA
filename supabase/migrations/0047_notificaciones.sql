-- 0047 - Notificaciones: la administracion le escribe a la gente
--
-- Hasta ahora la app solo avisaba con sonidos adentro de la pantalla (0.. el
-- timbre del local, la marimba del rider). Eso sirve para lo que pasa ahora
-- mismo, pero no para hablarle a alguien: "abrimos los domingos", "volve que
-- te extranamos", "tu local favorito tiene 30% hoy".
--
-- Este modulo es el *contenido y a quien va*. El *como llega* es aparte y se
-- suma despues sin tocar estas tablas:
--
--   1. Adentro de la app (lo que entra ahora): cada destinatario tiene su fila
--      en `notificacion_envios` y la ve en su campanita, en vivo por Realtime.
--   2. Push al celular (pendiente): hace falta un proyecto de Firebase. Cuando
--      este, se agrega la tabla de tokens y una Edge Function que ademas de
--      insertar el envio le pegue a FCM. El resto queda igual.
--
-- Por eso el envio se guarda fila por fila y no como "un mensaje para todos":
-- asi se sabe quien lo leyo, el cliente ve solo lo suyo, y el dia que haya push
-- cada fila ya tiene a quien mandarselo.

-- ---------------------------------------------------------------------------
-- 1. A quien le llega
-- ---------------------------------------------------------------------------

create type public.segmento_notificacion as enum (
  'todos',              -- clientes, locales y riders
  'clientes',           -- todos los clientes
  'clientes_plus',      -- los que hoy tienen MODO YA Plus
  'clientes_inactivos', -- sin pedidos en los ultimos N dias (o que nunca pidieron)
  'comercios',          -- locales aprobados
  'riders'              -- riders aprobados
);

-- Que abre la notificacion cuando la tocan. `local` usa `destino_id`.
create type public.destino_notificacion as enum (
  'ninguno', 'inicio', 'mis_pedidos', 'plus', 'local'
);

create type public.estado_notificacion as enum ('borrador', 'enviada');

create table public.notificaciones (
  id        uuid primary key default gen_random_uuid(),

  titulo    text not null check (length(titulo) between 1 and 80),
  cuerpo    text not null check (length(cuerpo) between 1 and 300),

  segmento  public.segmento_notificacion not null default 'clientes',
  -- Solo para 'clientes_inactivos'. El periodo lo elige la administracion al
  -- escribir el mensaje: no es lo mismo "hace una semana" que "hace tres meses".
  dias_inactividad smallint not null default 30 check (dias_inactividad between 1 and 365),

  destino    public.destino_notificacion not null default 'ninguno',
  destino_id uuid,

  estado     public.estado_notificacion not null default 'borrador',
  enviada_en timestamptz,
  -- Cuanta gente la recibio. Se completa al enviar y no se recalcula: si
  -- manana entran clientes nuevos, esta notificacion no les llego.
  alcance    integer not null default 0,

  creado_por uuid references public.perfiles(id),
  creado_en  timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),

  constraint notificaciones_local_con_id
    check (destino <> 'local' or destino_id is not null)
);

comment on table public.notificaciones is
  'Mensajes que la administracion le manda a un segmento de gente. Un envio por destinatario en notificacion_envios.';

create trigger notificaciones_tocar
  before update on public.notificaciones
  for each row execute function public.tocar_actualizado_en();

create table public.notificacion_envios (
  id              uuid primary key default gen_random_uuid(),
  notificacion_id uuid not null references public.notificaciones(id) on delete cascade,
  perfil_id       uuid not null references public.perfiles(id) on delete cascade,
  leida_en        timestamptz,
  creado_en       timestamptz not null default now(),

  unique (notificacion_id, perfil_id)
);

-- La campanita pregunta siempre "lo mio, lo no leido primero".
create index notificacion_envios_perfil_idx
  on public.notificacion_envios (perfil_id, creado_en desc);

-- ---------------------------------------------------------------------------
-- 2. Resolver el segmento
-- ---------------------------------------------------------------------------
--
-- Devuelve los perfiles de un segmento. Se usa dos veces: para mostrar "llega a
-- 143 personas" antes de mandar, y para mandar. Que sea la misma funcion evita
-- que el numero que se ve y el que se manda se separen.

-- `p_dias` va en integer y no en smallint (aunque la columna sea smallint):
-- un literal suelto como 30 es integer, y Postgres no lo baja solo al resolver
-- la funcion. Con smallint, cada llamada necesitaria `30::smallint`.
create or replace function public.destinatarios(
  p_segmento public.segmento_notificacion,
  p_dias     integer default 30
)
returns table (perfil_id uuid)
language sql stable security definer set search_path = public
as $$
  select p.id
    from public.perfiles p
   where public.es_admin()
     and case p_segmento
           when 'todos' then
             exists (select 1 from public.clientes c where c.perfil_id = p.id)
             or exists (select 1 from public.comercios co
                         where co.perfil_id = p.id and co.estado_aprobacion = 'aprobado')
             or exists (select 1 from public.repartidores r
                         where r.perfil_id = p.id and r.estado_aprobacion = 'aprobado')

           when 'clientes' then
             exists (select 1 from public.clientes c where c.perfil_id = p.id)

           when 'clientes_plus' then
             exists (select 1 from public.clientes c
                      where c.perfil_id = p.id and public.tiene_plus(c.id))

           when 'clientes_inactivos' then
             exists (
               select 1 from public.clientes c
                where c.perfil_id = p.id
                  -- Nunca pidio, o su ultimo pedido quedo fuera de la ventana.
                  and coalesce(
                        (select max(pe.creado_en) from public.pedidos pe where pe.cliente_id = c.id),
                        c.creado_en
                      ) < now() - make_interval(days => p_dias)
             )

           when 'comercios' then
             exists (select 1 from public.comercios co
                      where co.perfil_id = p.id and co.estado_aprobacion = 'aprobado')

           when 'riders' then
             exists (select 1 from public.repartidores r
                      where r.perfil_id = p.id and r.estado_aprobacion = 'aprobado')
         end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Mandarla
-- ---------------------------------------------------------------------------

create or replace function public.enviar_notificacion(p_notificacion uuid)
returns public.notificaciones
language plpgsql security definer set search_path = public
as $$
declare
  n public.notificaciones;
  cuantos integer;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion manda notificaciones' using errcode = '42501';
  end if;

  select * into n from public.notificaciones where id = p_notificacion for update;
  if n.id is null then
    raise exception 'La notificacion no existe' using errcode = 'MY004';
  end if;
  -- Dos clicks en el boton no tienen que mandarla dos veces.
  if n.estado = 'enviada' then
    raise exception 'Esa notificacion ya se mando' using errcode = 'MY006';
  end if;

  insert into public.notificacion_envios (notificacion_id, perfil_id)
  select n.id, d.perfil_id from public.destinatarios(n.segmento, n.dias_inactividad) d
  on conflict do nothing;

  get diagnostics cuantos = row_count;

  if cuantos = 0 then
    raise exception 'No hay nadie en ese segmento' using errcode = 'MY006';
  end if;

  update public.notificaciones
     set estado = 'enviada', enviada_en = now(), alcance = cuantos
   where id = n.id
  returning * into n;

  return n;
end;
$$;

-- Cuanta gente la recibiria hoy, para mostrarlo antes de mandar.
create or replace function public.alcance_de(
  p_segmento public.segmento_notificacion,
  p_dias     integer default 30
)
returns integer
language sql stable security definer set search_path = public
as $$
  select count(*)::integer from public.destinatarios(p_segmento, p_dias);
$$;

-- El cliente marca la suya como leida. No hay policy de update sobre
-- `notificacion_envios`: todo lo que cambia estado pasa por una funcion.
create or replace function public.marcar_notificacion_leida(p_envio uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.notificacion_envios
     set leida_en = coalesce(leida_en, now())
   where id = p_envio and perfil_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 4. Lo que ve cada uno
-- ---------------------------------------------------------------------------

alter table public.notificaciones     enable row level security;
alter table public.notificacion_envios enable row level security;

-- Las escribe y las mira solo la administracion...
create policy notificaciones_admin on public.notificaciones
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ...salvo las que le llegaron a uno, que necesita leer para mostrarlas.
-- `notificaciones.id` va calificado a proposito: `notificacion_envios` tambien
-- tiene una columna `id`, y sin calificar Postgres la resuelve contra la tabla
-- de adentro (`e.notificacion_id = e.id`), que nunca da true.
create policy notificaciones_las_mias on public.notificaciones
  for select to authenticated
  using (exists (select 1 from public.notificacion_envios e
                  where e.notificacion_id = public.notificaciones.id
                    and e.perfil_id = (select auth.uid())));

create policy notificacion_envios_admin on public.notificacion_envios
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

create policy notificacion_envios_los_mios on public.notificacion_envios
  for select to authenticated
  using (perfil_id = (select auth.uid()));

-- La campanita del cliente: su bandeja, sin tener que cruzar dos tablas.
create or replace view public.v_notificaciones
with (security_invoker = true)
as
select
  e.id            as envio_id,
  e.perfil_id,
  e.leida_en,
  e.creado_en,
  n.id            as notificacion_id,
  n.titulo,
  n.cuerpo,
  n.destino,
  n.destino_id
from public.notificacion_envios e
join public.notificaciones n on n.id = e.notificacion_id
where n.estado = 'enviada';

-- El panel: cada notificacion con cuanta gente la abrio. "Llego a 140 y la
-- leyeron 12" es lo unico que dice si el mensaje sirvio o no.
create or replace view public.v_notificaciones_admin
with (security_invoker = true)
as
select
  n.*,
  (select count(*) from public.notificacion_envios e
    where e.notificacion_id = n.id and e.leida_en is not null)::integer as leidas
from public.notificaciones n;

-- ---------------------------------------------------------------------------
-- 5. Permisos y tiempo real
-- ---------------------------------------------------------------------------

revoke execute on function public.destinatarios(public.segmento_notificacion, integer) from public, anon;
revoke execute on function public.enviar_notificacion(uuid) from public, anon;
revoke execute on function public.alcance_de(public.segmento_notificacion, integer) from public, anon;
revoke execute on function public.marcar_notificacion_leida(uuid) from public, anon;
grant execute on function public.destinatarios(public.segmento_notificacion, integer) to authenticated;
grant execute on function public.enviar_notificacion(uuid) to authenticated;
grant execute on function public.alcance_de(public.segmento_notificacion, integer) to authenticated;
grant execute on function public.marcar_notificacion_leida(uuid) to authenticated;

-- La campanita se prende sola cuando entra una, sin recargar la pantalla.
do $$
declare t text;
begin
  foreach t in array array['notificaciones', 'notificacion_envios']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
