-- 0057 - Pre-inscripciones de la landing
--
-- La landing (modoya-landing.vercel.app) tiene dos formularios, "Tengo un
-- local" y "Quiero ser rider", que hasta ahora solo simulaban el envio. Ahora
-- guardan la pre-inscripcion aca y la administracion la ve en el panel como
-- solicitud: la contacta por WhatsApp y la marca como contactada o descartada.
--
-- Quien llena el formulario no tiene cuenta (la app todavia no salio), asi que
-- todo lo publico va por funciones `security definer` que `anon` puede
-- ejecutar. La tabla en si no la toca nadie salvo la administracion.
--
-- La landing tambien lee de aca los locales reales (`landing_locales`) y el
-- contador de locales pre-inscriptos (`landing_preinscriptos`).

create type public.tipo_preinscripcion as enum ('local', 'rider');
create type public.estado_preinscripcion as enum ('pendiente', 'contactada', 'descartada');

create table public.preinscripciones (
  id        uuid primary key default gen_random_uuid(),
  tipo      public.tipo_preinscripcion not null,

  -- Lo que hace falta para contactarla y reconocerla en la lista. El nombre es
  -- el del local o el del rider, segun el tipo.
  nombre    text not null check (length(nombre) between 2 and 80),
  whatsapp  text not null check (length(whatsapp) between 6 and 30),
  email     text check (email is null or length(email) <= 120),

  -- El resto del formulario tal cual llego ("rubro", "horario", "vehiculo"...).
  -- Va en jsonb para que la landing pueda sumar preguntas sin migracion.
  datos     jsonb not null default '{}'::jsonb,

  estado    public.estado_preinscripcion not null default 'pendiente',
  atendida_por uuid references public.perfiles(id),
  atendida_en  timestamptz,

  creado_en timestamptz not null default now()
);

comment on table public.preinscripciones is
  'Formularios de la landing (locales y riders) que esperan que la administracion los contacte.';

create index preinscripciones_creado_idx on public.preinscripciones (creado_en desc);
create index preinscripciones_pendientes_idx on public.preinscripciones (tipo, creado_en) where estado = 'pendiente';

alter table public.preinscripciones enable row level security;

-- Solo la administracion la lee. Cambiar el estado va por la funcion de abajo.
create policy preinscripciones_admin_leer on public.preinscripciones
  for select to authenticated using ((select public.es_admin()));

revoke insert, update, delete on public.preinscripciones from authenticated, anon;

-- ---------------------------------------------------------------------------
-- La landing la manda
-- ---------------------------------------------------------------------------

create or replace function public.preinscribirse(p_tipo text, p_datos jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  t        public.tipo_preinscripcion;
  v_nombre   text;
  v_whatsapp text;
  v_email    text;
  resto    jsonb;
begin
  if p_tipo not in ('local', 'rider') then
    raise exception 'Tipo de pre-inscripcion invalido' using errcode = '22023';
  end if;
  t := p_tipo::public.tipo_preinscripcion;

  if p_datos is null or jsonb_typeof(p_datos) <> 'object' or length(p_datos::text) > 4000 then
    raise exception 'Datos invalidos' using errcode = '22023';
  end if;

  v_nombre   := left(trim(coalesce(p_datos->>case t when 'local' then 'local' else 'nombre' end, '')), 80);
  v_whatsapp := left(trim(coalesce(p_datos->>'whatsapp', '')), 30);
  v_email    := nullif(left(trim(coalesce(p_datos->>'email', '')), 120), '');

  if length(v_nombre) < 2 then
    raise exception 'Falta el nombre' using errcode = '22023';
  end if;
  if length(regexp_replace(v_whatsapp, '\D', '', 'g')) < 8 then
    raise exception 'Falta el WhatsApp' using errcode = '22023';
  end if;

  -- El mismo WhatsApp mandando lo mismo dos veces seguidas (doble clic,
  -- "Inscribir otro local" con los mismos datos): se ignora en silencio.
  if exists (
    select 1 from public.preinscripciones p
     where p.tipo = t and p.whatsapp = v_whatsapp
       and lower(p.nombre) = lower(v_nombre)
       and p.creado_en > now() - interval '10 minutes'
  ) then
    return;
  end if;

  -- Freno grueso contra que alguien llene la tabla con un script.
  if (select count(*) from public.preinscripciones where creado_en > now() - interval '1 hour') >= 120 then
    raise exception 'Demasiadas pre-inscripciones, proba en un rato' using errcode = '54000';
  end if;

  -- Solo se guardan textos cortos; lo que ya va en columnas no se repite.
  select coalesce(jsonb_object_agg(k, left(v, 500)), '{}'::jsonb) into resto
    from jsonb_each_text(p_datos) as e(k, v)
   where k not in ('local', 'nombre', 'whatsapp', 'email', 'tipo', 'fecha')
     and length(k) <= 40
     and coalesce(trim(v), '') <> '';

  insert into public.preinscripciones (tipo, nombre, whatsapp, email, datos)
  values (t, v_nombre, v_whatsapp, v_email, resto);
end;
$$;

revoke execute on function public.preinscribirse(text, jsonb) from public;
grant execute on function public.preinscribirse(text, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- La landing lee
-- ---------------------------------------------------------------------------

-- Los locales aprobados, con lo que se puede mostrar en publico (sin telefono
-- ni direccion). Los abiertos primero.
create or replace function public.landing_locales()
returns table (
  id          uuid,
  nombre      text,
  rubro       text,
  logo_url    text,
  portada_url text,
  demora_min  integer,
  abierto     boolean
)
language sql stable security definer set search_path = public
as $$
  select c.id, c.nombre, coalesce(r.nombre, c.rubro), c.logo_url, c.portada_url,
         c.demora_estimada_min, public.comercio_abierto(c.id)
    from public.comercios c
    left join public.rubros r on r.id = c.rubro_id
   where c.estado_aprobacion = 'aprobado'
   order by public.comercio_abierto(c.id) desc, c.nombre
   limit 30
$$;

revoke execute on function public.landing_locales() from public;
grant execute on function public.landing_locales() to anon, authenticated;

-- Cuantos locales se pre-inscribieron (el contador de la landing).
create or replace function public.landing_preinscriptos()
returns integer
language sql stable security definer set search_path = public
as $$
  select count(*)::int from public.preinscripciones where tipo = 'local' and estado <> 'descartada'
$$;

revoke execute on function public.landing_preinscriptos() from public;
grant execute on function public.landing_preinscriptos() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- La administracion la atiende
-- ---------------------------------------------------------------------------

create or replace function public.admin_marcar_preinscripcion(
  p_id     uuid,
  p_estado public.estado_preinscripcion
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion atiende pre-inscripciones' using errcode = '42501';
  end if;

  update public.preinscripciones
     set estado = p_estado,
         atendida_por = case when p_estado = 'pendiente' then null else auth.uid() end,
         atendida_en  = case when p_estado = 'pendiente' then null else now() end
   where id = p_id;

  if not found then
    raise exception 'La pre-inscripcion no existe' using errcode = 'MY004';
  end if;
end;
$$;

revoke execute on function public.admin_marcar_preinscripcion(uuid, public.estado_preinscripcion) from public, anon;
grant execute on function public.admin_marcar_preinscripcion(uuid, public.estado_preinscripcion) to authenticated;

-- Que el panel se entere en vivo cuando entra una.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'preinscripciones'
  ) then
    alter publication supabase_realtime add table public.preinscripciones;
  end if;
end $$;
