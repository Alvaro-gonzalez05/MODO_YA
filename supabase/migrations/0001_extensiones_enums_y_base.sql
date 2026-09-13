-- 0001 - Extensiones, tipos y tablas base
--
-- Convenciones de todo el esquema:
--   * Nombres en espanol y en singular para columnas, plural para tablas.
--   * Todas las tablas llevan `creado_en` / `actualizado_en` en timestamptz.
--   * Los ids son uuid v4; la clave legible para el usuario va aparte
--     (por ejemplo `envios.codigo` = 'MY-8492').
--   * Los importes son integer en pesos enteros: no hay centavos en el
--     producto y evitamos por completo los errores de punto flotante.

create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto   with schema extensions;
create extension if not exists postgis    with schema extensions;

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------

-- Los valores coinciden exactamente con los `wire` de los enums de Dart
-- (packages/my_core/lib/src/models/estados.dart). Si cambia uno, cambian los dos.

create type rol_usuario as enum ('comercio', 'repartidor', 'admin');

create type estado_aprobacion as enum (
  'pendiente', 'aprobado', 'rechazado', 'suspendido'
);

create type estado_envio as enum (
  'borrador',
  'cotizado',
  'buscando_repartidor',
  'asignado',
  'en_local',
  'retirado',
  'en_camino',
  'entregado',
  'sin_repartidor',
  'cancelado'
);

create type quien_paga as enum ('comercio', 'cliente');

create type vehiculo as enum ('moto', 'bicicleta', 'auto', 'a_pie');

create type estado_suscripcion as enum (
  'activa', 'por_vencer', 'vencida', 'sin_suscripcion'
);

-- El documento de la clienta pide que la arquitectura quede preparada para
-- sumar otros servicios (taxi, cadeteria) sin rehacer el producto. Por eso el
-- tipo existe desde el dia uno aunque hoy solo se use 'delivery'.
create type tipo_servicio as enum ('delivery', 'cadeteria', 'taxi');

create type metodo_pago as enum (
  'efectivo', 'mercado_pago', 'transferencia', 'otro'
);

create type estado_pago as enum (
  'pendiente', 'acreditado', 'rechazado', 'reembolsado'
);

create type respuesta_oferta as enum ('aceptada', 'rechazada', 'expirada');

-- ---------------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------------

create or replace function public.tocar_actualizado_en()
returns trigger
language plpgsql
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

comment on function public.tocar_actualizado_en is
  'Trigger generico para mantener actualizado_en. Se engancha en cada tabla.';

-- ---------------------------------------------------------------------------
-- Ciudades y zonas
-- ---------------------------------------------------------------------------

-- Arrancamos solo con Malargue, pero la ciudad es una fila y no una constante:
-- abrir una ciudad nueva tiene que ser un insert, no una migracion.
create table public.ciudades (
  id           uuid primary key default gen_random_uuid(),
  nombre       text not null,
  provincia    text not null,
  centro       extensions.geography(Point, 4326) not null,
  radio_km     numeric(6,2) not null default 15,
  activa       boolean not null default true,
  creado_en    timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint ciudades_nombre_provincia_unico unique (nombre, provincia)
);

create index ciudades_centro_idx on public.ciudades using gist (centro);

create trigger ciudades_tocar
  before update on public.ciudades
  for each row execute function public.tocar_actualizado_en();

-- Poligonos de cobertura. Todavia no se usan para cobrar distinto por zona,
-- pero permiten rechazar un destino fuera del area de reparto.
create table public.zonas (
  id         uuid primary key default gen_random_uuid(),
  ciudad_id  uuid not null references public.ciudades(id) on delete cascade,
  nombre     text not null,
  poligono   extensions.geography(Polygon, 4326) not null,
  activa     boolean not null default true,
  creado_en  timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index zonas_poligono_idx on public.zonas using gist (poligono);
create index zonas_ciudad_idx on public.zonas (ciudad_id);

create trigger zonas_tocar
  before update on public.zonas
  for each row execute function public.tocar_actualizado_en();

-- ---------------------------------------------------------------------------
-- Perfiles
-- ---------------------------------------------------------------------------

-- Espejo de auth.users con el rol y los datos de contacto. Es la tabla que
-- consultan las politicas de RLS para saber quien es quien.
create table public.perfiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  rol        rol_usuario not null,
  nombre     text not null default '',
  telefono   text,
  creado_en  timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index perfiles_rol_idx on public.perfiles (rol);

create trigger perfiles_tocar
  before update on public.perfiles
  for each row execute function public.tocar_actualizado_en();

comment on table public.perfiles is
  'Un perfil por usuario de auth. El rol decide que app abre y que puede ver.';
