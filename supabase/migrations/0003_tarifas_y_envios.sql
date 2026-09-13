-- 0003 - Tarifario versionado, envios, auditoria y ofertas

-- ---------------------------------------------------------------------------
-- Tarifario
--
-- Versionado en vez de editable: un tarifario nunca se modifica, se cierra y se
-- crea uno nuevo. Asi un envio de hace tres meses sigue mostrando el precio con
-- el que realmente se cobro, y las liquidaciones viejas no cambian solas cuando
-- la administracion sube una tarifa.

create table public.tarifarios (
  id        uuid primary key default gen_random_uuid(),
  ciudad_id uuid not null references public.ciudades(id) on delete cascade,
  servicio  tipo_servicio not null default 'delivery',

  -- Dinero, en pesos enteros.
  ganancia_repartidor_base integer not null check (ganancia_repartidor_base >= 0),
  comision_modo_ya         integer not null check (comision_modo_ya >= 0),
  precio_km_adicional      integer not null default 0
                           check (precio_km_adicional >= 0),
  precio_suscripcion_mensual integer check (precio_suscripcion_mensual >= 0),

  -- Reglas de operacion.
  km_incluidos         numeric(5,2) not null default 2 check (km_incluidos > 0),
  radio_busqueda_km    numeric(5,2) not null default 3 check (radio_busqueda_km > 0),
  segundos_para_aceptar integer not null default 30
                        check (segundos_para_aceptar between 5 and 600),

  vigente_desde timestamptz not null default now(),
  vigente_hasta timestamptz,
  creado_por    uuid references public.perfiles(id),
  creado_en     timestamptz not null default now(),

  constraint tarifarios_vigencia_coherente
    check (vigente_hasta is null or vigente_hasta > vigente_desde)
);

-- Un solo tarifario abierto por ciudad y servicio.
create unique index tarifarios_vigente_unico
  on public.tarifarios (ciudad_id, servicio)
  where vigente_hasta is null;

comment on column public.tarifarios.precio_km_adicional is
  'Pendiente de definir con la clienta. Arranca en 0 para no inventar un cobro.';

-- ---------------------------------------------------------------------------
-- Envios

-- El codigo legible que ve el usuario: MY-8492.
create sequence public.envio_codigo_seq start with 8500;

create table public.envios (
  id        uuid primary key default gen_random_uuid(),
  codigo    text not null unique
            default 'MY-' || nextval('public.envio_codigo_seq'),
  ciudad_id uuid not null references public.ciudades(id),
  servicio  tipo_servicio not null default 'delivery',

  comercio_id   uuid not null references public.comercios(id),
  repartidor_id uuid references public.repartidores(id),

  -- Origen: se copia del comercio al crear el envio. Se guarda copiado a
  -- proposito: si el comercio se muda, los envios viejos tienen que seguir
  -- diciendo desde donde salieron.
  origen_calle      text not null,
  origen_referencia text,
  origen_ubicacion  extensions.geography(Point, 4326),

  destino_calle      text not null,
  destino_referencia text,
  destino_ubicacion  extensions.geography(Point, 4326),

  -- Datos del destinatario. Solo los ve el cadete asignado (ver RLS).
  cliente_nombre       text not null,
  cliente_telefono     text not null,
  cliente_indicaciones text,

  -- Cotizacion congelada al momento de crear el envio.
  tarifario_id        uuid not null references public.tarifarios(id),
  distancia_km        numeric(6,2) not null check (distancia_km >= 0),
  km_adicionales      numeric(6,2) not null default 0,
  ganancia_repartidor integer not null check (ganancia_repartidor >= 0),
  comision            integer not null check (comision >= 0),
  total               integer generated always as (ganancia_repartidor + comision) stored,
  minutos_estimados   integer,
  paga                quien_paga not null,

  estado estado_envio not null default 'borrador',

  -- Codigo de 4 digitos que el cliente le dicta al cadete para cerrar la
  -- entrega. Se genera al asignar, no antes.
  codigo_entrega text check (codigo_entrega ~ '^[0-9]{4}$'),

  creado_en    timestamptz not null default now(),
  confirmado_en timestamptz,
  asignado_en  timestamptz,
  en_local_en  timestamptz,
  retirado_en  timestamptz,
  entregado_en timestamptz,
  cancelado_en timestamptz,
  actualizado_en timestamptz not null default now(),

  motivo_cancelacion text,
  cancelado_por      uuid references public.perfiles(id),

  -- Un envio asignado no puede no tener cadete.
  constraint envios_asignado_tiene_repartidor check (
    estado in ('borrador','cotizado','buscando_repartidor','sin_repartidor','cancelado')
    or repartidor_id is not null
  )
);

create index envios_comercio_idx   on public.envios (comercio_id, creado_en desc);
create index envios_repartidor_idx on public.envios (repartidor_id, creado_en desc);
create index envios_ciudad_idx     on public.envios (ciudad_id, creado_en desc);
create index envios_estado_idx     on public.envios (estado);

-- Los tableros y el mapa consultan casi siempre "lo que esta en la calle".
create index envios_activos_idx
  on public.envios (ciudad_id, creado_en desc)
  where estado in ('buscando_repartidor','asignado','en_local','retirado','en_camino');

create trigger envios_tocar
  before update on public.envios
  for each row execute function public.tocar_actualizado_en();

-- ---------------------------------------------------------------------------
-- Auditoria
--
-- "Registro de eventos del servicio para auditoria y reclamos" y "registro de
-- quien accedio o modifico informacion sensible" (secciones 11 y 12 del
-- documento). Cada cambio de estado deja una fila, con quien lo hizo.

create table public.envio_eventos (
  id        bigint generated always as identity primary key,
  envio_id  uuid not null references public.envios(id) on delete cascade,
  estado_anterior estado_envio,
  estado_nuevo    estado_envio not null,
  actor_id  uuid references public.perfiles(id),
  actor_rol rol_usuario,
  detalle   jsonb not null default '{}'::jsonb,
  creado_en timestamptz not null default now()
);

create index envio_eventos_envio_idx on public.envio_eventos (envio_id, creado_en);

-- ---------------------------------------------------------------------------
-- Ofertas
--
-- El motor de asignacion ofrece el envio de a un cadete por vez, empezando por
-- el mas cercano. Cada oferta tiene su ventana; si vence o la rechaza, se
-- ofrece al siguiente. Guardar cada oferta permite medir el indicador que pide
-- el piloto: tiempo promedio hasta que un cadete acepta.

create table public.ofertas (
  id            uuid primary key default gen_random_uuid(),
  envio_id      uuid not null references public.envios(id) on delete cascade,
  repartidor_id uuid not null references public.repartidores(id) on delete cascade,

  distancia_al_retiro_km numeric(6,2) not null,
  ofrecida_en   timestamptz not null default now(),
  expira_en     timestamptz not null,
  respondida_en timestamptz,
  respuesta     respuesta_oferta,

  constraint ofertas_unica unique (envio_id, repartidor_id)
);

create index ofertas_repartidor_idx on public.ofertas (repartidor_id, ofrecida_en desc);

-- Un envio no puede tener dos ofertas abiertas al mismo tiempo: es lo que
-- garantiza que no lo acepten dos cadetes a la vez.
create unique index ofertas_abierta_por_envio
  on public.ofertas (envio_id)
  where respuesta is null;
