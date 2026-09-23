-- 0032 - Pago con tarjeta dentro de la app (Mercado Pago)
--
-- El cliente paga con tarjeta en la app y la plata entra a la cuenta de MODO
-- YA. Recien cuando el pago queda aprobado el pedido pasa a `pagado` y le
-- suena al local: si la tarjeta rebota, el local no llego a cocinar nada.
--
-- Datos de la tarjeta: NUNCA pasan por la base. La app se los manda directo a
-- Mercado Pago, que devuelve un token de un solo uso; aca queda la referencia
-- que ellos guardan (customer y card) y lo justo para mostrar "Visa ••••4218".

-- ---------------------------------------------------------------------------
-- 1. El cliente como "customer" de Mercado Pago y sus tarjetas guardadas
-- ---------------------------------------------------------------------------

alter table public.clientes
  add column mp_customer_id text unique;

comment on column public.clientes.mp_customer_id is
  'Id del cliente en Mercado Pago. Lo crea la Edge Function pagar-pedido la primera vez que guarda una tarjeta.';

create table public.tarjetas_guardadas (
  id          uuid primary key default gen_random_uuid(),
  cliente_id  uuid not null references public.clientes(id) on delete cascade,

  -- Referencia en Mercado Pago. Con esto se cobra: el numero no esta aca.
  mp_card_id  text not null,

  marca       text not null,              -- visa, master, amex...
  ultimos4    text not null check (ultimos4 ~ '^[0-9]{4}$'),
  vence_mes   smallint not null check (vence_mes between 1 and 12),
  vence_anio  smallint not null check (vence_anio between 2020 and 2100),
  titular     text,
  predeterminada boolean not null default false,
  creado_en   timestamptz not null default now(),

  constraint tarjetas_guardadas_unica unique (cliente_id, mp_card_id)
);

create index tarjetas_guardadas_cliente_idx on public.tarjetas_guardadas (cliente_id);

alter table public.tarjetas_guardadas enable row level security;

-- Cada uno ve y borra las suyas. Las crea la Edge Function (service_role).
create policy tarjetas_guardadas_propias on public.tarjetas_guardadas
  for select to authenticated
  using (cliente_id = (select public.mi_cliente_id()));

create policy tarjetas_guardadas_borrar on public.tarjetas_guardadas
  for delete to authenticated
  using (cliente_id = (select public.mi_cliente_id()));

-- Una sola predeterminada por cliente.
create or replace function public.una_tarjeta_predeterminada()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.predeterminada then
    update public.tarjetas_guardadas
       set predeterminada = false
     where cliente_id = new.cliente_id and id <> new.id and predeterminada;
  end if;
  return new;
end;
$$;

create trigger tarjetas_guardadas_una_predeterminada
  after insert or update of predeterminada on public.tarjetas_guardadas
  for each row when (new.predeterminada) execute function public.una_tarjeta_predeterminada();

-- ---------------------------------------------------------------------------
-- 2. El pago guarda su rastro en Mercado Pago
-- ---------------------------------------------------------------------------

alter table public.pagos
  add column mp_payment_id text unique,
  add column cuotas smallint check (cuotas between 1 and 24),
  add column detalle text;

comment on column public.pagos.detalle is
  'Motivo cuando el pago no sale (tarjeta sin fondos, datos invalidos, etc.), para mostrarselo al cliente.';

create index pagos_mp_idx on public.pagos (mp_payment_id);

-- ---------------------------------------------------------------------------
-- 3. Crear el pedido pagando con tarjeta en la app
--
-- Con `mercado_pago` el pedido nace en `pendiente_pago`: NO le llega al local
-- hasta que el pago se aprueba (lo hace confirmar_pago_online). Con los otros
-- medios sigue naciendo en `pagado`, como en 0027.
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

  -- Con tarjeta en la app el pedido espera la aprobacion del pago; con los
  -- demas medios le llega al local en el momento (0027).
  estado_inicial := case when p_metodo = 'mercado_pago' then 'pendiente_pago' else 'pagado' end;

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
    p_nota, estado_inicial
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

  -- El cobro queda pendiente. Con efectivo, posnet o transferencia lo registra
  -- la administracion cuando entra la plata; con tarjeta en la app lo acredita
  -- confirmar_pago_online cuando Mercado Pago aprueba.
  insert into public.pagos (metodo, estado, monto)
  values (p_metodo, 'pendiente', ped.costo_envio + suma)
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
-- 4. Confirmar el pago online (la llama la Edge Function con service_role)
-- ---------------------------------------------------------------------------

create or replace function public.confirmar_pago_online(
  p_pedido     uuid,
  p_mp_payment text,
  p_estado     public.estado_pago,
  p_cuotas     smallint default 1,
  p_detalle    text default null
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
  pg  public.pagos;
begin
  select * into ped from public.pedidos where id = p_pedido for update;
  if ped.id is null then
    raise exception 'El pedido no existe' using errcode = 'MY004';
  end if;

  if ped.pago_id is null then
    insert into public.pagos (metodo, estado, monto, mp_payment_id, cuotas, detalle,
                              acreditado_en)
    values ('mercado_pago', p_estado, ped.total, p_mp_payment, p_cuotas, p_detalle,
            case when p_estado = 'acreditado' then now() end)
    returning * into pg;
    update public.pedidos set pago_id = pg.id where id = ped.id;
  else
    update public.pagos
       set estado = p_estado, mp_payment_id = coalesce(p_mp_payment, mp_payment_id),
           cuotas = coalesce(p_cuotas, cuotas), detalle = p_detalle,
           acreditado_en = case when p_estado = 'acreditado' then now() else acreditado_en end
     where id = ped.pago_id;
  end if;

  -- Aprobado: el pedido entra al local (le suena el timbre).
  if p_estado = 'acreditado' and ped.estado = 'pendiente_pago' then
    update public.pedidos
       set estado = 'pagado', pagado_en = now(), metodo_pago = 'mercado_pago'
     where id = ped.id
    returning * into ped;

    -- actor_id apunta a `perfiles`, no a `clientes`.
    insert into public.pedido_eventos (pedido_id, estado_nuevo, actor_id, actor_rol)
    values (ped.id, 'pagado', (select perfil_id from public.clientes where id = ped.cliente_id), 'cliente');
  end if;

  -- Rechazado: el pedido no queda colgado esperando para siempre.
  if p_estado = 'rechazado' and ped.estado = 'pendiente_pago' then
    update public.pedidos
       set estado = 'cancelado', cancelado_en = now(),
           motivo_cancelacion = coalesce(p_detalle, 'El pago no se pudo completar')
     where id = ped.id
    returning * into ped;
  end if;

  return ped;
end;
$$;

revoke execute on function public.confirmar_pago_online(uuid, text, public.estado_pago, smallint, text)
  from public, anon, authenticated;

-- Las tarjetas guardadas se ven en vivo (se agregan desde otra pantalla).
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'tarjetas_guardadas'
  ) then
    alter publication supabase_realtime add table public.tarjetas_guardadas;
  end if;
end;
$$;
