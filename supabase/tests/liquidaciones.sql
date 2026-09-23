-- Liquidaciones: que le queda a un local y a un rider en un periodo.
--
-- Arma un caso completo (pedido entregado, publicidad y mensualidad del local,
-- envio con efectivo cobrado por el rider), revisa lo que muestra el panel y
-- despues lo cierra. Al final borra todo lo que creo.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_adm uuid := gen_random_uuid();
  u_com uuid := gen_random_uuid();
  u_rep uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  ciudad uuid;
  com uuid; rep uuid; cli uuid; dir uuid; prod uuid; tar uuid;
  ped public.pedidos;
  env public.envios;
  liq_com public.liquidaciones_comercio;
  liq_rep public.liquidaciones;
  fila record;
  desde date := current_date - 7;
  hasta date := current_date;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  select id into tar from public.tarifarios where vigente_hasta is null limit 1;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','liq-adm@test.local','x','{"rol":"admin"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','liq-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_rep,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','liq-rep@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','liq-cli@test.local','x','{"provider":"email"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Liq Local', 'Pizzeria', '2604000001', 'Roca 100',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_rep, ciudad, 'Liq Rider', '2604000002', 'moto', 'aprobado') returning id into rep;

  select id into cli from public.clientes where perfil_id = u_cli;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  insert into public.secciones_menu (comercio_id, nombre, orden) values (com, 'Pizzas', 1);
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, (select id from public.secciones_menu where comercio_id = com), 'Muzzarella', 10000, true)
  returning id into prod;

  -- ---- Un pedido entregado, pagado en efectivo --------------------------------
  insert into public.pedidos (
    ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
    subtotal, costo_envio, estado, metodo_pago,
    envio_tarifario_id, envio_ganancia_repartidor, envio_comision
  ) values (
    ciudad, cli, com, 'San Martin 500',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
    10000, 3550, 'pagado', 'efectivo', tar, 3000, 550
  ) returning * into ped;

  insert into public.envios (
    ciudad_id, comercio_id, pedido_id, repartidor_id,
    origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
    cliente_nombre, cliente_telefono, tarifario_id, distancia_km,
    ganancia_repartidor, comision, paga, estado, entregado_en
  ) values (
    ciudad, com, ped.id, rep, 'Roca 100',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography,
    'San Martin 500',
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
    'Cliente Liq', '2604000003', tar, 1.2, 3000, 550, 'cliente', 'entregado', now()
  ) returning * into env;

  update public.pedidos set estado = 'aceptado' where id = ped.id;
  update public.pedidos set estado = 'en_preparacion' where id = ped.id;
  update public.pedidos set estado = 'listo' where id = ped.id;
  update public.pedidos set estado = 'en_camino' where id = ped.id;
  update public.pedidos set estado = 'entregado', entregado_en = now(), envio_id = env.id where id = ped.id;

  insert into _r values ('1. el rider cobro el efectivo',
    case when env.cobrar_al_entregar = ped.total and env.cobro_metodo = 'efectivo'
         then format('OK  cobro $%s', env.cobrar_al_entregar)
         else format('MAL  cobrar=%s metodo=%s', env.cobrar_al_entregar, env.cobro_metodo) end);

  -- ---- Cargos del local: mensualidad y publicidad -----------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);

  insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, creado_por)
  values (com, 'mensualidad', 'Plan Basico', 15000, u_adm),
         (com, 'publicidad', 'Cartel del inicio, una semana', 8000, u_adm);

  -- ---- Lo que muestra el panel antes de cerrar --------------------------------
  select * into fila from public.pendiente_de_liquidar_comercios(desde, hasta) where comercio_id = com;
  insert into _r values ('2. pendiente del local',
    case when fila.ventas = 10000 and fila.cargos = 23000 and fila.total = -13000
         then 'OK  vendio $10.000, debe $23.000 -> saldo -$13.000'
         else format('MAL  ventas=%s cargos=%s total=%s', fila.ventas, fila.cargos, fila.total) end);

  select * into fila from public.pendiente_de_liquidar_riders(desde, hasta) where repartidor_id = rep;
  insert into _r values ('3. pendiente del rider',
    case when fila.ganancias = 3000 and fila.efectivo = 13550 and fila.total = -10550
         then 'OK  gano $3.000 y junto $13.550 -> tiene que rendir $10.550'
         else format('MAL  ganancias=%s efectivo=%s total=%s', fila.ganancias, fila.efectivo, fila.total) end);

  -- ---- Cerrar ------------------------------------------------------------------
  liq_com := public.cerrar_liquidacion_comercio(com, desde, hasta, 'Prueba');
  liq_rep := public.cerrar_liquidacion_rider(rep, desde, hasta, 'Prueba');

  insert into _r values ('4. liquidacion del local',
    case when liq_com.ventas = 10000 and liq_com.cargos = 23000 and liq_com.total = -13000
         then 'OK  quedo registrada'
         else format('MAL  %s / %s / %s', liq_com.ventas, liq_com.cargos, liq_com.total) end);

  insert into _r values ('5. liquidacion del rider',
    case when liq_rep.ganancias = 3000 and liq_rep.efectivo_cobrado = 13550 and liq_rep.total = -10550
         then 'OK  quedo registrada'
         else format('MAL  %s / %s / %s', liq_rep.ganancias, liq_rep.efectivo_cobrado, liq_rep.total) end);

  -- Lo ya liquidado no se vuelve a ofrecer.
  insert into _r values ('6. no se paga dos veces',
    case when not exists (select 1 from public.pendiente_de_liquidar_comercios(desde, hasta) where comercio_id = com)
          and not exists (select 1 from public.pendiente_de_liquidar_riders(desde, hasta) where repartidor_id = rep)
         then 'OK  el periodo quedo cerrado'
         else 'MAL  sigue apareciendo como pendiente' end);

  perform public.marcar_liquidacion_pagada(liq_com.id, true);
  insert into _r values ('7. marcar pagada',
    (select case when estado = 'acreditado' and pagada_en is not null then 'OK  pagada' else 'MAL' end
       from public.liquidaciones_comercio where id = liq_com.id));

  -- ---- Un local sin movimientos no aparece -------------------------------------
  insert into _r values ('8. sin movimientos no figura',
    case when not exists (
      select 1 from public.pendiente_de_liquidar_comercios(current_date + 30, current_date + 37))
         then 'OK  periodo vacio, lista vacia' else 'MAL' end);

  -- ---- Limpieza -----------------------------------------------------------------
  perform set_config('request.jwt.claims', null, true);
  delete from public.liquidacion_items where liquidacion_id = liq_rep.id;
  delete from public.liquidaciones where id = liq_rep.id;
  delete from public.cargos_comercio where comercio_id = com;
  update public.pedidos set liquidacion_id = null, envio_id = null where id = ped.id;
  delete from public.liquidaciones_comercio where id = liq_com.id;
  delete from public.envio_eventos where envio_id = env.id;
  delete from public.envios where id = env.id;
  delete from public.pedido_eventos where pedido_id = ped.id;
  delete from public.pedidos where id = ped.id;
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.repartidores where id = rep;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_adm, u_com, u_rep, u_cli);
end $$;

select paso, resultado from _r order by paso;
