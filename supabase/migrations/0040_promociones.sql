-- 0040 - Promociones del local: descuentos sobre el menu
--
-- El local baja el precio de todo su menu, de algunas secciones o de productos
-- sueltos, con o sin fecha de fin y, si quiere, solo ciertos dias ("martes de
-- pizza"). El descuento lo pone el local: es menos plata para el, no para
-- MODO YA, y como la liquidacion se arma con lo que realmente se vendio
-- (`pedidos.subtotal`), sale solo.
--
-- El precio con descuento lo calcula la base, igual que el envio: la app lo
-- muestra, pero `crear_pedido` lo vuelve a calcular antes de cobrar. Una app
-- vieja o modificada no puede inventarse un precio.
--
-- El descuento es sobre el precio del producto, no sobre los agregados: la
-- muzzarella con descuento sigue cobrando el extra de jamon completo.

create type public.alcance_promocion as enum (
  'todo',       -- el menu entero
  'secciones',  -- las secciones elegidas
  'productos'   -- productos sueltos
);

create table public.promociones (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,

  nombre      text not null,
  porcentaje  smallint not null check (porcentaje between 1 and 90),
  alcance     public.alcance_promocion not null default 'todo',

  -- Vacio = todos los dias. 0 = domingo, 6 = sabado (como extract(dow)).
  dias        smallint[] not null default '{}',

  desde       date not null default current_date,
  hasta       date,
  activa      boolean not null default true,

  creado_en   timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),

  constraint promociones_periodo check (hasta is null or hasta >= desde),
  constraint promociones_dias_validos check (dias <@ array[0,1,2,3,4,5,6]::smallint[])
);

create index promociones_comercio_idx on public.promociones (comercio_id, activa);

create trigger promociones_tocar
  before update on public.promociones
  for each row execute function public.tocar_actualizado_en();

create table public.promocion_secciones (
  promocion_id uuid not null references public.promociones(id) on delete cascade,
  seccion_id   uuid not null references public.secciones_menu(id) on delete cascade,
  primary key (promocion_id, seccion_id)
);

create table public.promocion_productos (
  promocion_id uuid not null references public.promociones(id) on delete cascade,
  producto_id  uuid not null references public.productos(id) on delete cascade,
  primary key (promocion_id, producto_id)
);

comment on table public.promociones is
  'Descuentos que arma el local sobre su propio menu. El costo lo absorbe el local.';

-- ---------------------------------------------------------------------------
-- RLS: el local maneja las suyas, cualquiera las lee (son la vidriera)
-- ---------------------------------------------------------------------------

alter table public.promociones enable row level security;
alter table public.promocion_secciones enable row level security;
alter table public.promocion_productos enable row level security;

create policy promociones_leer on public.promociones
  for select to authenticated using (true);

create policy promociones_insert on public.promociones
  for insert to authenticated
  with check (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy promociones_update on public.promociones
  for update to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()))
  with check (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy promociones_delete on public.promociones
  for delete to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

do $$
declare t text;
begin
  foreach t in array array['promocion_secciones', 'promocion_productos']
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (true)', t || '_leer', t);
    execute format(
      'create policy %I on public.%I for all to authenticated
         using (exists (select 1 from public.promociones pr
                         where pr.id = promocion_id
                           and (pr.comercio_id = (select public.mi_comercio_id())
                                or (select public.es_admin()))))
         with check (exists (select 1 from public.promociones pr
                              where pr.id = promocion_id
                                and (pr.comercio_id = (select public.mi_comercio_id())
                                     or (select public.es_admin()))))',
      t || '_escribir', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Cuanto vale hoy cada producto
-- ---------------------------------------------------------------------------

-- Redondeo al peso: no hay centavos en el producto.
create or replace function public.precio_con_promocion(
  p_precio     integer,
  p_porcentaje smallint
)
returns integer
language sql immutable
as $$
  select greatest(0, round(p_precio * (100 - p_porcentaje) / 100.0))::integer
$$;

-- Si hoy rige, para este local, alguna promocion.
create or replace function public.promocion_vigente(
  p_promocion uuid,
  p_momento   timestamptz default now()
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select pr.activa
     and (p_momento at time zone 'America/Argentina/Mendoza')::date >= pr.desde
     and (pr.hasta is null or (p_momento at time zone 'America/Argentina/Mendoza')::date <= pr.hasta)
     and (cardinality(pr.dias) = 0
          or extract(dow from p_momento at time zone 'America/Argentina/Mendoza')::smallint = any(pr.dias))
  from public.promociones pr
  where pr.id = p_promocion
$$;

-- La promocion que le toca a un producto. Si hay mas de una, gana la que mas
-- descuenta: el cliente nunca paga de mas por una regla nuestra.
create or replace function public.promocion_de_producto(
  p_producto uuid,
  p_momento  timestamptz default now()
)
returns public.promociones
language sql stable security definer set search_path = public
as $$
  select pr.*
    from public.promociones pr
    join public.productos p on p.comercio_id = pr.comercio_id
   where p.id = p_producto
     and public.promocion_vigente(pr.id, p_momento)
     and (
       pr.alcance = 'todo'
       or (pr.alcance = 'secciones' and exists (
             select 1 from public.promocion_secciones ps
              where ps.promocion_id = pr.id and ps.seccion_id = p.seccion_id))
       or (pr.alcance = 'productos' and exists (
             select 1 from public.promocion_productos pp
              where pp.promocion_id = pr.id and pp.producto_id = p.id))
     )
   order by pr.porcentaje desc, pr.creado_en
   limit 1
$$;

-- Lo que consulta la app cuando abre el menu de un local: solo los productos
-- que hoy tienen descuento.
create or replace function public.promociones_del_local(p_comercio uuid)
returns table (
  producto_id  uuid,
  precio_lista integer,
  precio       integer,
  porcentaje   smallint,
  promocion_id uuid,
  promocion    text
)
language sql stable security definer set search_path = public
as $$
  select p.id,
         p.precio,
         public.precio_con_promocion(p.precio, pr.porcentaje),
         pr.porcentaje,
         pr.id,
         pr.nombre
    from public.productos p
    cross join lateral public.promocion_de_producto(p.id) pr
   where p.comercio_id = p_comercio
     and pr.id is not null
$$;

-- El panel del local: cada promocion con su alcance contado y si hoy rige.
create or replace view public.v_promociones
with (security_invoker = true)
as
select
  pr.id, pr.comercio_id, pr.nombre, pr.porcentaje, pr.alcance,
  pr.dias, pr.desde, pr.hasta, pr.activa, pr.creado_en,
  (select count(*) from public.promocion_secciones ps where ps.promocion_id = pr.id) as secciones,
  (select count(*) from public.promocion_productos pp where pp.promocion_id = pr.id) as productos,
  public.promocion_vigente(pr.id) as vigente
from public.promociones pr;

revoke execute on function public.promocion_vigente(uuid, timestamptz) from public, anon;
revoke execute on function public.promocion_de_producto(uuid, timestamptz) from public, anon;
revoke execute on function public.promociones_del_local(uuid) from public, anon;
grant execute on function public.promocion_vigente(uuid, timestamptz) to authenticated;
grant execute on function public.promocion_de_producto(uuid, timestamptz) to authenticated;
grant execute on function public.promociones_del_local(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- El pedido guarda el precio de lista y con que promocion se descontó
-- ---------------------------------------------------------------------------

alter table public.pedido_items
  add column precio_lista integer,
  add column promocion_id uuid references public.promociones(id) on delete set null;

comment on column public.pedido_items.precio_lista is
  'Lo que costaba sin promocion. Nulo si no hubo descuento.';

-- ---------------------------------------------------------------------------
-- Crear el pedido con los precios de hoy
-- ---------------------------------------------------------------------------

create or replace function public.crear_pedido(
  p_comercio_id  uuid,
  p_direccion_id uuid,
  p_items        jsonb,
  p_nota         text default null,
  p_metodo       public.metodo_pago default 'efectivo'
)
returns public.pedidos
language plpgsql security definer set search_path = public, extensions
as $$
declare
  cli    public.clientes;
  com    public.comercios;
  dir    public.direcciones_cliente;
  cot    record;
  ped    public.pedidos;
  item   jsonb;
  prod   public.productos;
  it_id  uuid;
  oi     public.opcion_items;
  op     public.opciones_producto;
  extras integer;
  linea  public.pedido_items;
  suma   integer := 0;
  cant   smallint;
  elegidas uuid[];
  n      integer;
  pg     public.pagos;
  estado_inicial public.estado_pedido;
  camp   uuid;
  cubierto integer := 0;
  cobra_envio integer;
  promo  public.promociones;
  precio integer;
  lista  integer;
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
    raise exception 'El comercio esta cerrado en este momento' using errcode = 'MY005';
  end if;

  select * into dir from public.direcciones_cliente
   where id = p_direccion_id and cliente_id = cli.id;
  if dir.id is null then
    raise exception 'La direccion de entrega no existe' using errcode = 'MY004';
  end if;

  if p_metodo not in ('efectivo', 'tarjeta', 'transferencia', 'mercado_pago') then
    raise exception 'Medio de pago no disponible' using errcode = 'MY006';
  end if;

  estado_inicial := case when p_metodo = 'mercado_pago' then 'pendiente_pago' else 'pagado' end;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido no tiene productos' using errcode = 'MY006';
  end if;

  select * into cot from public.cotizar(com.ciudad_id, com.ubicacion, dir.ubicacion);

  -- MODO YA Plus: si el cliente esta al dia y el local adherido tiene fondo,
  -- el envio lo paga el local y el cliente no lo ve en su total.
  if public.tiene_plus(cli.id) then
    camp := public.campania_plus_activa(com.id);
    if camp is not null and public.fondo_disponible(camp) >= cot.total then
      cubierto := cot.total;
    else
      camp := null;
    end if;
  end if;
  cobra_envio := cot.total - cubierto;

  insert into public.pedidos (
    ciudad_id, cliente_id, comercio_id,
    entrega_calle, entrega_referencia, entrega_ubicacion,
    subtotal, costo_envio,
    envio_tarifario_id, envio_distancia_km, envio_km_adicionales,
    envio_ganancia_repartidor, envio_comision, envio_minutos_estimados,
    nota_cliente, estado, envio_cubierto, campania_id
  ) values (
    com.ciudad_id, cli.id, com.id,
    dir.calle, dir.referencia, dir.ubicacion,
    0, cobra_envio,
    cot.tarifario_id, cot.distancia_km, cot.km_adicionales,
    cot.ganancia_repartidor, cot.comision, cot.minutos_estimados,
    p_nota, estado_inicial, cubierto, camp
  ) returning * into ped;

  for item in select * from jsonb_array_elements(p_items)
  loop
    select * into prod from public.productos
     where id = (item->>'producto_id')::uuid
       and comercio_id = com.id
       and disponible;
    if prod.id is null then
      raise exception 'Hay un producto que ya no esta disponible' using errcode = 'MY004';
    end if;

    cant := coalesce((item->>'cantidad')::smallint, 1);
    if cant <= 0 or cant > 50 then
      raise exception 'Cantidad invalida para %', prod.nombre using errcode = 'MY006';
    end if;

    -- El precio sale de la base, con la promocion que rija en este momento.
    select * into promo from public.promocion_de_producto(prod.id);
    if promo.id is null then
      precio := prod.precio;
      lista  := null;
    else
      precio := public.precio_con_promocion(prod.precio, promo.porcentaje);
      lista  := prod.precio;
    end if;

    select coalesce(array_agg((value #>> '{}')::uuid), '{}')
      into elegidas
      from jsonb_array_elements(coalesce(item->'opciones', '[]'::jsonb));

    if cardinality(elegidas) <> (select count(distinct x) from unnest(elegidas) x) then
      raise exception 'Hay una opcion repetida en %', prod.nombre using errcode = 'MY006';
    end if;

    for op in select * from public.opciones_producto where producto_id = prod.id
    loop
      select count(*) into n
        from public.opcion_items i
       where i.opcion_id = op.id and i.id = any(elegidas);

      if op.obligatoria and n = 0 then
        raise exception 'Falta elegir % en %', lower(op.nombre), prod.nombre using errcode = 'MY006';
      end if;
      if op.tipo = 'unica' and n > 1 then
        raise exception 'En % se puede elegir una sola opcion de %', prod.nombre, lower(op.nombre)
          using errcode = 'MY006';
      end if;
      if op.max_selecciones is not null and n > op.max_selecciones then
        raise exception 'En % se pueden elegir hasta % de %', prod.nombre, op.max_selecciones, lower(op.nombre)
          using errcode = 'MY006';
      end if;
    end loop;

    insert into public.pedido_items (
      pedido_id, producto_id, nombre_producto, cantidad, precio_unitario, subtotal, nota,
      precio_lista, promocion_id
    ) values (
      ped.id, prod.id, prod.nombre, cant, precio, 0, item->>'nota',
      lista, promo.id
    ) returning * into linea;

    extras := 0;
    foreach it_id in array elegidas
    loop
      select * into oi from public.opcion_items where id = it_id and disponible;
      if oi.id is null then
        raise exception 'Hay una opcion que ya no esta disponible' using errcode = 'MY004';
      end if;

      select * into op from public.opciones_producto where id = oi.opcion_id;
      if op.producto_id <> prod.id then
        raise exception 'Una opcion no corresponde a %', prod.nombre using errcode = 'MY006';
      end if;

      insert into public.pedido_item_opciones (
        pedido_item_id, opcion_item_id, nombre_opcion, nombre_item, precio_extra
      ) values (linea.id, oi.id, op.nombre, oi.nombre, oi.precio_extra);

      extras := extras + oi.precio_extra;
    end loop;

    update public.pedido_items set subtotal = (precio + extras) * cant where id = linea.id;
    suma := suma + (precio + extras) * cant;
  end loop;

  -- El envio regalado se le carga al local recien ahora, con el pedido creado.
  if cubierto > 0 and camp is not null then
    insert into public.campania_gastos (campania_id, comercio_id, detalle, monto, pedido_id)
    values (camp, com.id, 'Envío gratis con MODO YA Plus', cubierto, ped.id);
  end if;

  insert into public.pagos (metodo, estado, monto)
  values (p_metodo, 'pendiente', cobra_envio + suma)
  returning * into pg;

  update public.pedidos
     set subtotal = suma, metodo_pago = p_metodo, pago_id = pg.id
   where id = ped.id
  returning * into ped;

  insert into public.pedido_eventos (pedido_id, estado_nuevo, actor_id, actor_rol)
  values (ped.id, estado_inicial, auth.uid(), 'cliente');

  return ped;
end;
$$;

revoke execute on function public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago) from public, anon;
grant execute on function public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago) to authenticated;

-- ---------------------------------------------------------------------------
-- La vidriera muestra el descuento
-- ---------------------------------------------------------------------------

create or replace view public.v_comercios
with (security_invoker = true)
as
select
  c.id, c.perfil_id, c.ciudad_id,
  c.nombre, c.rubro, c.rubro_id, r.nombre as rubro_nombre,
  c.telefono, c.calle, c.referencia,
  extensions.ST_Y(c.ubicacion::extensions.geometry) as lat,
  extensions.ST_X(c.ubicacion::extensions.geometry) as lng,
  c.logo_url, c.acepta_pedidos, c.demora_estimada_min,
  c.estado_aprobacion, c.creado_en,
  public.comercio_abierto(c.id) as abierto,
  c.portada_url,
  public.campania_plus_activa(c.id) is not null as plus,
  exists (
    select 1 from public.campanias ca
     where ca.comercio_id = c.id and ca.tipo = 'publicidad' and ca.estado = 'activa'
       and current_date >= ca.desde and (ca.hasta is null or current_date <= ca.hasta)
       and public.fondo_disponible(ca.id) > 0
  ) as destacado,
  (
    select max(pr.porcentaje) from public.promociones pr
     where pr.comercio_id = c.id and public.promocion_vigente(pr.id)
  ) as descuento
from public.comercios c
left join public.rubros r on r.id = c.rubro_id;

do $$
declare t text;
begin
  foreach t in array array['promociones', 'promocion_secciones', 'promocion_productos']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
