-- 0002 - Comercios, repartidores y documentacion
--
-- Ni los comercios ni los cadetes se activan solos: la administracion los
-- aprueba (seccion 12 del documento de la clienta). Por eso todos arrancan en
-- `pendiente` y la condicion de poder operar se evalua siempre contra
-- `estado_aprobacion`.

create table public.comercios (
  id           uuid primary key default gen_random_uuid(),
  perfil_id    uuid not null unique references public.perfiles(id) on delete cascade,
  ciudad_id    uuid not null references public.ciudades(id),

  nombre       text not null,
  rubro        text not null,
  telefono     text not null,

  -- Direccion de retiro. La referencia en texto libre importa tanto como la
  -- calle: en Malargue la numeracion no siempre es confiable.
  calle        text not null,
  referencia   text,
  ubicacion    extensions.geography(Point, 4326),

  logo_url     text,

  estado_aprobacion estado_aprobacion not null default 'pendiente',
  aprobado_en  timestamptz,
  aprobado_por uuid references public.perfiles(id),
  motivo_rechazo text,

  creado_en    timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index comercios_ciudad_idx on public.comercios (ciudad_id);
create index comercios_estado_idx on public.comercios (estado_aprobacion);
create index comercios_ubicacion_idx on public.comercios using gist (ubicacion);

create trigger comercios_tocar
  before update on public.comercios
  for each row execute function public.tocar_actualizado_en();

-- ---------------------------------------------------------------------------

create table public.repartidores (
  id           uuid primary key default gen_random_uuid(),
  perfil_id    uuid not null unique references public.perfiles(id) on delete cascade,
  ciudad_id    uuid not null references public.ciudades(id),

  nombre       text not null,
  telefono     text not null,
  vehiculo     vehiculo not null,
  foto_url     text,

  estado_aprobacion estado_aprobacion not null default 'pendiente',
  aprobado_en  timestamptz,
  aprobado_por uuid references public.perfiles(id),
  motivo_rechazo text,

  -- El cadete apreto "Conectarme": comparte ubicacion y puede recibir ofertas.
  conectado    boolean not null default false,
  conectado_en timestamptz,

  -- Ya tiene un envio en curso. El motor de asignacion no debe ofrecerle otro.
  ocupado      boolean not null default false,

  -- Ultima posicion conocida. Deliberadamente es un upsert sobre una sola fila
  -- y no una tabla de historico: guardar cada ping de GPS infla la base sin
  -- necesidad. El seguimiento en vivo va por Realtime Broadcast.
  ultima_ubicacion    extensions.geography(Point, 4326),
  ultima_ubicacion_en timestamptz,

  reputacion         numeric(3,2) not null default 5.00
                     check (reputacion >= 0 and reputacion <= 5),
  viajes_completados integer not null default 0 check (viajes_completados >= 0),
  viajes_cancelados  integer not null default 0 check (viajes_cancelados >= 0),

  creado_en    timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index repartidores_ciudad_idx on public.repartidores (ciudad_id);
create index repartidores_ubicacion_idx
  on public.repartidores using gist (ultima_ubicacion);

-- Indice parcial: el motor de asignacion solo mira cadetes elegibles, y son
-- una fraccion chica del total.
create index repartidores_elegibles_idx
  on public.repartidores (ciudad_id)
  where estado_aprobacion = 'aprobado' and conectado and not ocupado;

create trigger repartidores_tocar
  before update on public.repartidores
  for each row execute function public.tocar_actualizado_en();

-- ---------------------------------------------------------------------------
-- Documentacion del cadete
--
-- Que documentos se exigen por tipo de vehiculo sigue pendiente de definicion
-- con la clienta, asi que el tipo es texto libre y la lista exigida se
-- configura en `documentos_exigidos`. Cambiar el requisito es un update, no una
-- migracion.

create table public.documentos_exigidos (
  id        uuid primary key default gen_random_uuid(),
  vehiculo  vehiculo not null,
  tipo      text not null,
  obligatorio boolean not null default true,
  constraint documentos_exigidos_unico unique (vehiculo, tipo)
);

create table public.documentos_repartidor (
  id            uuid primary key default gen_random_uuid(),
  repartidor_id uuid not null references public.repartidores(id) on delete cascade,
  tipo          text not null,
  archivo_url   text,
  estado        estado_aprobacion not null default 'pendiente',
  vence_en      date,
  validado_por  uuid references public.perfiles(id),
  validado_en   timestamptz,
  observacion   text,
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint documentos_repartidor_unico unique (repartidor_id, tipo)
);

create index documentos_repartidor_idx
  on public.documentos_repartidor (repartidor_id);

create trigger documentos_repartidor_tocar
  before update on public.documentos_repartidor
  for each row execute function public.tocar_actualizado_en();
