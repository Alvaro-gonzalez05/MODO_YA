-- El envío que el local regala con MODO YA Plus: cuándo se le cobra y cuándo no.
--
-- Fija los hallazgos B1 y B2 de docs/hallazgos-de-la-auditoria-2.md, arreglados
-- en la migración 0069:
--
--   B2  el carrito y `crear_pedido` tienen que decir el mismo número
--   B1  el local paga el envío que regaló solo si el envío ocurrió
--
-- Las tres secuencias de B1 se prueban por los tres caminos reales por los que
-- muere un pedido: el vencimiento del pago (un `update` crudo del cron), la
-- cancelación del cliente y el rechazo del local.
--
-- Nota sobre el aislamiento: todo pasa dentro de un `do $$`, o sea una sola
-- transacción, y se borra ahí mismo. El cron de reembolsos (que corre cada
-- minuto) nunca ve estas filas.

create temporary table _r (paso text, resultado text);

do $$
declare
  pct_comision numeric; pct_cobro numeric;
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; dir uuid; prod uuid; seccion uuid;
  camp_chica uuid; camp uuid;
  liq public.liquidaciones_comercio;
  eb integer;              -- lo que sale el envío
  tope integer;            -- presupuesto de la campaña grande
  cot jsonb;
  ped_b2 public.pedidos;   -- B2: con fondo insuficiente
  ped_vivo public.pedidos; -- el que sí se entrega
  ped_venc public.pedidos;
  ped_canc public.pedidos;
  ped_rech public.pedidos;
  ped_liq  public.pedidos;
  items jsonb;
  fondo_antes integer;
  n integer;
  i integer;
  pagos_de_prueba uuid[];
begin

  -- La comisión por pedido y el costo del cobro (0075) tienen su propia prueba
  -- (comision_por_pedido.sql). Acá se apagan mientras dura esta, para que los
  -- números que mide sigan siendo los suyos, y se vuelven a poner al final.
  select comision_pedido_pct, costo_cobro_pct into pct_comision, pct_cobro
    from public.tarifarios where vigente_hasta is null and servicio = 'delivery' limit 1;
  update public.tarifarios set comision_pedido_pct = 0, costo_cobro_pct = 0
   where vigente_hasta is null and servicio = 'delivery';

  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','plus-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','plus-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','plus-adm@test.local','x','{"rol":"admin"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Plus Local', 'Pizzeria', '2604000077', 'Roca 777',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;

  insert into public.secciones_menu (comercio_id, nombre, orden) values (com, 'Pizzas', 1) returning id into seccion;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, seccion, 'Muzzarella', 10000, true) returning id into prod;

  select id into cli from public.clientes where perfil_id = u_cli;

  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio)
  values (cli, public.hoy() - 1, public.hoy() + 29, 2500);

  select total into eb from public.cotizar(
    ciudad,
    (select ubicacion from public.comercios where id = com),
    (select ubicacion from public.direcciones_cliente where id = dir));

  items := jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1));

  -- =========================================================================
  -- B2. El carrito y crear_pedido dicen el mismo número
  -- =========================================================================
  --
  -- Campaña con fondo de sobra para la regla vieja (> 0) y de menos para pagar
  -- este envío. Es el caso del informe: $500 de fondo, envío de $2.500.
  insert into public.campanias (comercio_id, tipo, presupuesto)
  values (com, 'plus', greatest(1, eb - 1)) returning id into camp_chica;

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  cot := public.cotizar_para_cliente(com, dir);

  insert into _r values ('B2 01 el carrito no promete lo que no se puede pagar',
    case when not (cot->>'envio_gratis')::boolean and (cot->>'costo_envio')::int = eb
         then format('OK  con $%s de fondo y un envio de $%s, el carrito cobra el envio', greatest(1, eb - 1), eb)
         else 'MAL  ' || cot::text end);

  -- Se confirma pasando el envío que mostró el carrito: si las dos funciones no
  -- coincidieran, esto cortaria con MY007 en vez de crear el pedido.
  ped_b2 := public.crear_pedido(com, dir, items, null, 'mercado_pago', (cot->>'costo_envio')::int);

  insert into _r values ('B2 02 el pedido nace con el total que el cliente acepto',
    case when ped_b2.costo_envio = eb and ped_b2.envio_cubierto = 0 and ped_b2.campania_id is null
          and not exists (select 1 from public.campania_gastos where pedido_id = ped_b2.id)
         then format('OK  cobra $%s de envio y no le carga nada al local', eb)
         else format('MAL  envio=%s cubierto=%s camp=%s', ped_b2.costo_envio, ped_b2.envio_cubierto, ped_b2.campania_id) end);

  -- El guard del total: lo que pasaría si el fondo se consumiera entre la
  -- cotización y el "Confirmar".
  select count(*) into n from public.pedidos where comercio_id = com;
  begin
    ped_canc := public.crear_pedido(com, dir, items, null, 'mercado_pago', 0);
    insert into _r values ('B2 03 si el envio cambio no se crea el pedido', 'MAL  lo creo con otro total');
  exception when sqlstate 'MY007' then
    insert into _r values ('B2 03 si el envio cambio no se crea el pedido',
      case when (select count(*) from public.pedidos where comercio_id = com) = n
           then 'OK  corta con MY007 y no deja el pedido a medio hacer'
           else 'MAL  corto pero dejo el pedido' end);
  end;

  -- La campaña chica sale de escena: si quedaran dos campañas Plus activas del
  -- mismo local, cual gana seria cuestion de suerte.
  delete from public.campanias where id = camp_chica;

  -- =========================================================================
  -- B1. El local paga el envío que regaló solo si el envío ocurrió
  -- =========================================================================

  tope := eb * 10;
  insert into public.campanias (comercio_id, tipo, presupuesto)
  values (com, 'plus', tope) returning id into camp;

  cot := public.cotizar_para_cliente(com, dir);
  ped_vivo := public.crear_pedido(com, dir, items, null, 'mercado_pago', (cot->>'costo_envio')::int);

  insert into _r values ('B1 01 con fondo el envio va gratis y se reserva',
    case when (cot->>'envio_gratis')::boolean and (cot->>'costo_envio')::int = 0
          and ped_vivo.envio_cubierto = eb and ped_vivo.costo_envio = 0
          and public.fondo_disponible(camp) = tope - eb
         then format('OK  el cliente paga $10.000 y se le reservan $%s al local', eb)
         else format('MAL  cot=%s cubierto=%s fondo=%s', cot::text, ped_vivo.envio_cubierto, public.fondo_disponible(camp)) end);

  -- ---- Secuencia 1: el pago vence y el cron cancela el pedido --------------
  ped_venc := public.crear_pedido(com, dir, items, null, 'mercado_pago', 0);
  perform set_config('request.jwt.claims', null, true);

  -- Se lo envejece para que entre en la ventana del cron. `cerrar_pagos_vencidos`
  -- es un `update` crudo que no pasa por ninguna funcion de negocio: es el caso
  -- que obliga a que el arreglo sea un trigger. Llamarla no toca nada de nadie
  -- que el cron no vaya a cerrar en los proximos 5 minutos de todos modos.
  update public.pedidos set creado_en = now() - interval '31 minutes' where id = ped_venc.id;
  perform public.cerrar_pagos_vencidos();

  insert into _r values ('B1 02 el pago vencido no se le cobra al local',
    case when (select estado from public.pedidos where id = ped_venc.id) = 'cancelado'
          and (select revertido_en from public.campania_gastos where pedido_id = ped_venc.id) is not null
          and public.fondo_disponible(camp) = tope - eb
         then format('OK  el gasto se solto y el fondo volvio a $%s', tope - eb)
         else format('MAL  estado=%s revertido=%s fondo=%s',
                     (select estado from public.pedidos where id = ped_venc.id),
                     (select revertido_en from public.campania_gastos where pedido_id = ped_venc.id),
                     public.fondo_disponible(camp)) end);

  -- ---- Secuencia 2: el cliente cancela un pedido ya cobrado ---------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped_canc := public.crear_pedido(com, dir, items, null, 'mercado_pago', 0);

  perform set_config('request.jwt.claims', null, true);
  update public.pagos set estado = 'acreditado', acreditado_en = now() where id = ped_canc.pago_id;
  update public.pedidos set estado = 'pagado' where id = ped_canc.id;

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  perform public.cancelar_pedido(ped_canc.id, 'Me arrepenti');

  insert into _r values ('B1 03 el pedido pago que se cancela no se le cobra al local',
    case when (select revertido_en from public.campania_gastos where pedido_id = ped_canc.id) is not null
          and public.fondo_disponible(camp) = tope - eb
         then 'OK  se le devuelve todo al cliente y el envio no queda del local'
         else format('MAL  revertido=%s fondo=%s',
                     (select revertido_en from public.campania_gastos where pedido_id = ped_canc.id),
                     public.fondo_disponible(camp)) end);

  -- ---- Secuencia 3: el local rechaza el pedido ----------------------------
  ped_rech := public.crear_pedido(com, dir, items, null, 'mercado_pago', 0);

  perform set_config('request.jwt.claims', null, true);
  update public.pagos set estado = 'acreditado', acreditado_en = now() where id = ped_rech.pago_id;
  update public.pedidos set estado = 'pagado' where id = ped_rech.id;

  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  perform public.rechazar_pedido(ped_rech.id, 'No tengo mozzarella');

  insert into _r values ('B1 04 el rechazo cobra la penalidad pero no el envio',
    case when (select revertido_en from public.campania_gastos where pedido_id = ped_rech.id) is not null
          and public.fondo_disponible(camp) = tope - eb
          and (select monto from public.cargos_comercio where pedido_id = ped_rech.id) = 5000
         then 'OK  paga $5.000 de penalidad y nada del envio que no se hizo'
         else format('MAL  revertido=%s fondo=%s penalidad=%s',
                     (select revertido_en from public.campania_gastos where pedido_id = ped_rech.id),
                     public.fondo_disponible(camp),
                     (select monto from public.cargos_comercio where pedido_id = ped_rech.id)) end);

  -- ---- Lo que vaciaba el presupuesto: repetir la secuencia 1 --------------
  fondo_antes := public.fondo_disponible(camp);
  for i in 1..5 loop
    perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
    ped_venc := public.crear_pedido(com, dir, items, null, 'mercado_pago', 0);
    perform set_config('request.jwt.claims', null, true);
    update public.pedidos set estado = 'cancelado', cancelado_en = now(),
           motivo_cancelacion = 'El pago no se completó a tiempo'
     where id = ped_venc.id;
  end loop;

  insert into _r values ('B1 05 repetirlo cinco veces no vacia el presupuesto',
    case when public.fondo_disponible(camp) = fondo_antes
         then format('OK  el fondo sigue en $%s', fondo_antes)
         else format('MAL  quedo en %s de %s', public.fondo_disponible(camp), fondo_antes) end);

  -- ---- El envío que SÍ ocurrió se le sigue cobrando -----------------------
  update public.pedidos set estado = 'pagado', pagado_en = now() where id = ped_vivo.id;
  update public.pedidos set estado = 'aceptado' where id = ped_vivo.id;
  update public.pedidos set estado = 'en_preparacion' where id = ped_vivo.id;
  update public.pedidos set estado = 'listo' where id = ped_vivo.id;
  update public.pedidos set estado = 'en_camino' where id = ped_vivo.id;
  update public.pedidos set estado = 'entregado', entregado_en = now() where id = ped_vivo.id;

  insert into _r values ('B1 06 el envio entregado si se le cobra',
    case when (select revertido_en from public.campania_gastos where pedido_id = ped_vivo.id) is null
          and public.fondo_disponible(camp) = tope - eb
         then format('OK  el gasto de $%s sigue en pie', eb)
         else 'MAL  se solto un envio que se hizo' end);

  -- ---- La liquidación cuenta solo lo que ocurrió --------------------------
  -- Un pedido más, para que haya un gasto vivo cuando se cierre el período.
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped_liq := public.crear_pedido(com, dir, items, null, 'mercado_pago', 0);

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  insert into _r values ('B1 07 la liquidacion no incluye los envios fantasma',
    (select case when cargos = eb + eb + 5000 and ventas = 10000
                 then format('OK  dos envios vivos ($%s) mas la penalidad, y ninguno de los 8 muertos', eb * 2)
                 else format('MAL  ventas=%s cargos=%s (esperado %s)', ventas, cargos, eb * 2 + 5000) end
       from public.pendiente_de_liquidar_comercios(public.hoy() - 1, public.hoy())
      where comercio_id = com));

  insert into _r values ('B1 08 el renglon por renglon da la misma suma',
    (select case when coalesce(sum(monto), 0) = eb + eb + 5000
                 then 'OK  los renglones suman lo mismo que el resumen'
                 else format('MAL  los renglones suman %s', coalesce(sum(monto), 0)) end
       from public.cargos_a_liquidar_comercio(com, public.hoy() - 1, public.hoy())));

  -- ---- Un gasto ya liquidado se devuelve con un cargo negativo -----------
  liq := public.cerrar_liquidacion_comercio(com, public.hoy() - 1, public.hoy(), 'prueba 0069');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('B1 09 el cierre sella lo mismo que mostraba el resumen',
    case when liq.cargos = eb + eb + 5000 and liq.ventas = 10000
         then 'OK  la liquidacion cerrada cuadra con lo que se mostro'
         else format('MAL  ventas=%s cargos=%s', liq.ventas, liq.cargos) end);

  insert into _r values ('B1 10 un gasto revertido nunca se sella',
    case when (select count(*) from public.campania_gastos
                where comercio_id = com and revertido_en is not null and liquidacion_id is not null) = 0
         then 'OK  los 8 envios muertos quedaron fuera de la liquidacion'
         else 'MAL  se sello un gasto revertido' end);

  update public.pedidos set estado = 'cancelado', cancelado_en = now(),
         motivo_cancelacion = 'El pago no se completó a tiempo'
   where id = ped_liq.id;

  insert into _r values ('B1 11 lo ya liquidado se devuelve con un cargo negativo',
    case when (select revertido_en from public.campania_gastos where pedido_id = ped_liq.id) is not null
          and (select monto from public.cargos_comercio
                where pedido_id = ped_liq.id and liquidacion_id is null) = -eb
         then format('OK  la liquidacion cerrada no se reabre: se le acredita $%s en la proxima', eb)
         else format('MAL  revertido=%s cargo=%s',
                     (select revertido_en from public.campania_gastos where pedido_id = ped_liq.id),
                     (select monto from public.cargos_comercio where pedido_id = ped_liq.id and liquidacion_id is null)) end);

  -- ---- Permisos: la regla nueva la puede preguntar la app ----------------
  -- sql.ps1 corre como `postgres`, que saltea el RLS y tiene todos los grants:
  -- sin cambiar de rol esto pasaria aunque el grant no existiera.
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  begin
    set local role authenticated;
    perform public.campania_plus_para_envio(com, eb);
    reset role;
    insert into _r values ('B1 12 la app puede preguntar la regla nueva',
      'OK  campania_plus_para_envio es llamable con el rol de la app');
  exception when others then
    reset role;
    insert into _r values ('B1 12 la app puede preguntar la regla nueva', 'MAL  ' || left(sqlerrm, 60));
  end;
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza -----------------------------------------------------------
  update public.pedidos set liquidacion_id = null where comercio_id = com;
  update public.campania_gastos set liquidacion_id = null where comercio_id = com;
  update public.cargos_comercio set liquidacion_id = null where comercio_id = com;
  delete from public.liquidaciones_comercio where comercio_id = com;
  delete from public.cargos_comercio where comercio_id = com;
  delete from public.campania_gastos where comercio_id = com;
  delete from public.campanias where comercio_id = com;
  delete from public.suscripciones_plus where cliente_id = cli;
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id in (select id from public.pedidos where comercio_id = com));
  delete from public.pedido_items where pedido_id in (select id from public.pedidos where comercio_id = com);
  delete from public.pedido_eventos where pedido_id in (select id from public.pedidos where comercio_id = com);
  select array_agg(pago_id) into pagos_de_prueba
    from public.pedidos where comercio_id = com and pago_id is not null;
  update public.pedidos set pago_id = null where comercio_id = com;
  delete from public.pedidos where comercio_id = com;
  delete from public.pagos where id = any(coalesce(pagos_de_prueba, '{}'::uuid[]));
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli, u_adm);
  update public.tarifarios set comision_pedido_pct = pct_comision, costo_cobro_pct = pct_cobro
   where vigente_hasta is null and servicio = 'delivery';
end $$;

select paso, resultado from _r order by paso;
