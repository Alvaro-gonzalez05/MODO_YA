-- 0012 - Catalogo de productos (grupo D de las pantallas)
--
-- Amplia el producto de cadeteria a marketplace: el cliente final navega
-- comercios, arma un carrito y paga. Decision de alcance tomada el 13/09/2026.
--
-- Modelo clave: un PEDIDO (cliente -> comercio, con productos) es una entidad
-- distinta del ENVIO (comercio -> domicilio, con cadete). Un pedido GENERA un
-- envio cuando el comercio lo acepta. Asi la cadeteria pura sigue funcionando
-- sin pedido asociado, que es lo que ya usa la app del comercio.

-- ---------------------------------------------------------------------------
-- El cliente final es un rol nuevo
-- ---------------------------------------------------------------------------

alter type rol_usuario add value if not exists 'cliente';

create type estado_pedido as enum (
  'carrito',          -- todavia lo esta armando el cliente
  'pendiente_pago',
  'pagado',
  'aceptado',         -- el comercio lo tomo
  'en_preparacion',
  'listo',            -- esperando cadete
  'en_camino',        -- espejo del envio asociado
  'entregado',
  'rechazado',        -- el comercio no lo tomo
  'cancelado'
);

-- Tipo de seleccion de una opcion de producto: "tamano" es unica,
-- "agregados" es multiple.
create type tipo_opcion as enum ('unica', 'multiple');

-- ---------------------------------------------------------------------------
-- Clientes
-- ---------------------------------------------------------------------------

create table public.clientes (
  id        uuid primary key default gen_random_uuid(),
  perfil_id uuid not null unique references public.perfiles(id) on delete cascade,
  ciudad_id uuid not null references public.ciudades(id),
  nombre    text not null,
  telefono  text,
  foto_url  text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index clientes_ciudad_idx on public.clientes (ciudad_id);

create trigger clientes_tocar
  before update on public.clientes
  for each row execute function public.tocar_actualizado_en();

-- Direcciones guardadas. El cliente marca un pin y le pone un alias ("casa",
-- "trabajo"); la referencia en texto sigue siendo tan importante como la calle.
create table public.direcciones_cliente (
  id         uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.clientes(id) on delete cascade,
  alias      text not null default 'Casa',
  calle      text not null,
  referencia text,
  ubicacion  extensions.geography(Point, 4326) not null,
  predeterminada boolean not null default false,
  creado_en  timestamptz not null default now()
);

create index direcciones_cliente_idx on public.direcciones_cliente (cliente_id);

-- Una sola direccion predeterminada por cliente.
create unique index direcciones_cliente_predeterminada
  on public.direcciones_cliente (cliente_id)
  where predeterminada;

-- ---------------------------------------------------------------------------
-- Horarios del comercio
--
-- El listado del cliente muestra abierto/cerrado, y un comercio cerrado no
-- deberia poder recibir pedidos.
-- ---------------------------------------------------------------------------

create table public.horarios_comercio (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  -- 0 = domingo, 6 = sabado (compatible con extract(dow)).
  dia         smallint not null check (dia between 0 and 6),
  abre        time not null,
  cierra      time not null,
  constraint horarios_rango_valido check (cierra > abre)
);

create index horarios_comercio_idx on public.horarios_comercio (comercio_id, dia);

-- Interruptor manual: el comercio puede cerrarse aunque este dentro de horario
-- (se le rompio el horno, se quedo sin stock).
alter table public.comercios
  add column if not exists acepta_pedidos boolean not null default true,
  add column if not exists demora_estimada_min integer not null default 25
      check (demora_estimada_min >= 0);

create or replace function public.comercio_abierto(p_comercio uuid)
returns boolean
language sql stable set search_path = public
as $$
  select c.acepta_pedidos
     and c.estado_aprobacion = 'aprobado'
     and exists (
       select 1 from public.horarios_comercio h
       where h.comercio_id = c.id
         and h.dia = extract(dow from now() at time zone 'America/Argentina/Mendoza')
         and (now() at time zone 'America/Argentina/Mendoza')::time between h.abre and h.cierra
     )
  from public.comercios c
  where c.id = p_comercio
$$;

-- ---------------------------------------------------------------------------
-- Catalogo
-- ---------------------------------------------------------------------------

-- Categorias del listado general ("Pizzeria", "Comidas rapidas", "Farmacia"),
-- las que se ven como chips en el home del cliente.
create table public.rubros (
  id     uuid primary key default gen_random_uuid(),
  nombre text not null unique,
  icono  text,
  orden  smallint not null default 0,
  activo boolean not null default true
);

alter table public.comercios
  add column if not exists rubro_id uuid references public.rubros(id);

-- Secciones del menu dentro de un comercio ("Pizzas", "Empanadas", "Bebidas").
create table public.secciones_menu (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  nombre      text not null,
  orden       smallint not null default 0,
  activa      boolean not null default true
);

create index secciones_menu_idx on public.secciones_menu (comercio_id, orden);

create table public.productos (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  seccion_id  uuid references public.secciones_menu(id) on delete set null,

  nombre      text not null,
  descripcion text,
  -- En pesos enteros, igual que el resto del sistema.
  precio      integer not null check (precio >= 0),
  foto_url    text,

  disponible  boolean not null default true,
  orden       smallint not null default 0,

  creado_en   timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index productos_comercio_idx on public.productos (comercio_id, orden);
create index productos_seccion_idx on public.productos (seccion_id);
create index productos_disponibles_idx
  on public.productos (comercio_id) where disponible;

create trigger productos_tocar
  before update on public.productos
  for each row execute function public.tocar_actualizado_en();

-- Personalizacion (pantalla D2): "Tamano" (unica, obligatoria),
-- "Agregados" (multiple, hasta 3).
create table public.opciones_producto (
  id          uuid primary key default gen_random_uuid(),
  producto_id uuid not null references public.productos(id) on delete cascade,
  nombre      text not null,
  tipo        tipo_opcion not null default 'unica',
  obligatoria boolean not null default false,
  min_selecciones smallint not null default 0 check (min_selecciones >= 0),
  max_selecciones smallint check (max_selecciones >= 1),
  orden       smallint not null default 0,
  constraint opciones_min_max_coherente
    check (max_selecciones is null or max_selecciones >= min_selecciones)
);

create index opciones_producto_idx on public.opciones_producto (producto_id, orden);

create table public.opcion_items (
  id          uuid primary key default gen_random_uuid(),
  opcion_id   uuid not null references public.opciones_producto(id) on delete cascade,
  nombre      text not null,
  -- Puede ser 0 (una variante que no cambia el precio) o negativo nunca.
  precio_extra integer not null default 0 check (precio_extra >= 0),
  disponible  boolean not null default true,
  orden       smallint not null default 0
);

create index opcion_items_idx on public.opcion_items (opcion_id, orden);

-- ---------------------------------------------------------------------------
-- Favoritos
-- ---------------------------------------------------------------------------

create table public.favoritos (
  cliente_id  uuid not null references public.clientes(id) on delete cascade,
  comercio_id uuid not null references public.comercios(id) on delete cascade,
  creado_en   timestamptz not null default now(),
  primary key (cliente_id, comercio_id)
);
