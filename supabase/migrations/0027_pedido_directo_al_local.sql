-- 0027 - El pedido llega directo al local
--
-- Antes: el cliente pedia, el pedido quedaba en `pendiente_pago` y recien
-- cuando la administracion lo marcaba pagado le aparecia al local. Eso frenaba
-- cada pedido esperando a una persona.
--
-- Ahora el cliente elige con que paga (efectivo, tarjeta o transferencia) y el
-- pedido nace en `pagado`, que la app muestra como "Nuevo": le llega al local
-- en el momento. El cobro se sigue en `pagos` (pendiente -> acreditado) y la
-- administracion lo registra cuando entra la plata, sin frenar nada.
--
-- De paso:
--   * Un local sin horarios cargados figura CERRADO (antes, abierto siempre).
--   * La busqueda de rider no se rinde: el envio se queda en
--     `buscando_repartidor` y cada 10 s se vuelve a ofrecer, tambien a los
--     riders que ya dijeron que no (pasado un minuto).

-- ---------------------------------------------------------------------------
-- 1. Crear pedido con medio de pago
-- ---------------------------------------------------------------------------

drop function if exists public.crear_pedido(uuid, uuid, jsonb, text);

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

  if p_metodo not in ('efectivo', 'tarjeta', 'transferencia') then
    raise exception 'Medio de pago no disponible' using errcode = 'MY006';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido no tiene productos' using errcode = 'MY006';
  end if;

  select * into cot from public.cotizar(com.ciudad_id, com.ubicacion, dir.ubicacion);

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
    p_nota, 'pagado'
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

    -- Opciones elegidas para este renglon.
    select coalesce(array_agg((value #>> '{}')::uuid), '{}')
      into elegidas
      from jsonb_array_elements(coalesce(item->'opciones', '[]'::jsonb));

    if cardinality(elegidas) <> (select count(distinct x) from unnest(elegidas) x) then
      raise exception 'Hay una opcion repetida en %', prod.nombre using errcode = 'MY006';
    end if;

    -- Reglas de cada grupo del producto.
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

  -- El cobro queda pendiente: lo registra la administracion cuando entra la
  -- plata (efectivo del rider, posnet o transferencia). No frena el pedido.
  insert into public.pagos (metodo, estado, monto)
  values (p_metodo, 'pendiente', ped.costo_envio + suma)
  returning * into pg;

  update public.pedidos
     set subtotal = suma, metodo_pago = p_metodo, pago_id = pg.id
   where id = ped.id
  returning * into ped;

  insert into public.pedido_eventos (pedido_id, estado_nuevo, actor_id, actor_rol)
  values (ped.id, 'pagado', auth.uid(), 'cliente');

  return ped;
end;
$$;

revoke execute on function public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago) from public, anon;
grant execute on function public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Registrar el cobro (administracion)
--
-- Mismo nombre y parametros que antes, para no romper la app: ahora acredita
-- el pago del pedido. Solo mueve el estado del pedido si era uno viejo que
-- todavia esperaba en `pendiente_pago`.
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
    raise exception 'Solo la administracion puede registrar un cobro'
      using errcode = '42501';
  end if;

  select * into ped from public.pedidos where id = p_pedido for update;
  if ped.id is null then
    raise exception 'El pedido no existe' using errcode = 'MY004';
  end if;

  if ped.pago_id is null then
    insert into public.pagos (metodo, estado, monto, referencia_externa, acreditado_en)
    values (p_metodo, 'acreditado', ped.total, p_referencia_externa, now())
    returning * into pg;
  else
    update public.pagos
       set estado = 'acreditado', metodo = p_metodo,
           referencia_externa = coalesce(p_referencia_externa, referencia_externa),
           acreditado_en = now()
     where id = ped.pago_id
    returning * into pg;
  end if;

  update public.pedidos
     set metodo_pago = p_metodo, pago_id = pg.id, pagado_en = now(),
         estado = case when estado = 'pendiente_pago' then 'pagado'::estado_pedido else estado end
   where id = p_pedido
  returning * into ped;

  return ped;
end;
$$;

-- Los pedidos que quedaron esperando pago con el circuito viejo pasan al
-- local, con el cobro pendiente. Solo los de las ultimas 12 horas: los mas
-- viejos ya no tiene sentido que le aparezcan a la cocina.
do $$
declare
  p  public.pedidos;
  pg public.pagos;
begin
  for p in
    select * from public.pedidos
     where estado = 'pendiente_pago' and creado_en > now() - interval '12 hours'
  loop
    insert into public.pagos (metodo, estado, monto)
    values (coalesce(p.metodo_pago, 'efectivo'), 'pendiente', p.total)
    returning * into pg;

    update public.pedidos
       set estado = 'pagado', metodo_pago = coalesce(metodo_pago, 'efectivo'), pago_id = pg.id
     where id = p.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Sin horarios = cerrado
-- ---------------------------------------------------------------------------

create or replace function public.comercio_abierto_en(
  p_comercio uuid,
  p_momento  timestamp   -- hora local de Mendoza
)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  c    public.comercios;
  hoy  smallint := extract(dow from p_momento);
  ayer smallint := (extract(dow from p_momento)::int + 6) % 7;
  hora time     := p_momento::time;
begin
  select * into c from public.comercios where id = p_comercio;
  if c.id is null or c.estado_aprobacion <> 'aprobado' or not c.acepta_pedidos then
    return false;
  end if;

  -- Sin horarios cargados el local no figura abierto: que el cliente no pueda
  -- pedirle a un local que quizas ni esta atendiendo.
  return exists (
    select 1 from public.horarios_comercio h
    where h.comercio_id = c.id
      and (
        (h.dia = hoy  and h.cierra > h.abre and hora >= h.abre and hora < h.cierra)
        or (h.dia = hoy  and h.cierra < h.abre and hora >= h.abre)
        or (h.dia = ayer and h.cierra < h.abre and hora <  h.cierra)
      )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Buscar rider hasta encontrar
-- ---------------------------------------------------------------------------

-- Antes cada envio se le podia ofrecer UNA sola vez a cada rider: con pocos
-- riders, despues de un "no" o de una oferta vencida no quedaba a quien
-- ofrecerle. Ahora lo unico prohibido es tener dos ofertas abiertas del mismo
-- envio al mismo rider.
alter table public.ofertas drop constraint if exists ofertas_unica;
create unique index if not exists ofertas_abierta_unica
  on public.ofertas (envio_id, repartidor_id) where respuesta is null;
create index if not exists ofertas_envio_idx on public.ofertas (envio_id, ofrecida_en desc);

-- Candidatos: conectados, libres y cerca. Se saltea a quien ya tiene una
-- oferta abierta (no puede ver dos a la vez) y a quien se le ofrecio ESTE
-- envio hace menos de un minuto; pasado ese tiempo se le vuelve a ofrecer.
create or replace function public.repartidores_cercanos(p_envio uuid)
returns table (repartidor_id uuid, distancia_km numeric)
language sql stable security definer set search_path = public, extensions
as $$
  select r.id,
         round((extensions.ST_Distance(r.ultima_ubicacion, e.origen_ubicacion)
                / 1000)::numeric, 2)
  from public.envios e
  join public.tarifarios t on t.id = e.tarifario_id
  join public.repartidores r
    on r.ciudad_id = e.ciudad_id
   and r.estado_aprobacion = 'aprobado'
   and r.conectado
   and not r.ocupado
   and r.ultima_ubicacion is not null
   and extensions.ST_DWithin(
         r.ultima_ubicacion, e.origen_ubicacion, t.radio_busqueda_km * 1000
       )
  where e.id = p_envio
    and not exists (
      select 1 from public.ofertas o
      where o.repartidor_id = r.id and o.respuesta is null and o.expira_en > now()
    )
    and not exists (
      select 1 from public.ofertas o
      where o.envio_id = e.id and o.repartidor_id = r.id
        and o.ofrecida_en > now() - interval '1 minute'
    )
  order by 2
$$;

-- Si no hay nadie disponible el envio SIGUE buscando (antes pasaba a
-- `sin_repartidor` y ahi quedaba). El reintento lo hace vencer_ofertas().
create or replace function public.ofrecer_al_siguiente(p_envio uuid)
returns public.ofertas
language plpgsql security definer set search_path = public
as $$
declare
  cand  record;
  segs  integer;
  nueva public.ofertas;
begin
  if exists (
    select 1 from public.ofertas
    where envio_id = p_envio and respuesta is null and expira_en > now()
  ) then
    return null;
  end if;

  -- Un envio que habia quedado sin rider vuelve a la busqueda.
  update public.envios set estado = 'buscando_repartidor'
   where id = p_envio and estado = 'sin_repartidor';

  if not exists (
    select 1 from public.envios where id = p_envio and estado = 'buscando_repartidor'
  ) then
    return null;
  end if;

  select t.segundos_para_aceptar into segs
  from public.envios e join public.tarifarios t on t.id = e.tarifario_id
  where e.id = p_envio;

  select * into cand from public.repartidores_cercanos(p_envio) limit 1;
  if cand.repartidor_id is null then
    return null;
  end if;

  insert into public.ofertas (
    envio_id, repartidor_id, distancia_al_retiro_km, expira_en
  ) values (
    p_envio, cand.repartidor_id, cand.distancia_km,
    now() + make_interval(secs => segs)
  ) returning * into nueva;

  return nueva;
end;
$$;

-- Corre cada 10 s (pg_cron, job "vencer-ofertas"): vence las ofertas sin
-- respuesta y le ofrece a alguien cada envio que este buscando sin oferta
-- abierta. Asi la busqueda sigue sola hasta que alguien acepte o se cancele.
create or replace function public.vencer_ofertas()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  o public.ofertas;
  e record;
  n integer := 0;
begin
  for o in
    select * from public.ofertas
     where respuesta is null and expira_en <= now()
  loop
    update public.ofertas set respuesta = 'expirada', respondida_en = now()
     where id = o.id;
    n := n + 1;
  end loop;

  for e in
    select id from public.envios
     where estado in ('buscando_repartidor', 'sin_repartidor')
     order by creado_en
  loop
    perform public.ofrecer_al_siguiente(e.id);
  end loop;

  return n;
end;
$$;

-- Los envios que habian quedado sin rider en las ultimas 12 horas vuelven a
-- buscar; los mas viejos se dejan como estan.
update public.envios set estado = 'buscando_repartidor'
 where estado = 'sin_repartidor' and creado_en > now() - interval '12 hours';
