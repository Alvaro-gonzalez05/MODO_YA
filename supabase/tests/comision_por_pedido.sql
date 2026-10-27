-- La comisión por pedido y el costo del cobro con tarjeta (0075).
--
-- Lo que tiene que pasar:
--   * cada pedido congela los porcentajes del tarifario al crearse, y un
--     cambio de tarifa después no lo toca;
--   * la liquidación del local los descuenta, y la hoja, el resumen y el
--     cierre dan el mismo número;
--   * guardar el tarifario no pierde la penalidad ni las comisiones;
--   * el local no se puede bajar la comisión.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_adm uuid := gen_random_uuid();
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  ciudad uuid; cli uuid; com uuid;
  orig public.tarifarios;            -- el tarifario vigente, para dejarlo como estaba
  nuevo public.tarifarios;
  ped_a public.pedidos; ped_b public.pedidos; ped_c public.pedidos;
  liq public.liquidaciones_comercio;
  r record;
  desde date := public.hoy() - 7;
  hasta date := public.hoy();
  n integer; m integer;
  txt text;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  select * into orig from public.tarifarios
   where ciudad_id = ciudad and servicio = 'delivery' and vigente_hasta is null;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','comi-adm@test.local','x','{"rol":"admin"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','comi-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','comi-cli@test.local','x','{"provider":"email"}',now(),now(),now());
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Comisión', 'Pizzeria', '2604111009', 'Roca 100',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;
  select id into cli from public.clientes where perfil_id = u_cli;

  -- Los valores de arranque, fijos para la prueba.
  update public.tarifarios set comision_pedido_pct = 10, costo_cobro_pct = 8, penalidad_rechazo_pct = 30
   where id = orig.id;

  -- ---- Cada pedido congela su porcentaje -------------------------------------
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago,
                              envio_tarifario_id, envio_ganancia_repartidor, envio_comision)
  values (ciudad, cli, com, 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          20000, 3550, 'pagado', 'tarjeta', orig.id, 3000, 550)
  returning * into ped_a;

  insert into _r values ('01 el pedido guarda 10% y 8% de los productos',
    case when ped_a.comision_pct = 10 and ped_a.comision = 2000 and ped_a.costo_cobro_pct = 8 and ped_a.costo_cobro = 1600
         then 'OK  $2000 + $1600 sobre $20000' else format('MAL  %s / %s', ped_a.comision, ped_a.costo_cobro) end);

  -- La administración cambia la tarifa: lo que viene paga 15% y MODO YA absorbe el cobro.
  update public.tarifarios set comision_pedido_pct = 15, costo_cobro_pct = 0 where id = orig.id;

  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago,
                              envio_tarifario_id, envio_ganancia_repartidor, envio_comision)
  values (ciudad, cli, com, 'San Martin 600',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          10000, 3550, 'pagado', 'tarjeta', orig.id, 3000, 550)
  returning * into ped_b;

  insert into _r values ('02 el pedido nuevo sale con la tarifa nueva',
    case when ped_b.comision = 1500 and ped_b.costo_cobro = 0 then 'OK  15% y sin costo de cobro'
         else format('MAL  %s / %s', ped_b.comision, ped_b.costo_cobro) end);

  select * into ped_a from public.pedidos where id = ped_a.id;
  insert into _r values ('03 el pedido viejo no cambia con la tarifa',
    case when ped_a.comision = 2000 and ped_a.costo_cobro = 1600 then 'OK  sigue en 10% + 8%' else 'MAL' end);

  -- Si cambia el subtotal (crear_pedido lo suma después de insertar), el monto se rehace con su porcentaje.
  update public.pedidos set subtotal = 30000 where id = ped_a.id returning * into ped_a;
  insert into _r values ('04 si cambia el subtotal, el monto se rehace con su porcentaje',
    case when ped_a.comision = 3000 and ped_a.costo_cobro = 2400 then 'OK  10% y 8% de $30000' else 'MAL' end);
  update public.pedidos set subtotal = 20000 where id = ped_a.id returning * into ped_a;

  -- Uno rechazado: no se liquida, así que no paga comisión.
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago,
                              envio_tarifario_id, envio_ganancia_repartidor, envio_comision)
  values (ciudad, cli, com, 'San Martin 700',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          50000, 3550, 'pagado', 'tarjeta', orig.id, 3000, 550)
  returning * into ped_c;

  -- Paso a paso: los triggers de la máquina de estados no dejan saltar.
  update public.pedidos set estado = 'aceptado' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'en_preparacion' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'listo' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'en_camino' where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'entregado', entregado_en = now() where id in (ped_a.id, ped_b.id);
  update public.pedidos set estado = 'rechazado', motivo_rechazo = 'prueba' where id = ped_c.id;

  -- ---- La liquidación ----------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  set local role authenticated;
  select * into r from public.pendiente_de_liquidar_comercios(desde, hasta) where comercio_id = com;
  reset role;
  insert into _r values ('05 el resumen descuenta las comisiones',
    case when r.ventas = 30000 and r.cargos = 5100 and r.total = 24900
         then 'OK  vendió $30000, comisiones $5100, a pagarle $24900'
         else format('MAL  ventas %s cargos %s total %s', r.ventas, r.cargos, r.total) end);

  set local role authenticated;
  select count(*), coalesce(sum(monto), 0) into n, m from public.cargos_a_liquidar_comercio(com, desde, hasta);
  select string_agg(detalle, ' | ' order by monto desc) into txt
    from public.cargos_a_liquidar_comercio(com, desde, hasta) where concepto = 'comision';
  reset role;
  insert into _r values ('06 la hoja da el mismo número que el resumen',
    case when n = 3 and m = 5100 then 'OK  3 renglones, $5100' else format('MAL  %s renglones, $%s', n, m) end);
  insert into _r values ('07 cada porcentaje en su renglón, legible',
    case when txt = '10% de $20.000 en 1 pedido | 15% de $10.000 en 1 pedido' then 'OK  ' || txt else 'MAL  ' || coalesce(txt, '(nada)') end);

  set local role authenticated;
  liq := public.cerrar_liquidacion_comercio(com, desde, hasta, null);
  select coalesce(sum(monto), 0) into m from public.renglones_de_liquidacion_comercio(liq.id) where seccion = 'cargos';
  reset role;
  insert into _r values ('08 el cierre guarda lo mismo',
    case when liq.ventas = 30000 and liq.cargos = 5100 and liq.total = 24900 and m = 5100
         then 'OK  $24900 a pagarle, y los renglones cierran' else format('MAL  %s / %s / %s / %s', liq.ventas, liq.cargos, liq.total, m) end);

  -- ---- Guardar la tarifa no pierde nada ------------------------------------------
  update public.tarifarios set comision_pedido_pct = 10, costo_cobro_pct = 8 where id = orig.id;
  set local role authenticated;
  nuevo := public.admin_nuevo_tarifario(ciudad, orig.ganancia_repartidor_base, orig.comision_modo_ya,
    orig.precio_km_adicional, orig.km_incluidos, orig.radio_busqueda_km, orig.segundos_para_aceptar);
  reset role;
  insert into _r values ('09 guardar sin tocar los porcentajes los conserva',
    case when nuevo.comision_pedido_pct = 10 and nuevo.costo_cobro_pct = 8 and nuevo.penalidad_rechazo_pct = 30
         then 'OK  10%, 8% y la penalidad del 30%' else format('MAL  %s / %s / %s', nuevo.comision_pedido_pct, nuevo.costo_cobro_pct, nuevo.penalidad_rechazo_pct) end);
  delete from public.tarifarios where id = nuevo.id;
  update public.tarifarios set vigente_hasta = null where id = orig.id;

  set local role authenticated;
  nuevo := public.admin_nuevo_tarifario(ciudad, orig.ganancia_repartidor_base, orig.comision_modo_ya,
    orig.precio_km_adicional, orig.km_incluidos, orig.radio_busqueda_km, orig.segundos_para_aceptar,
    p_comision_pedido_pct => 12.5, p_costo_cobro_pct => 7);
  reset role;
  insert into _r values ('10 guardar con porcentajes nuevos los cambia',
    case when nuevo.comision_pedido_pct = 12.5 and nuevo.costo_cobro_pct = 7 then 'OK  12,5% y 7%' else 'MAL' end);
  delete from public.tarifarios where id = nuevo.id;
  update public.tarifarios set vigente_hasta = null where id = orig.id;

  begin
    set local role authenticated;
    perform public.admin_nuevo_tarifario(ciudad, orig.ganancia_repartidor_base, orig.comision_modo_ya,
      orig.precio_km_adicional, orig.km_incluidos, orig.radio_busqueda_km, orig.segundos_para_aceptar,
      p_comision_pedido_pct => 150);
    reset role;
    insert into _r values ('11 NO un porcentaje de más de 100', 'MAL  lo aceptó');
  exception when others then
    reset role;
    insert into _r values ('11 NO un porcentaje de más de 100',
      case when sqlstate = 'MY006' then 'OK  rechazado' else 'MAL  ' || sqlstate end);
  end;

  -- ---- El local no se la puede bajar -------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  set local role authenticated;
  update public.pedidos set comision = 0, costo_cobro = 0 where id = ped_b.id;
  get diagnostics n = row_count;
  begin
    perform public.admin_nuevo_tarifario(ciudad, 1, 1, 1, 1, 1, 1, p_comision_pedido_pct => 0);
    m := 1;
  exception when others then m := 0; end;
  reset role;
  insert into _r values ('12 NO el local se baja la comisión de un pedido',
    case when n = 0 then 'OK  el RLS no lo deja' else 'MAL' end);
  insert into _r values ('13 NO el local cambia la tarifa',
    case when m = 0 then 'OK  rechazado' else 'MAL' end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza ----------------------------------------------------------------
  update public.tarifarios
     set comision_pedido_pct = orig.comision_pedido_pct, costo_cobro_pct = orig.costo_cobro_pct,
         penalidad_rechazo_pct = orig.penalidad_rechazo_pct, vigente_hasta = null
   where id = orig.id;
  update public.pedidos set liquidacion_id = null where comercio_id = com;
  delete from public.liquidaciones_comercio where comercio_id = com;
  delete from public.cargos_comercio where comercio_id = com;
  delete from public.pedido_eventos where pedido_id in (ped_a.id, ped_b.id, ped_c.id);
  delete from public.pedidos where id in (ped_a.id, ped_b.id, ped_c.id);
  delete from public.clientes where id = cli;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_adm, u_com, u_cli);
end $$;

select paso, resultado from _r order by paso;
