-- 0013 - Pedidos del marketplace
--
-- Un PEDIDO es del cliente al comercio y tiene productos. Un ENVIO es del
-- comercio al domicilio y tiene cadete. Son dos cosas distintas: cuando el
-- comercio acepta un pedido, se genera el envio que lo lleva.
--
-- Asi conviven los dos productos sin pisarse:
--   * Cadeteria pura  -> envio sin pedido_id (lo que ya usa la app del comercio)
--   * Marketplace     -> pedido -> envio con pedido_id

create sequence public.pedido_codigo_seq start with 1000;

create table public.pedidos (
  id        uuid primary key default gen_random_uuid(),
  codigo    text not null unique
            default 'P-' || nextval('public.pedido_codigo_seq'),
  ciudad_id uuid not null references public.ciudades(id),

  cliente_id  uuid not null references public.clientes(id),
  comercio_id uuid not null references public.comercios(id),

  estado estado_pedido not null default 'pendiente_pago',

  -- Direccion de entrega copiada, no referenciada: si el cliente edita o borra
  -- la direccion guardada, el pedido viejo tiene que seguir diciendo a donde
  -- fue. Mismo criterio que el origen en `envios`.
  entrega_calle      text not null,
  entrega_referencia text,
  entrega_ubicacion  extensions.geography(Point, 4326) not null,

  -- Importes en pesos enteros. Los calcula el servidor en crear_pedido().
  subtotal    integer not null check (subtotal >= 0),
  costo_envio integer not null default 0 check (costo_envio >= 0),
  total       integer generated always as (subtotal + costo_envio) stored,

  -- Cotizacion del envio congelada al momento de comprar. Se guarda en el
  -- pedido porque el cliente ya pago ese precio: cuando el comercio acepte y
  -- se cree el envio, tiene que salir exactamente esto y no una cotizacion
  -- nueva calculada media hora despues con otro tarifario.
  envio_tarifario_id      uuid references public.tarifarios(id),
  envio_distancia_km      numeric(6,2),
  envio_km_adicionales    numeric(6,2) not null default 0,
  envio_ganancia_repartidor integer,
  envio_comision          integer,
  envio_minutos_estimados integer,

  metodo_pago metodo_pago,
  pago_id     uuid references public.pagos(id),

  -- El envio que lo lleva. Se crea recien cuando el comercio acepta.
  envio_id uuid references public.envios(id),

  nota_cliente       text,
  motivo_rechazo     text,
  motivo_cancelacion text,
  cancelado_por      uuid references public.perfiles(id) on delete set null,

  creado_en       timestamptz not null default now(),
  pagado_en       timestamptz,
  aceptado_en     timestamptz,
  listo_en        timestamptz,
  entregado_en    timestamptz,
  cancelado_en    timestamptz,
  actualizado_en  timestamptz not null default now()
);

create index pedidos_cliente_idx  on public.pedidos (cliente_id, creado_en desc);
create index pedidos_comercio_idx on public.pedidos (comercio_id, creado_en desc);
create index pedidos_ciudad_idx   on public.pedidos (ciudad_id, creado_en desc);
create index pedidos_envio_idx    on public.pedidos (envio_id);
create index pedidos_pago_idx     on public.pedidos (pago_id);
create index pedidos_cancelado_por_idx on public.pedidos (cancelado_por);
create index pedidos_tarifario_idx on public.pedidos (envio_tarifario_id);

-- Lo que el comercio mira todo el dia: lo que tiene que preparar ahora.
create index pedidos_abiertos_idx
  on public.pedidos (comercio_id, creado_en desc)
  where estado in ('pagado','aceptado','en_preparacion','listo','en_camino');

create trigger pedidos_tocar
  before update on public.pedidos
  for each row execute function public.tocar_actualizado_en();

-- El envio sabe de que pedido salio (si salio de alguno).
alter table public.envios
  add column if not exists pedido_id uuid references public.pedidos(id);

create index if not exists envios_pedido_idx on public.envios (pedido_id);

-- ---------------------------------------------------------------------------
-- Renglones del pedido
--
-- El nombre y el precio se copian del catalogo al momento de comprar. Si el
-- comercio despues sube el precio de la muzzarella, los pedidos viejos no
-- cambian. Por eso producto_id permite null: el producto se puede borrar y el
-- renglon historico sigue siendo legible.
-- ---------------------------------------------------------------------------

create table public.pedido_items (
  id          uuid primary key default gen_random_uuid(),
  pedido_id   uuid not null references public.pedidos(id) on delete cascade,
  producto_id uuid references public.productos(id) on delete set null,

  nombre_producto text not null,
  cantidad        smallint not null check (cantidad > 0),
  precio_unitario integer not null check (precio_unitario >= 0),
  -- (precio unitario + extras de las opciones) x cantidad
  subtotal        integer not null check (subtotal >= 0),
  nota            text
);

create index pedido_items_idx on public.pedido_items (pedido_id);
create index pedido_items_producto_idx on public.pedido_items (producto_id);

create table public.pedido_item_opciones (
  id             uuid primary key default gen_random_uuid(),
  pedido_item_id uuid not null references public.pedido_items(id) on delete cascade,
  opcion_item_id uuid references public.opcion_items(id) on delete set null,
  nombre_opcion  text not null,
  nombre_item    text not null,
  precio_extra   integer not null default 0 check (precio_extra >= 0)
);

create index pedido_item_opciones_idx
  on public.pedido_item_opciones (pedido_item_id);
create index pedido_item_opciones_item_idx
  on public.pedido_item_opciones (opcion_item_id);

-- ---------------------------------------------------------------------------
-- Auditoria del pedido
-- ---------------------------------------------------------------------------

create table public.pedido_eventos (
  id        bigint generated always as identity primary key,
  pedido_id uuid not null references public.pedidos(id) on delete cascade,
  estado_anterior estado_pedido,
  estado_nuevo    estado_pedido not null,
  actor_id  uuid references public.perfiles(id) on delete set null,
  actor_rol rol_usuario,
  detalle   jsonb not null default '{}'::jsonb,
  creado_en timestamptz not null default now()
);

create index pedido_eventos_idx on public.pedido_eventos (pedido_id, creado_en);
create index pedido_eventos_actor_idx on public.pedido_eventos (actor_id);

-- ---------------------------------------------------------------------------
-- Maquina de estados del pedido
-- ---------------------------------------------------------------------------

create or replace function public.transicion_pedido_valida(
  p_desde estado_pedido,
  p_hacia estado_pedido
)
returns boolean
language sql immutable set search_path = public
as $$
  select case p_desde
    when 'carrito'        then p_hacia in ('pendiente_pago','cancelado')
    when 'pendiente_pago' then p_hacia in ('pagado','cancelado')
    -- Desde pagado el comercio decide: lo toma o lo rechaza (y se reembolsa).
    when 'pagado'         then p_hacia in ('aceptado','rechazado','cancelado')
    when 'aceptado'       then p_hacia in ('en_preparacion','cancelado')
    when 'en_preparacion' then p_hacia in ('listo','cancelado')
    when 'listo'          then p_hacia in ('en_camino','cancelado')
    when 'en_camino'      then p_hacia in ('entregado','cancelado')
    else false
  end
$$;

create or replace function public.registrar_cambio_pedido()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.estado is distinct from old.estado then
    if not public.transicion_pedido_valida(old.estado, new.estado) then
      raise exception 'Transicion de pedido invalida: % -> %', old.estado, new.estado
        using errcode = 'MY001';
    end if;

    new.pagado_en    := coalesce(new.pagado_en,
                          case when new.estado = 'pagado'    then now() end);
    new.aceptado_en  := coalesce(new.aceptado_en,
                          case when new.estado = 'aceptado'  then now() end);
    new.listo_en     := coalesce(new.listo_en,
                          case when new.estado = 'listo'     then now() end);
    new.entregado_en := coalesce(new.entregado_en,
                          case when new.estado = 'entregado' then now() end);
    new.cancelado_en := coalesce(new.cancelado_en,
                          case when new.estado in ('cancelado','rechazado') then now() end);

    insert into public.pedido_eventos (
      pedido_id, estado_anterior, estado_nuevo, actor_id, actor_rol
    ) values (
      new.id, old.estado, new.estado, auth.uid(), public.mi_rol()
    );
  end if;
  return new;
end;
$$;

create trigger pedidos_registrar_estado
  before update of estado on public.pedidos
  for each row execute function public.registrar_cambio_pedido();

-- ---------------------------------------------------------------------------
-- Identidad del cliente
-- ---------------------------------------------------------------------------

create or replace function public.mi_cliente_id()
returns uuid
language sql stable security definer set search_path = public
as $$ select id from public.clientes where perfil_id = auth.uid() $$;

-- ---------------------------------------------------------------------------
-- Crear pedido
--
-- Los precios los pone el servidor leyendo el catalogo. La app manda que
-- producto y cuantos, nunca cuanto sale. Mismo criterio que crear_envio().
--
-- p_items es un jsonb con esta forma:
--   [{"producto_id":"...", "cantidad":2, "nota":"sin cebolla",
--     "opciones":["<opcion_item_id>", "..."]}]
-- ---------------------------------------------------------------------------

create or replace function public.crear_pedido(
  p_comercio_id  uuid,
  p_direccion_id uuid,
  p_items        jsonb,
  p_nota         text default null
)
returns public.pedidos
language plpgsql security definer set search_path = public, extensions
as $$
declare
  cli       public.clientes;
  com       public.comercios;
  dir       public.direcciones_cliente;
  cot       record;
  ped       public.pedidos;
  item      jsonb;
  prod      public.productos;
  it_id     uuid;
  oi        public.opcion_items;
  op        public.opciones_producto;
  extras    integer;
  linea     public.pedido_items;
  suma      integer := 0;
  cant      smallint;
begin
  select * into cli from public.clientes where id = public.mi_cliente_id();
  if cli.id is null then
    raise exception 'Solo un cliente puede hacer pedidos' using errcode = '42501';
  end if;

  select * into com from public.comercios where id = p_comercio_id;
  if com.id is null then
    raise exception 'El comercio no existe' using errcode = 'MY004';
  end if;
  if not public.comercio_abierto(com.id) then
    raise exception 'El comercio esta cerrado en este momento'
      using errcode = 'MY005';
  end if;

  select * into dir from public.direcciones_cliente
   where id = p_direccion_id and cliente_id = cli.id;
  if dir.id is null then
    raise exception 'La direccion de entrega no existe' using errcode = 'MY004';
  end if;

  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido no tiene productos' using errcode = 'MY006';
  end if;

  -- Cotizacion del envio, congelada: es lo que el cliente va a pagar.
  select * into cot
    from public.cotizar(com.ciudad_id, com.ubicacion, dir.ubicacion);

  insert into public.pedidos (
    ciudad_id, cliente_id, comercio_id,
    entrega_calle, entrega_referencia, entrega_ubicacion,
    subtotal, costo_envio,
    envio_tarifario_id, envio_distancia_km, envio_km_adicionales,
    envio_ganancia_repartidor, envio_comision, envio_minutos_estimados,
    nota_cliente, estado
  ) values (
    com.ciudad_id, cli.id, com.id,
    dir.calle, dir.referencia, dir.ubicacion,
    0, cot.total,
    cot.tarifario_id, cot.distancia_km, cot.km_adicionales,
    cot.ganancia_repartidor, cot.comision, cot.minutos_estimados,
    p_nota, 'pendiente_pago'
  ) returning * into ped;

  -- Renglones
  for item in select * from jsonb_array_elements(p_items)
  loop
    select * into prod from public.productos
     where id = (item->>'producto_id')::uuid
       and comercio_id = com.id
       and disponible;
    if prod.id is null then
      raise exception 'Producto no disponible: %', item->>'producto_id'
        using errcode = 'MY004';
    end if;

    cant := coalesce((item->>'cantidad')::smallint, 1);
    if cant <= 0 then
      raise exception 'Cantidad invalida para %', prod.nombre using errcode = 'MY006';
    end if;

    insert into public.pedido_items (
      pedido_id, producto_id, nombre_producto, cantidad,
      precio_unitario, subtotal, nota
    ) values (
      ped.id, prod.id, prod.nombre, cant, prod.precio, 0, item->>'nota'
    ) returning * into linea;

    extras := 0;

    if item ? 'opciones' then
      for it_id in
        select (value #>> '{}')::uuid from jsonb_array_elements(item->'opciones')
      loop
        select * into oi from public.opcion_items where id = it_id and disponible;
        if oi.id is null then
          raise exception 'Opcion no disponible' using errcode = 'MY004';
        end if;

        select * into op from public.opciones_producto where id = oi.opcion_id;
        -- Una opcion tiene que pertenecer al producto que se esta pidiendo.
        if op.producto_id <> prod.id then
          raise exception 'La opcion no corresponde a %', prod.nombre
            using errcode = 'MY006';
        end if;

        insert into public.pedido_item_opciones (
          pedido_item_id, opcion_item_id, nombre_opcion, nombre_item, precio_extra
        ) values (linea.id, oi.id, op.nombre, oi.nombre, oi.precio_extra);

        extras := extras + oi.precio_extra;
      end loop;
    end if;

    update public.pedido_items
       set subtotal = (prod.precio + extras) * cant
     where id = linea.id;

    suma := suma + (prod.precio + extras) * cant;
  end loop;

  update public.pedidos set subtotal = suma where id = ped.id
  returning * into ped;

  insert into public.pedido_eventos (pedido_id, estado_nuevo, actor_id, actor_rol)
  values (ped.id, 'pendiente_pago', auth.uid(), 'cliente');

  return ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- Pago
--
-- Como todavia no esta elegida la forma de cobro, esta funcion es el unico
-- punto por donde un pedido pasa a pagado. Cuando se decida, la llama el
-- webhook de la pasarela (o la administracion, si el cobro es en efectivo).
-- Por eso queda restringida a admin y no la puede llamar el cliente.
-- ---------------------------------------------------------------------------

create or replace function public.marcar_pedido_pagado(
  p_pedido uuid,
  p_metodo metodo_pago,
  p_referencia_externa text default null
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
  pg  public.pagos;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion puede registrar un pago'
      using errcode = '42501';
  end if;

  select * into ped from public.pedidos where id = p_pedido for update;
  if ped.id is null then
    raise exception 'El pedido no existe' using errcode = 'MY004';
  end if;

  insert into public.pagos (metodo, estado, monto, referencia_externa, acreditado_en)
  values (p_metodo, 'acreditado', ped.total, p_referencia_externa, now())
  returning * into pg;

  update public.pedidos
     set estado = 'pagado', metodo_pago = p_metodo, pago_id = pg.id
   where id = p_pedido
  returning * into ped;

  return ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- El comercio acepta el pedido: se crea el envio y arranca la busqueda
-- ---------------------------------------------------------------------------

create or replace function public.aceptar_pedido(p_pedido uuid)
returns public.pedidos
language plpgsql security definer set search_path = public, extensions
as $$
declare
  ped public.pedidos;
  com public.comercios;
  cli public.clientes;
  env public.envios;
begin
  select * into ped from public.pedidos
   where id = p_pedido and comercio_id = public.mi_comercio_id() for update;
  if ped.id is null then
    raise exception 'El pedido no existe o no es de tu comercio'
      using errcode = 'MY004';
  end if;
  if ped.estado <> 'pagado' then
    raise exception 'Solo se puede aceptar un pedido pagado' using errcode = 'MY001';
  end if;

  select * into com from public.comercios where id = ped.comercio_id;
  select * into cli from public.clientes  where id = ped.cliente_id;

  -- El envio hereda la cotizacion congelada del pedido, no una nueva.
  insert into public.envios (
    ciudad_id, comercio_id, pedido_id,
    origen_calle, origen_referencia, origen_ubicacion,
    destino_calle, destino_referencia, destino_ubicacion,
    cliente_nombre, cliente_telefono, cliente_indicaciones,
    tarifario_id, distancia_km, km_adicionales,
    ganancia_repartidor, comision, minutos_estimados,
    paga, estado
  ) values (
    ped.ciudad_id, com.id, ped.id,
    com.calle, com.referencia, com.ubicacion,
    ped.entrega_calle, ped.entrega_referencia, ped.entrega_ubicacion,
    cli.nombre, coalesce(cli.telefono, ''), ped.nota_cliente,
    ped.envio_tarifario_id, ped.envio_distancia_km, ped.envio_km_adicionales,
    ped.envio_ganancia_repartidor, ped.envio_comision, ped.envio_minutos_estimados,
    -- En el marketplace el envio ya lo pago el cliente dentro del total.
    'cliente', 'cotizado'
  ) returning * into env;

  insert into public.envio_eventos (envio_id, estado_nuevo, actor_id, actor_rol)
  values (env.id, 'cotizado', auth.uid(), 'comercio');

  update public.pedidos
     set estado = 'aceptado', envio_id = env.id
   where id = ped.id
  returning * into ped;

  return ped;
end;
$$;

create or replace function public.rechazar_pedido(
  p_pedido uuid,
  p_motivo text
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare ped public.pedidos;
begin
  update public.pedidos
     set estado = 'rechazado', motivo_rechazo = p_motivo
   where id = p_pedido
     and comercio_id = public.mi_comercio_id()
     and estado = 'pagado'
  returning * into ped;

  if ped.id is null then
    raise exception 'El pedido no existe o ya no se puede rechazar'
      using errcode = 'MY004';
  end if;
  -- El reembolso lo hace la administracion: depende de la pasarela que se
  -- elija, que todavia no esta definida.
  return ped;
end;
$$;

-- El comercio mueve el pedido mientras lo prepara.
create or replace function public.avanzar_pedido(
  p_pedido uuid,
  p_nuevo  estado_pedido
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare ped public.pedidos;
begin
  if p_nuevo not in ('en_preparacion','listo') then
    raise exception 'Ese estado no lo maneja el comercio' using errcode = '42501';
  end if;

  update public.pedidos set estado = p_nuevo
   where id = p_pedido and comercio_id = public.mi_comercio_id()
  returning * into ped;

  if ped.id is null then
    raise exception 'El pedido no existe o no es de tu comercio'
      using errcode = 'MY004';
  end if;

  -- Cuando esta listo, recien ahi se sale a buscar cadete: no tiene sentido
  -- tener a alguien esperando en la puerta mientras se prepara.
  if p_nuevo = 'listo' and ped.envio_id is not null then
    update public.envios set estado = 'buscando_repartidor'
     where id = ped.envio_id and estado = 'cotizado';
    perform public.ofrecer_al_siguiente(ped.envio_id);
  end if;

  return ped;
end;
$$;

create or replace function public.cancelar_pedido(
  p_pedido uuid,
  p_motivo text
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare ped public.pedidos;
begin
  update public.pedidos
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_pedido
     and (cliente_id = public.mi_cliente_id()
          or comercio_id = public.mi_comercio_id()
          or public.es_admin())
  returning * into ped;

  if ped.id is null then
    raise exception 'El pedido no existe o no podes cancelarlo'
      using errcode = '42501';
  end if;

  if ped.envio_id is not null then
    perform public.cancelar_envio(ped.envio_id, 'Pedido cancelado');
  end if;

  return ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- El estado del envio arrastra al del pedido
--
-- Cuando el cadete marca "retirado", el pedido pasa a en_camino; cuando
-- confirma la entrega, el pedido queda entregado. Asi el cliente ve un solo
-- estado coherente sin que nadie tenga que sincronizarlo a mano.
-- ---------------------------------------------------------------------------

create or replace function public.sincronizar_pedido_con_envio()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.pedido_id is null then return new; end if;
  if new.estado is not distinct from old.estado then return new; end if;

  if new.estado = 'retirado' then
    update public.pedidos set estado = 'en_camino'
     where id = new.pedido_id and estado = 'listo';
  elsif new.estado = 'entregado' then
    update public.pedidos set estado = 'entregado'
     where id = new.pedido_id and estado = 'en_camino';
  end if;

  return new;
end;
$$;

create trigger envios_sincronizar_pedido
  after update of estado on public.envios
  for each row execute function public.sincronizar_pedido_con_envio();
