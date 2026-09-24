-- 0037 - Envío gratis con MODO YA Plus
--
-- Si el cliente tiene Plus al dia y el local tiene una campania Plus activa
-- con fondo, el envio le sale gratis: el cliente paga solo los productos y el
-- envio lo absorbe el local (se le descuenta en la liquidacion, 0036).
--
-- El rider cobra su parte igual y MODO YA se queda con su comision: el envio
-- no es gratis para nadie mas que para el cliente.

-- El pedido recuerda si el envio se lo regalaron (para el detalle y para no
-- recalcularlo despues).
alter table public.pedidos
  add column envio_cubierto integer not null default 0 check (envio_cubierto >= 0),
  add column campania_id uuid references public.campanias(id) on delete set null;

comment on column public.pedidos.envio_cubierto is
  'Cuanto del envio pago el local con su campania Plus. El cliente no lo paga.';

-- ---------------------------------------------------------------------------
-- La cotizacion le dice a la app si el envio va gratis
-- ---------------------------------------------------------------------------

create or replace function public.cotizar_para_cliente(
  p_comercio  uuid,
  p_direccion uuid
)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  com public.comercios;
  dir public.direcciones_cliente;
  cot record;
  plus boolean;
  camp uuid;
begin
  select * into dir from public.direcciones_cliente
   where id = p_direccion and cliente_id = public.mi_cliente_id();
  if dir.id is null then
    raise exception 'La direccion no existe' using errcode = 'MY004';
  end if;

  select * into com from public.comercios where id = p_comercio and estado_aprobacion = 'aprobado';
  if com.id is null or com.ubicacion is null then
    raise exception 'El comercio no esta disponible' using errcode = 'MY004';
  end if;

  select * into cot from public.cotizar(com.ciudad_id, com.ubicacion, dir.ubicacion);

  plus := public.tiene_plus();
  camp := public.campania_plus_activa(com.id);

  return jsonb_build_object(
    'distancia_km', cot.distancia_km,
    -- Lo que paga el cliente: cero si el envio va gratis.
    'costo_envio', case when plus and camp is not null then 0 else cot.total end,
    'costo_envio_real', cot.total,
    'envio_gratis', plus and camp is not null,
    -- El local esta adherido aunque este cliente todavia no tenga Plus: sirve
    -- para ofrecerle la suscripcion ("con Plus este envio te salia gratis").
    'local_adherido', camp is not null,
    'tiene_plus', plus,
    'minutos_estimados', cot.minutos_estimados + com.demora_estimada_min
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Crear el pedido: si corresponde, el envio lo paga el local
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
      pedido_id, producto_id, nombre_producto, cantidad, precio_unitario, subtotal, nota
    ) values (
      ped.id, prod.id, prod.nombre, cant, prod.precio, 0, item->>'nota'
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

    update public.pedido_items set subtotal = (prod.precio + extras) * cant where id = linea.id;
    suma := suma + (prod.precio + extras) * cant;
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

-- El envio del pedido se cotiza igual que siempre: el rider cobra lo suyo
-- aunque el cliente no haya pagado envio. aceptar_pedido usa
-- envio_ganancia_repartidor, que no cambia.

-- La vista de pedidos muestra si el envio fue gratis.
create or replace view public.v_pedidos
with (security_invoker = true)
as
select
  p.id, p.codigo, p.ciudad_id, p.estado,
  p.cliente_id, p.cliente_nombre, p.cliente_telefono,
  p.comercio_id, c.nombre as comercio_nombre, c.logo_url as comercio_logo_url,
  p.entrega_calle, p.entrega_referencia,
  extensions.ST_Y(p.entrega_ubicacion::extensions.geometry) as entrega_lat,
  extensions.ST_X(p.entrega_ubicacion::extensions.geometry) as entrega_lng,
  p.subtotal, p.costo_envio, p.total, p.metodo_pago,
  p.envio_id, p.envio_minutos_estimados,
  p.nota_cliente, p.motivo_rechazo, p.motivo_cancelacion,
  p.creado_en, p.pagado_en, p.aceptado_en, p.listo_en, p.entregado_en, p.cancelado_en,
  pg.estado as pago_estado,
  p.envio_cubierto
from public.pedidos p
left join public.comercios c on c.id = p.comercio_id
left join public.pagos pg on pg.id = p.pago_id;

-- La vidriera marca los locales adheridos a Plus, para mostrar "Envío gratis".
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
  ) as destacado
from public.comercios c
left join public.rubros r on r.id = c.rubro_id;
