-- 0058 - En la app solo se paga con tarjeta
--
-- Efectivo y transferencia salen de la pantalla del cliente. Transferencia
-- ademas estaba rota: prometia un alias que no existe en ningun lado, el
-- pedido entraba a la cocina marcado como pagado y el rider no cobraba nada
-- (hallazgo 1 de docs/hallazgos-de-la-revision.md). Efectivo funcionaba, pero
-- se corta a pedido: toda la plata entra por la pasarela.
--
-- Esto NO toca los mandados, que se siguen pagando en efectivo al rider:
-- `crear_mandado()` arma el envio por su cuenta y no pasa por aca (0052).
-- Tampoco toca los pedidos viejos ni los cobros que la administracion
-- registra a mano.
--
-- Va en la base y no solo en la app porque una version ya instalada sigue
-- mostrando las tres opciones: sin esto, un celular sin actualizar podria
-- seguir metiendo pedidos en efectivo.

create or replace function public.crear_pedido(
  p_comercio_id  uuid,
  p_direccion_id uuid,
  p_items        jsonb,
  p_nota         text default null,
  p_metodo       public.metodo_pago default 'mercado_pago'
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

  -- Solo tarjeta en la app. Efectivo y transferencia quedaron afuera (0058):
  -- se validan aca y no solo en la pantalla, porque una version vieja ya
  -- instalada sigue ofreciendolos y mandaria 'efectivo' igual.
  if p_metodo <> 'mercado_pago' then
    raise exception 'Por ahora solo se puede pagar con tarjeta' using errcode = 'MY006';
  end if;

  -- Con tarjeta el pedido espera el pago: al local le llega recien cuando
  -- Mercado Pago aprueba, asi nadie cocina algo que no se cobro.
  estado_inicial := 'pendiente_pago';

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
