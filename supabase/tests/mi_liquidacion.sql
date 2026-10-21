-- Cada uno ve su liquidación y solo la suya (migración 0065).
--
-- Lo que importa acá es el aislamiento: abrirle las funciones de liquidación al
-- rider y al local es exactamente el cambio que, mal hecho, deja que un rider
-- lea lo que cobra otro. Así que se arman dos riders y dos locales con plata de
-- verdad en el período y se prueba cruzado: A pidiendo lo de B tiene que volver
-- vacío, y A pidiendo lo suyo tiene que volver completo (cerrar de más también
-- es un bug: un rider que no ve su propia liquidación es el problema que esto
-- venía a resolver).
--
-- **Trampa:** `sql.ps1` corre como `postgres`, que es dueño de las tablas y
-- SALTEA el RLS. Todo lo que mide permisos va entre `set local role
-- authenticated` y `reset role`, o el test pasa igual con la política mal
-- escrita. El `insert into _r` va siempre con el rol reseteado, porque la tabla
-- temporal es de `postgres`.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_adm uuid := gen_random_uuid();
  u_ra  uuid := gen_random_uuid();   -- rider A
  u_rb  uuid := gen_random_uuid();   -- rider B
  u_la  uuid := gen_random_uuid();   -- local A
  u_lb  uuid := gen_random_uuid();   -- local B
  u_cli uuid := gen_random_uuid();
  ciudad uuid; tar uuid; cli uuid;
  ra uuid; rb uuid; la uuid; lb uuid;
  camp uuid;
  ped_a public.pedidos; ped_b public.pedidos;
  env_a public.envios;  env_b public.envios;
  liq_ra public.liquidaciones;        liq_rb public.liquidaciones;
  liq_la public.liquidaciones_comercio; liq_lb public.liquidaciones_comercio;
  desde date := public.hoy() - 7;
  hasta date := public.hoy();
  n integer; m integer; resumen integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  select id into tar from public.tarifarios where vigente_hasta is null limit 1;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','miliq-adm@test.local','x','{"rol":"admin"}',now(),now(),now()),
    (u_ra, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','miliq-ra@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_rb, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','miliq-rb@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_la, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','miliq-la@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_lb, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','miliq-lb@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','miliq-cli@test.local','x','{"provider":"email"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_la, ciudad, 'MiLiq Local A', 'Pizzeria', '2604111001', 'Roca 100',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into la;
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_lb, ciudad, 'MiLiq Local B', 'Pizzeria', '2604111002', 'Roca 200',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into lb;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_ra, ciudad, 'MiLiq Rider A', '2604111003', 'moto', 'aprobado') returning id into ra;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_rb, ciudad, 'MiLiq Rider B', '2604111004', 'moto', 'aprobado') returning id into rb;

  select id into cli from public.clientes where perfil_id = u_cli;

  -- ---- Un pedido entregado y un envío entregado por cada par ------------------
  insert into public.pedidos (
    ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
    subtotal, costo_envio, estado, metodo_pago,
    envio_tarifario_id, envio_ganancia_repartidor, envio_comision
  ) values (
    ciudad, cli, la, 'San Martin 500',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
    20000, 3550, 'pagado', 'tarjeta', tar, 3000, 550
  ) returning * into ped_a;

  insert into public.pedidos (
    ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
    subtotal, costo_envio, estado, metodo_pago,
    envio_tarifario_id, envio_ganancia_repartidor, envio_comision
  ) values (
    ciudad, cli, lb, 'San Martin 600',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
    31000, 3550, 'pagado', 'tarjeta', tar, 4000, 550
  ) returning * into ped_b;

  insert into public.envios (
    ciudad_id, comercio_id, pedido_id, repartidor_id,
    origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
    cliente_nombre, cliente_telefono, tarifario_id, distancia_km,
    ganancia_repartidor, comision, paga, estado, entregado_en
  ) values (
    ciudad, la, ped_a.id, ra, 'Roca 100',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography,
    'San Martin 500',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
    'Cliente MiLiq', '2604111005', tar, 1.2, 3000, 550, 'cliente', 'entregado', now()
  ) returning * into env_a;

  insert into public.envios (
    ciudad_id, comercio_id, pedido_id, repartidor_id,
    origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
    cliente_nombre, cliente_telefono, tarifario_id, distancia_km,
    ganancia_repartidor, comision, paga, estado, entregado_en
  ) values (
    ciudad, lb, ped_b.id, rb, 'Roca 200',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography,
    'San Martin 600',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
    'Cliente MiLiq', '2604111005', tar, 1.4, 4000, 550, 'cliente', 'entregado', now()
  ) returning * into env_b;

  update public.pedidos set estado = 'aceptado' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'en_preparacion' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'listo' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'en_camino' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'entregado', entregado_en = now() where id in (ped_a.id, ped_b.id);
  update public.pedidos set envio_id = env_a.id where id = ped_a.id;
  update public.pedidos set envio_id = env_b.id where id = ped_b.id;

  -- ---- Lo que se le descuenta a cada uno ---------------------------------------
  insert into public.cargos_repartidor (repartidor_id, concepto, detalle, monto, creado_por)
  values (ra, 'faltante', 'No entrego la vuelta del pedido MY-A', 1500, u_adm),
         (rb, 'abandono', 'Se bajo con el pedido en la puerta', 8000, u_adm);

  -- La penalidad por rechazar un pedido ya cobrado entra como `ajuste` (0060).
  -- Se inserta a mano y no por `rechazar_pedido` a proposito: lo que se prueba
  -- acá es que el local la VEA en su liquidación, no que se genere (eso ya lo
  -- cubre tests/reembolsos.sql).
  insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, creado_por)
  values (la, 'mensualidad', 'Plan Basico', 15000, u_adm),
         (la, 'ajuste', 'Penalidad por rechazar el pedido MY-A (50% de 20000)', 10000, u_adm),
         (lb, 'mensualidad', 'Plan Basico', 15000, u_adm);

  -- Un envío regalado con Plus: sale de la campaña del local y también se le
  -- descuenta, así que tiene que aparecer en la misma hoja.
  insert into public.campanias (comercio_id, tipo, presupuesto, creado_por)
  values (la, 'plus', 50000, u_adm) returning id into camp;
  insert into public.campania_gastos (campania_id, comercio_id, detalle, monto)
  values (camp, la, 'Envio regalado con Plus', 3550);

  -- ===========================================================================
  -- El rider y su liquidación en curso
  -- ===========================================================================

  perform set_config('request.jwt.claims', json_build_object('sub', u_ra)::text, true);

  set local role authenticated;
  select count(*) into n from public.detalle_de_liquidar_rider(rb, desde, hasta);
  select count(*) into m from public.detalle_de_liquidar_rider(ra, desde, hasta);
  reset role;
  insert into _r values ('01 NO el rider ve el detalle de otro rider',
    case when n = 0 then 'OK  0 filas' else format('VULNERABLE  vio %s envios ajenos', n) end);
  insert into _r values ('02 SI el rider ve su propio detalle',
    case when m = 1 then 'OK  su envio, renglon por renglon' else format('BLOQUEADO DE MAS  vio %s', m) end);

  set local role authenticated;
  select count(*) into n from public.pendiente_de_liquidar_riders(desde, hasta);
  select count(*) into m from public.pendiente_de_liquidar_riders(desde, hasta) where repartidor_id = ra;
  reset role;
  insert into _r values ('03 el resumen del rider trae solo su fila',
    case when n = 1 and m = 1 then 'OK  una sola fila, la suya'
         else format('MAL  %s filas en total, %s propias', n, m) end);

  set local role authenticated;
  select count(*) into n from public.cargos_a_liquidar_rider(rb, desde, hasta);
  select count(*) into m from public.cargos_a_liquidar_rider(ra, desde, hasta);
  reset role;
  insert into _r values ('04 NO el rider ve los cargos de otro',
    case when n = 0 then 'OK  0 filas' else format('VULNERABLE  vio %s cargos ajenos', n) end);
  insert into _r values ('05 SI el rider ve por que cobra menos',
    case when m = 1 then 'OK  el faltante aparece' else format('BLOQUEADO DE MAS  vio %s', m) end);

  perform set_config('request.jwt.claims', null, true);

  -- ===========================================================================
  -- El local y su liquidación en curso
  -- ===========================================================================

  perform set_config('request.jwt.claims', json_build_object('sub', u_la)::text, true);

  set local role authenticated;
  select count(*) into n from public.detalle_de_liquidar_comercio(lb, desde, hasta);
  select count(*) into m from public.detalle_de_liquidar_comercio(la, desde, hasta);
  reset role;
  insert into _r values ('06 NO el local ve los pedidos de otro local',
    case when n = 0 then 'OK  0 filas' else format('VULNERABLE  vio %s pedidos ajenos', n) end);
  insert into _r values ('07 SI el local ve sus pedidos del periodo',
    case when m = 1 then 'OK  que entro en el numero' else format('BLOQUEADO DE MAS  vio %s', m) end);

  set local role authenticated;
  select count(*) into n from public.pendiente_de_liquidar_comercios(desde, hasta);
  select count(*) into m from public.pendiente_de_liquidar_comercios(desde, hasta) where comercio_id = la;
  reset role;
  insert into _r values ('08 el resumen del local trae solo su fila',
    case when n = 1 and m = 1 then 'OK  una sola fila, la suya'
         else format('MAL  %s filas en total, %s propias', n, m) end);

  set local role authenticated;
  select count(*) into n from public.cargos_a_liquidar_comercio(lb, desde, hasta);
  select count(*) into m from public.cargos_a_liquidar_comercio(la, desde, hasta);
  reset role;
  insert into _r values ('09 NO el local ve los cargos de otro local',
    case when n = 0 then 'OK  0 filas' else format('VULNERABLE  vio %s cargos ajenos', n) end);
  insert into _r values ('10 SI el local ve sus tres descuentos',
    case when m = 3 then 'OK  mensualidad, penalidad y campania'
         else format('MAL  vio %s de 3', m) end);

  -- El chequeo que evita el reclamo: lo que suma la pantalla tiene que ser
  -- exactamente el `cargos` del resumen. Si la hoja mostrara solo
  -- `cargos_comercio` y el resumen sumara además `campania_gastos`, el local
  -- veria $25.000 de descuentos y un saldo calculado sobre $28.550.
  set local role authenticated;
  select coalesce(sum(monto), 0) into n from public.cargos_a_liquidar_comercio(la, desde, hasta);
  select cargos into resumen from public.pendiente_de_liquidar_comercios(desde, hasta) where comercio_id = la;
  reset role;
  insert into _r values ('11 los descuentos de la hoja dan el mismo numero que el resumen',
    case when n = resumen and n = 28550 then format('OK  $%s en los dos lados', n)
         else format('MAL  hoja=%s resumen=%s', n, resumen) end);

  perform set_config('request.jwt.claims', null, true);

  -- ===========================================================================
  -- La administración no perdió nada al abrirlas
  -- ===========================================================================

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);

  set local role authenticated;
  select count(*) into n from public.pendiente_de_liquidar_riders(desde, hasta)
   where repartidor_id in (ra, rb);
  select count(*) into m from public.pendiente_de_liquidar_comercios(desde, hasta)
   where comercio_id in (la, lb);
  reset role;
  insert into _r values ('12 la administracion sigue viendo a todos',
    case when n = 2 and m = 2 then 'OK  los dos riders y los dos locales'
         else format('MAL  riders=%s locales=%s', n, m) end);

  -- ---- Cerrar las cuatro -------------------------------------------------------
  liq_ra := public.cerrar_liquidacion_rider(ra, desde, hasta, 'Prueba');
  liq_rb := public.cerrar_liquidacion_rider(rb, desde, hasta, 'Prueba');
  liq_la := public.cerrar_liquidacion_comercio(la, desde, hasta, 'Prueba');
  liq_lb := public.cerrar_liquidacion_comercio(lb, desde, hasta, 'Prueba');
  perform set_config('request.jwt.claims', null, true);

  -- ===========================================================================
  -- El historial: la tabla por RLS y el detalle por función
  -- ===========================================================================

  perform set_config('request.jwt.claims', json_build_object('sub', u_ra)::text, true);

  set local role authenticated;
  select count(*) into n from public.liquidaciones where id = liq_rb.id;
  select count(*) into m from public.liquidaciones where id = liq_ra.id;
  reset role;
  insert into _r values ('13 NO el rider lee la liquidacion cerrada de otro',
    case when n = 0 then 'OK  0 filas' else 'VULNERABLE  la leyo' end);
  insert into _r values ('14 SI el rider lee su historial',
    case when m = 1 then 'OK  su liquidacion cerrada' else 'BLOQUEADO DE MAS' end);

  set local role authenticated;
  select count(*) into n from public.renglones_de_liquidacion_rider(liq_rb.id);
  select count(*) into m from public.renglones_de_liquidacion_rider(liq_ra.id);
  reset role;
  insert into _r values ('15 NO el rider ve el detalle de la liquidacion de otro',
    case when n = 0 then 'OK  0 filas' else format('VULNERABLE  vio %s renglones ajenos', n) end);
  insert into _r values ('16 SI el rider ve el detalle de la suya',
    case when m = 2 then 'OK  el envio y el faltante' else format('MAL  vio %s de 2', m) end);

  perform set_config('request.jwt.claims', null, true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_la)::text, true);

  set local role authenticated;
  select count(*) into n from public.liquidaciones_comercio where id = liq_lb.id;
  select count(*) into m from public.cargos_comercio where comercio_id = lb;
  reset role;
  insert into _r values ('17 NO el local lee la liquidacion cerrada de otro',
    case when n = 0 then 'OK  0 filas' else 'VULNERABLE  la leyo' end);
  insert into _r values ('18 NO el local lee los cargos de otro',
    case when m = 0 then 'OK  0 filas' else format('VULNERABLE  vio %s', m) end);

  set local role authenticated;
  select count(*) into n from public.renglones_de_liquidacion_comercio(liq_lb.id);
  select count(*) into m from public.renglones_de_liquidacion_comercio(liq_la.id);
  reset role;
  insert into _r values ('19 NO el local ve el detalle de la liquidacion de otro',
    case when n = 0 then 'OK  0 filas' else format('VULNERABLE  vio %s renglones ajenos', n) end);
  insert into _r values ('20 SI el local ve el detalle de la suya',
    case when m = 4 then 'OK  el pedido, la mensualidad, la penalidad y la campania'
         else format('MAL  vio %s de 4', m) end);

  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza ----------------------------------------------------------------
  update public.pedidos set liquidacion_id = null, envio_id = null where id in (ped_a.id, ped_b.id);
  delete from public.campania_gastos where comercio_id = la;
  delete from public.campanias where comercio_id = la;
  delete from public.cargos_repartidor where repartidor_id in (ra, rb);
  delete from public.cargos_comercio where comercio_id in (la, lb);
  delete from public.liquidacion_items where liquidacion_id in (liq_ra.id, liq_rb.id);
  delete from public.liquidaciones where id in (liq_ra.id, liq_rb.id);
  delete from public.liquidaciones_comercio where id in (liq_la.id, liq_lb.id);
  delete from public.envio_eventos where envio_id in (env_a.id, env_b.id);
  delete from public.envios where id in (env_a.id, env_b.id);
  delete from public.pedido_eventos where pedido_id in (ped_a.id, ped_b.id);
  delete from public.pedidos where id in (ped_a.id, ped_b.id);
  delete from public.clientes where id = cli;
  delete from public.repartidores where id in (ra, rb);
  delete from public.comercios where id in (la, lb);
  delete from auth.users where id in (u_adm, u_ra, u_rb, u_la, u_lb, u_cli);
end $$;

select paso, resultado from _r order by paso;
