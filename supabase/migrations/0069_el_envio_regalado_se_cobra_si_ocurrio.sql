-- 0069 - El envío que regala el local se le cobra solo si el envío ocurrió
--
-- Dos errores de plata de MODO YA Plus, los dos verificados (hallazgos B1 y B2
-- de docs/hallazgos-de-la-auditoria-2.md). Van juntos porque son el mismo
-- número —cuánto del envío pone el local— mirado desde dos lados.
--
-- ===========================================================================
-- B1. Se le cobraba al local el envío de pedidos que nunca existieron
-- ===========================================================================
--
-- `crear_pedido` asienta el gasto del envío cubierto en `campania_gastos`
-- cuando el pedido todavía está en `pendiente_pago`, o sea antes de que entre
-- un peso. Y nada lo revertía después:
--
--   1. El cliente con Plus arma el pedido, cierra la app, y a los 30 minutos
--      lo cancela `cerrar_pagos_vencidos()`: el envío ya quedó cargado.
--   2. El cliente cancela un pedido pago: se le devuelve el 100%, pero el
--      gasto sigue siendo del local.
--   3. El local rechaza el pedido: paga el envío que nunca se hizo **más** la
--      penalidad del 50% del subtotal (0060).
--
-- Como el gasto no tenía tope, repetir la secuencia 1 vaciaba el presupuesto
-- de Plus de cualquier local adherido y le facturaba la diferencia.
--
-- **Qué se elige y por qué.** Había tres caminos: asentar el gasto más tarde
-- (al entregar), revertirlo cuando el pedido muere, o permitir filas negativas
-- como ya hace `cargos_comercio`. Se revierte, y se revierte marcando la fila
-- (`revertido_en`) en vez de borrarla:
--
--   * **Asentarlo al entregar no sirve**: el gasto en `campania_gastos` es lo
--     único que hace bajar `fondo_disponible`. Si el envío se asentara recién
--     al entregar, dos pedidos Plus simultáneos del mismo local verían los dos
--     el presupuesto entero y lo gastarían dos veces. El presupuesto es el
--     tope que el local puso: reservarlo al crear el pedido es justamente lo
--     que lo hace un tope. Lo que faltaba era soltar la reserva.
--   * **Las filas negativas no entran**: `campania_gastos.monto` tiene
--     `check (monto > 0)` y además hay un índice único por `pedido_id` (0038),
--     así que un pedido no puede tener dos filas. Habría que tocar las dos
--     cosas, y en la liquidación el local vería dos renglones ("Envío gratis
--     $2.500" y "-$2.500") de un pedido que no existió: ruido, no explicación.
--   * **Marcar y no borrar**: la fila queda para poder reconstruir qué pasó
--     (se reservó el envío, el pedido murió, se soltó), que es lo que uno
--     quiere tres semanas después cuando el local pregunta. Borrarla dejaría
--     el mismo saldo sin ningún rastro.
--
-- El disparador es un trigger sobre `pedidos` y no un `perform` dentro de
-- `cancelar_pedido`: los pedidos mueren por tres caminos distintos y uno de
-- ellos (`cerrar_pagos_vencidos`) es un `update` crudo que no pasa por ninguna
-- función de negocio. Un trigger los cubre a los tres y cubre también el
-- próximo camino que alguien agregue.
--
-- ===========================================================================
-- B2. El carrito prometía "Gratis con Plus" y la pantalla de pago cobraba todo
-- ===========================================================================
--
-- El mismo número calculado en dos lados con reglas distintas:
--
--   * `cotizar_para_cliente` (lo que ve el carrito): gratis si la campaña
--     tiene **algo** de fondo (`campania_plus_activa` solo exige
--     `fondo_disponible > 0`).
--   * `crear_pedido`: exige `fondo_disponible >= cot.total`. Si no alcanzaba,
--     descartaba la campaña y cobraba el envío entero **sin avisar nada**.
--
-- Con $500 de fondo y un envío de $2.500 el cliente veía "Envío MODO YA —
-- Gratis con Plus", confirmaba, y la pantalla de pago le mostraba $2.500 más.
-- No era una carrera: pasaba siempre.
--
-- **Qué se elige y por qué.** La regla queda una sola, en una sola función
-- (`campania_plus_para_envio`), y es la estricta: o la campaña paga el envío
-- entero o no paga nada. Media cobertura no existe en ninguna pantalla —el
-- carrito dice "Gratis con Plus", no "Gratis hasta $500"— y el local se
-- adhirió a Plus para regalar envíos, no para pagar una parte.
--
-- **Quién gana la carrera.** Queda el borde real: el fondo alcanza cuando se
-- cotiza y no cuando se confirma, porque otro pedido Plus del mismo local lo
-- consumió en el medio. Gana el cliente en el sentido que importa: **nunca se
-- le cambia el total en silencio**. `crear_pedido` recibe el envío que el
-- cliente aceptó (`p_envio_esperado`) y si no puede honrarlo corta con MY007
-- en vez de crear el pedido con otro precio; la pantalla vuelve a cotizar y le
-- muestra el número nuevo para que decida de nuevo. No se elige cubrir el
-- envío igual, por encima del presupuesto, porque eso es exactamente el agujero
-- sin tope de B1 entrando por la otra puerta.
--
-- Y para que la carrera sea rara en vez de frecuente, `crear_pedido` toma un
-- candado sobre la fila de la campaña antes de mirar el fondo: dos pedidos Plus
-- simultáneos del mismo local ya no ven los dos el fondo entero.
--
--   MY007  el costo del envío cambió entre la cotización y la confirmación
--
-- Lo que NO toca esta migración: nada de Mercado Pago ni de las Edge Functions
-- de pago. El reembolso al cliente de un pedido cancelado o rechazado sigue
-- siendo el de 0060/0061, intacto.

-- ---------------------------------------------------------------------------
-- 1. Un gasto de campaña se puede soltar
-- ---------------------------------------------------------------------------

alter table public.campania_gastos
  add column if not exists revertido_en timestamptz;

comment on column public.campania_gastos.revertido_en is
  'Cuando se solto el gasto porque el pedido murio (cancelado, rechazado o vencido). Una fila revertida no gasta fondo ni se le descuenta al local, pero queda para poder explicar que paso.';

-- `fondo_disponible` se consulta en cada cotización y en cada fila de la
-- vidriera, así que el filtro nuevo se apoya en un índice.
create index if not exists campania_gastos_campania_vivos_idx
  on public.campania_gastos (campania_id)
  where revertido_en is null;

-- ---------------------------------------------------------------------------
-- 2. El fondo de la campaña ignora lo revertido
-- ---------------------------------------------------------------------------
--
-- Este es el cambio que le devuelve el presupuesto al local: sin esto, marcar
-- la fila no alcanzaría para que vuelva a tener envíos gratis para regalar.

create or replace function public.fondo_disponible(p_campania uuid)
returns integer
language sql stable security definer set search_path = public
as $$
  select greatest(
    0,
    (select c.presupuesto from public.campanias c where c.id = p_campania)
    - coalesce((select sum(g.monto) from public.campania_gastos g
                 where g.campania_id = p_campania
                   and g.revertido_en is null), 0)
  );
$$;

-- Lo que el local ve en su pantalla de campañas.
create or replace view public.v_campanias
with (security_invoker = true)
as
select
  c.id, c.comercio_id, co.nombre as comercio_nombre,
  c.tipo, c.estado, c.presupuesto, c.presupuesto_diario,
  c.desde, c.hasta, c.creado_en,
  coalesce((select sum(g.monto) from public.campania_gastos g
             where g.campania_id = c.id and g.revertido_en is null), 0)::integer as gastado,
  public.fondo_disponible(c.id) as disponible
from public.campanias c
left join public.comercios co on co.id = c.comercio_id;

-- El retorno de la campaña: un envío que no se hizo no costó nada.
create or replace function public.rendimiento_campania(
  p_campania uuid,
  p_desde    date default null,
  p_hasta    date default null
)
returns table(ingresos integer, pedidos integer, costo integer, retorno numeric)
language sql stable security definer set search_path = public
as $$
  with c as (
    select * from public.campanias where id = p_campania
  ), rango as (
    select coalesce(p_desde, (select desde from c)) as d,
           coalesce(p_hasta, public.hoy()) as h
  ), ventas as (
    select coalesce(sum(p.subtotal), 0)::integer as ingresos, count(*)::integer as pedidos
      from public.pedidos p, c, rango
     where p.comercio_id = c.comercio_id
       and p.estado = 'entregado'
       and public.dia(p.entregado_en) between rango.d and rango.h
       -- Plus: solo los pedidos que efectivamente usaron el beneficio.
       and (c.tipo = 'publicidad'
            or exists (select 1 from public.campania_gastos g
                        where g.campania_id = c.id and g.pedido_id = p.id
                          and g.revertido_en is null))
  ), gastos as (
    select coalesce(sum(g.monto), 0)::integer as costo
      from public.campania_gastos g, rango
     where g.campania_id = p_campania
       and g.fecha between rango.d and rango.h
       and g.revertido_en is null
  )
  select v.ingresos, v.pedidos, g.costo,
         case when g.costo = 0 then 0 else round(v.ingresos::numeric / g.costo, 2) end
    from ventas v, gastos g;
$$;

-- ---------------------------------------------------------------------------
-- 3. La liquidación del local ignora lo revertido
-- ---------------------------------------------------------------------------
--
-- Mismo cuerpo que 0065, con el filtro agregado. Si esto no cambiara, el local
-- seguiría pagando el envío fantasma: la liquidación es el único consumidor de
-- `campania_gastos` que le toca el bolsillo.

create or replace function public.pendiente_de_liquidar_comercios(
  p_desde date,
  p_hasta date
)
returns table (
  comercio_id uuid,
  comercio    text,
  pedidos     integer,
  ventas      integer,
  cargos      integer,
  total       integer
)
language sql stable security definer set search_path = public
as $$
  with ventas as (
    select p.comercio_id, count(*)::integer as pedidos, coalesce(sum(p.subtotal), 0)::integer as ventas
      from public.pedidos p
     where p.estado = 'entregado'
       and p.liquidacion_id is null
       and public.dia(p.entregado_en) between p_desde and p_hasta
     group by p.comercio_id
  ), cargos as (
    select x.comercio_id, sum(x.monto)::integer as cargos from (
      select c.comercio_id, c.monto
        from public.cargos_comercio c
       where c.liquidacion_id is null and c.fecha between p_desde and p_hasta
      union all
      -- Publicidad y envios regalados con Plus.
      select g.comercio_id, g.monto
        from public.campania_gastos g
       where g.liquidacion_id is null and g.fecha between p_desde and p_hasta
         and g.revertido_en is null
    ) x group by x.comercio_id
  )
  select co.id, co.nombre,
         coalesce(v.pedidos, 0), coalesce(v.ventas, 0), coalesce(c.cargos, 0),
         coalesce(v.ventas, 0) - coalesce(c.cargos, 0)
    from public.comercios co
    left join ventas v on v.comercio_id = co.id
    left join cargos c on c.comercio_id = co.id
   where ((select public.es_admin()) or co.id = (select public.mi_comercio_id()))
     and (v.pedidos is not null or c.cargos is not null)
   order by co.nombre;
$$;

-- El renglón por renglón tiene que dar la misma suma que el resumen de arriba:
-- si el gasto revertido desapareciera de uno y no del otro, la resta no cerraría.
create or replace function public.cargos_a_liquidar_comercio(
  p_comercio uuid,
  p_desde    date,
  p_hasta    date
)
returns table (
  fecha    date,
  concepto text,
  detalle  text,
  monto    integer
)
language sql stable security definer set search_path = public
as $$
  select x.fecha, x.concepto, x.detalle, x.monto
    from (
      select c.fecha, c.concepto::text as concepto, c.detalle, c.monto, c.creado_en
        from public.cargos_comercio c
       where c.comercio_id = p_comercio
         and c.liquidacion_id is null
         and c.fecha between p_desde and p_hasta
      union all
      select g.fecha, 'campania'::text, g.detalle, g.monto, g.creado_en
        from public.campania_gastos g
       where g.comercio_id = p_comercio
         and g.liquidacion_id is null
         and g.fecha between p_desde and p_hasta
         and g.revertido_en is null
    ) x
   where ((select public.es_admin()) or p_comercio = (select public.mi_comercio_id()))
   order by x.fecha, x.creado_en;
$$;

-- Al cerrar, un gasto revertido no se sella con la liquidación: queda con
-- `liquidacion_id` nulo para siempre, que es como se lo deja afuera de todas
-- las cuentas sin tener que filtrarlo en cada lugar que las lee.
--
-- La suma de abajo (`liquidacion_id = liq.id`) a propósito NO filtra por
-- revertido: tiene que decir lo que esa liquidación efectivamente descontó.
create or replace function public.cerrar_liquidacion_comercio(
  p_comercio uuid,
  p_desde    date,
  p_hasta    date,
  p_observacion text default null
)
returns public.liquidaciones_comercio
language plpgsql security definer set search_path = public
as $$
declare
  liq public.liquidaciones_comercio;
  v   integer;
  c   integer;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion liquida' using errcode = '42501';
  end if;

  insert into public.liquidaciones_comercio (comercio_id, periodo_desde, periodo_hasta, observacion, creado_por)
  values (p_comercio, p_desde, p_hasta, p_observacion, auth.uid())
  returning * into liq;

  update public.pedidos set liquidacion_id = liq.id
   where comercio_id = p_comercio
     and estado = 'entregado'
     and liquidacion_id is null
     and public.dia(entregado_en) between p_desde and p_hasta;

  update public.cargos_comercio set liquidacion_id = liq.id
   where comercio_id = p_comercio and liquidacion_id is null
     and fecha between p_desde and p_hasta;

  update public.campania_gastos set liquidacion_id = liq.id
   where comercio_id = p_comercio and liquidacion_id is null
     and fecha between p_desde and p_hasta
     and revertido_en is null;

  select coalesce(sum(subtotal), 0) into v from public.pedidos where liquidacion_id = liq.id;
  select coalesce((select sum(monto) from public.cargos_comercio where liquidacion_id = liq.id), 0)
       + coalesce((select sum(monto) from public.campania_gastos where liquidacion_id = liq.id), 0)
    into c;

  update public.liquidaciones_comercio
     set ventas = v, cargos = c, total = v - c
   where id = liq.id
  returning * into liq;

  return liq;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Cuando el pedido muere, se suelta el envío
-- ---------------------------------------------------------------------------

create or replace function public.soltar_envio_cubierto()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  g public.campania_gastos;
begin
  -- `for update` porque el cierre de la liquidación le escribe `liquidacion_id`
  -- a esta misma fila: sin el candado, cancelar y liquidar al mismo tiempo
  -- podría sellar un gasto que se está soltando.
  select * into g from public.campania_gastos
   where pedido_id = new.id and revertido_en is null
   for update;

  if g.id is null then
    return null;
  end if;

  update public.campania_gastos set revertido_en = now() where id = g.id;

  -- Si el gasto ya entró en una liquidación cerrada, marcarlo no le devuelve la
  -- plata: esa liquidación ya se la descontó y no se reabre. Se le acredita en
  -- la próxima con un cargo negativo, que `cargos_comercio` admite a propósito
  -- (`check (monto <> 0)`, 0035). Es raro pero posible: el gasto nace con la
  -- fecha de hoy y la administración puede cerrar el período con el pedido
  -- todavía esperando el pago.
  if g.liquidacion_id is not null then
    insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, fecha, pedido_id)
    values (
      g.comercio_id, 'ajuste',
      format('Devolución del envío que regaló con Plus en el pedido %s (%s)', new.codigo, new.estado),
      -g.monto, public.hoy(), new.id
    );
  end if;

  return null;
end;
$$;

comment on function public.soltar_envio_cubierto() is
  'Suelta el gasto del envio cubierto con Plus cuando el pedido muere. Trigger: los pedidos mueren por tres caminos y uno es un update crudo (cerrar_pagos_vencidos).';

drop trigger if exists pedidos_soltar_envio_cubierto on public.pedidos;
create trigger pedidos_soltar_envio_cubierto
  after update of estado on public.pedidos
  for each row
  when (new.estado in ('cancelado', 'rechazado')
        and old.estado not in ('cancelado', 'rechazado'))
  execute function public.soltar_envio_cubierto();

-- ---------------------------------------------------------------------------
-- 5. Una sola regla para saber si el local paga el envío
-- ---------------------------------------------------------------------------
--
-- Lo que tenían distinto el carrito y `crear_pedido` ahora vive en un solo
-- lugar, y recibe el monto del envío: sin el monto no se puede decidir, y era
-- justamente lo que le faltaba a la cotización.

create or replace function public.campania_plus_para_envio(
  p_comercio uuid,
  p_envio    integer
)
returns uuid
language sql stable security definer set search_path = public
as $$
  select c.id
    from public.campanias c
   where c.comercio_id = p_comercio
     and c.tipo = 'plus'
     and c.estado = 'activa'
     and public.hoy() >= c.desde
     and (c.hasta is null or public.hoy() <= c.hasta)
     -- O cubre el envío entero o no cubre nada: media cobertura no existe en
     -- ninguna pantalla y el local no se adhirió para pagar una parte.
     and public.fondo_disponible(c.id) >= greatest(coalesce(p_envio, 0), 1)
   limit 1;
$$;

comment on function public.campania_plus_para_envio(uuid, integer) is
  'La campania Plus del local que puede pagar un envio de p_envio pesos. Es la UNICA regla del envio gratis: la usan cotizar_para_cliente y crear_pedido, que antes tenian una cada una (hallazgo B2).';

-- `campania_plus_activa` queda como está y sigue significando "el local está
-- adherido y la campaña tiene algo de fondo". Es lo que necesita la vidriera
-- (`v_comercios.plus`), que no conoce la dirección del cliente y por lo tanto
-- no sabe cuánto sale el envío. El que compromete un número es el carrito.

revoke execute on function public.campania_plus_para_envio(uuid, integer) from public, anon;
grant execute on function public.campania_plus_para_envio(uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. La cotización usa la regla buena
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
  -- Con el monto del envío, igual que `crear_pedido`: antes alcanzaba con que
  -- la campaña tuviera un peso y el carrito prometía un envío que el pedido
  -- despues cobraba entero (hallazgo B2).
  camp := public.campania_plus_para_envio(com.id, cot.total);

  return jsonb_build_object(
    'distancia_km', cot.distancia_km,
    -- Lo que paga el cliente: cero si el envio va gratis.
    'costo_envio', case when plus and camp is not null then 0 else cot.total end,
    'costo_envio_real', cot.total,
    'envio_gratis', plus and camp is not null,
    -- El local esta adherido aunque este cliente todavia no tenga Plus: sirve
    -- para ofrecerle la suscripcion ("con Plus este envio te salia gratis").
    -- Mira la misma regla que el envio gratis, porque es la misma promesa: si
    -- la campania no puede pagar ESTE envio, ofrecerle Plus seria mentirle.
    'local_adherido', camp is not null,
    'tiene_plus', plus,
    'minutos_estimados', cot.minutos_estimados + com.demora_estimada_min
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Crear el pedido: misma regla, candado, y el total que el cliente aceptó
-- ---------------------------------------------------------------------------
--
-- Cambia la firma (entra `p_envio_esperado`), así que hay que soltar la vieja
-- primero. Una app ya instalada sigue llamando con cinco parámetros y entra por
-- el default: se queda sin el guard del total, pero con la regla de la
-- cotización arreglada, que es la parte que hacía que el caso pasara siempre.

drop function if exists public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago);

create or replace function public.crear_pedido(
  p_comercio_id  uuid,
  p_direccion_id uuid,
  p_items        jsonb,
  p_nota         text default null,
  p_metodo       public.metodo_pago default 'mercado_pago',
  p_envio_esperado integer default null
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

  -- MODO YA Plus: si el cliente esta al dia y el local adherido puede pagar
  -- ESTE envio, el envio lo pone el local y el cliente no lo ve en su total.
  if public.tiene_plus(cli.id) then
    camp := public.campania_plus_para_envio(com.id, cot.total);
    if camp is not null then
      -- Candado sobre la campaña antes de decidir: dos pedidos Plus del mismo
      -- local que entraban al mismo tiempo veian los dos el fondo entero y lo
      -- gastaban dos veces. El segundo espera a que el primero termine y
      -- vuelve a mirar.
      perform 1 from public.campanias where id = camp for update;
      if public.fondo_disponible(camp) >= cot.total then
        cubierto := cot.total;
      else
        camp := null;
      end if;
    end if;
  end if;
  cobra_envio := cot.total - cubierto;

  -- El envio que el cliente acepto en el carrito. Si cambio en el medio —otro
  -- pedido Plus se comio el fondo, o cambio la tarifa— el pedido NO nace con
  -- otro precio: se corta y la pantalla vuelve a cotizar. Antes el pedido
  -- nacia con el envio cobrado y el cliente se enteraba en la pantalla de
  -- pago, con $2.500 mas y sin un solo mensaje (hallazgo B2).
  if p_envio_esperado is not null and p_envio_esperado <> cobra_envio then
    raise exception 'El costo del envío cambió mientras confirmabas el pedido. Revisá el total y volvé a confirmar.'
      using errcode = 'MY007';
  end if;

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

  -- El envio regalado se le reserva al local recien ahora, con el pedido
  -- creado. Es una reserva, no un cobro: si el pedido muere, el trigger
  -- `pedidos_soltar_envio_cubierto` la suelta y el fondo vuelve.
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

revoke execute on function
  public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago, integer)
  from public, anon;
grant execute on function
  public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago, integer)
  to authenticated;

comment on function public.crear_pedido(uuid, uuid, jsonb, text, public.metodo_pago, integer) is
  'Crea el pedido. p_envio_esperado es el envio que el cliente acepto en el carrito: si no coincide corta con MY007 en vez de crear el pedido con otro total (hallazgo B2).';
