-- 0004 - Pagos, suscripciones, liquidaciones y reclamos
--
-- La pasarela de pago todavia no esta elegida, y el documento advierte que no
-- hay que asumir que una transferencia comun permita separar automaticamente la
-- ganancia del cadete de la comision. Por eso el modelo no habla de ninguna
-- pasarela en particular: registra el metodo, el estado y una referencia
-- externa opaca. Sumar Mercado Pago (o efectivo) es agregar un valor al enum,
-- no rehacer las tablas.

create table public.pagos (
  id       uuid primary key default gen_random_uuid(),
  envio_id uuid references public.envios(id) on delete set null,

  metodo metodo_pago not null,
  estado estado_pago not null default 'pendiente',
  monto  integer not null check (monto >= 0),

  -- Id del pago en la pasarela, cuando haya una.
  referencia_externa text,
  -- Payload crudo de la pasarela, para poder auditar y reconciliar.
  datos jsonb not null default '{}'::jsonb,

  creado_en    timestamptz not null default now(),
  acreditado_en timestamptz,
  actualizado_en timestamptz not null default now()
);

create index pagos_envio_idx on public.pagos (envio_id);
create index pagos_estado_idx on public.pagos (estado, creado_en desc);
create unique index pagos_referencia_externa_unica
  on public.pagos (referencia_externa)
  where referencia_externa is not null;

create trigger pagos_tocar
  before update on public.pagos
  for each row execute function public.tocar_actualizado_en();

-- ---------------------------------------------------------------------------
-- Suscripcion mensual del comercio

create table public.suscripciones (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  estado      estado_suscripcion not null default 'sin_suscripcion',
  periodo_desde date not null,
  periodo_hasta date not null,
  monto       integer not null check (monto >= 0),
  pago_id     uuid references public.pagos(id),
  creado_en   timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint suscripciones_periodo_coherente check (periodo_hasta > periodo_desde)
);

create index suscripciones_comercio_idx
  on public.suscripciones (comercio_id, periodo_hasta desc);

create trigger suscripciones_tocar
  before update on public.suscripciones
  for each row execute function public.tocar_actualizado_en();

-- Estado de suscripcion vigente de cada comercio, para no repetir la consulta.
create view public.comercios_con_suscripcion as
select
  c.*,
  coalesce(s.estado, 'sin_suscripcion'::estado_suscripcion) as estado_suscripcion,
  s.periodo_hasta as suscripcion_hasta
from public.comercios c
left join lateral (
  select estado, periodo_hasta
  from public.suscripciones
  where comercio_id = c.id
  order by periodo_hasta desc
  limit 1
) s on true;

-- ---------------------------------------------------------------------------
-- Liquidaciones al cadete
--
-- La frecuencia y el metodo siguen pendientes de definicion. El modelo es
-- agnostico: una liquidacion agrupa envios entregados en un periodo y se cierra
-- cuando se paga. Sirve igual para semanal, quincenal o a pedido.

create table public.liquidaciones (
  id            uuid primary key default gen_random_uuid(),
  repartidor_id uuid not null references public.repartidores(id) on delete cascade,
  periodo_desde date not null,
  periodo_hasta date not null,
  total         integer not null default 0 check (total >= 0),
  estado        estado_pago not null default 'pendiente',
  pagada_en     timestamptz,
  pago_id       uuid references public.pagos(id),
  observacion   text,
  creado_en     timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint liquidaciones_periodo_coherente check (periodo_hasta >= periodo_desde)
);

create index liquidaciones_repartidor_idx
  on public.liquidaciones (repartidor_id, periodo_hasta desc);

create trigger liquidaciones_tocar
  before update on public.liquidaciones
  for each row execute function public.tocar_actualizado_en();

create table public.liquidacion_items (
  id              uuid primary key default gen_random_uuid(),
  liquidacion_id  uuid not null references public.liquidaciones(id) on delete cascade,
  envio_id        uuid not null references public.envios(id),
  monto           integer not null check (monto >= 0),
  -- Un envio no se puede liquidar dos veces.
  constraint liquidacion_items_envio_unico unique (envio_id)
);

create index liquidacion_items_liquidacion_idx
  on public.liquidacion_items (liquidacion_id);

-- ---------------------------------------------------------------------------
-- Reclamos e incidencias

create table public.reclamos (
  id         uuid primary key default gen_random_uuid(),
  envio_id   uuid references public.envios(id) on delete set null,
  abierto_por uuid not null references public.perfiles(id),
  rol_origen rol_usuario not null,
  motivo     text not null,
  detalle    text,
  estado     text not null default 'abierto'
             check (estado in ('abierto', 'en_revision', 'resuelto', 'desestimado')),
  resolucion text,
  resuelto_por uuid references public.perfiles(id),
  resuelto_en  timestamptz,
  creado_en  timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index reclamos_estado_idx on public.reclamos (estado, creado_en desc);
create index reclamos_envio_idx on public.reclamos (envio_id);

create trigger reclamos_tocar
  before update on public.reclamos
  for each row execute function public.tocar_actualizado_en();
