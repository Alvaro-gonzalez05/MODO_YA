-- Campañas del local (publicidad y MODO YA Plus) y el envío gratis.
--
-- Arma un local con las dos campañas, un cliente con Plus y otro sin Plus, y
-- revisa quién paga el envío, qué se le carga al local y qué rendimiento ve.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();   -- con Plus
  u_cli2 uuid := gen_random_uuid();  -- sin Plus
  u_adm uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; cli2 uuid; dir uuid; dir2 uuid; prod uuid; seccion uuid;
  camp_plus uuid; camp_pub uuid;
  ped public.pedidos;
  ped2 public.pedidos;
  cot jsonb;
  rend record;
  envio_base integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','camp-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','camp-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_cli2,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','camp-cli2@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','camp-adm@test.local','x','{"rol":"admin"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Camp Local', 'Pizzeria', '2604000010', 'Roca 100',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;

  insert into public.secciones_menu (comercio_id, nombre, orden) values (com, 'Pizzas', 1) returning id into seccion;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, seccion, 'Muzzarella', 10000, true) returning id into prod;

  select id into cli from public.clientes where perfil_id = u_cli;
  select id into cli2 from public.clientes where perfil_id = u_cli2;

  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli2, 'Casa', 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir2;

  select total into envio_base from public.cotizar(
    ciudad,
    (select ubicacion from public.comercios where id = com),
    (select ubicacion from public.direcciones_cliente where id = dir));

  -- ---- Campañas del local ---------------------------------------------------
  insert into public.campanias (comercio_id, tipo, presupuesto)
  values (com, 'plus', 50000) returning id into camp_plus;

  insert into public.campanias (comercio_id, tipo, presupuesto, presupuesto_diario)
  values (com, 'publicidad', 60000, 9000) returning id into camp_pub;

  insert into _r values ('01 fondo disponible',
    case when public.fondo_disponible(camp_plus) = 50000 then 'OK  $50.000 para gastar'
         else 'MAL  ' || public.fondo_disponible(camp_plus)::text end);

  -- ---- El cliente con Plus --------------------------------------------------
  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio)
  values (cli, current_date - 1, current_date + 29, 2500);

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  cot := public.cotizar_para_cliente(com, dir);
  insert into _r values ('02 cotizacion con Plus',
    case when (cot->>'envio_gratis')::boolean and (cot->>'costo_envio')::int = 0
          and (cot->>'costo_envio_real')::int = envio_base
         then format('OK  el cliente ve $0 (el envio vale $%s)', envio_base)
         else 'MAL  ' || cot::text end);

  ped := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'efectivo');

  insert into _r values ('03 el cliente no paga envio',
    case when ped.costo_envio = 0 and ped.envio_cubierto = envio_base and ped.total = 10000
         then format('OK  paga $10.000 y el local pone $%s', envio_base)
         else format('MAL  envio=%s cubierto=%s total=%s', ped.costo_envio, ped.envio_cubierto, ped.total) end);

  insert into _r values ('04 el envio se le carga al local',
    case when (select monto from public.campania_gastos where pedido_id = ped.id) = envio_base
         then 'OK  quedo como gasto de la campania'
         else 'MAL  no se registro el gasto' end);

  insert into _r values ('05 el fondo baja',
    case when public.fondo_disponible(camp_plus) = 50000 - envio_base
         then format('OK  quedan $%s', 50000 - envio_base)
         else 'MAL  ' || public.fondo_disponible(camp_plus)::text end);

  -- ---- El cliente sin Plus paga el envío ------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli2)::text, true);
  cot := public.cotizar_para_cliente(com, dir2);
  ped2 := public.crear_pedido(com, dir2,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'efectivo');

  insert into _r values ('06 sin Plus paga el envio',
    case when not (cot->>'envio_gratis')::boolean and (cot->>'local_adherido')::boolean
          and ped2.costo_envio = envio_base and ped2.envio_cubierto = 0
         then 'OK  paga el envio y ve que el local esta adherido'
         else format('MAL  envio=%s cubierto=%s %s', ped2.costo_envio, ped2.envio_cubierto, cot::text) end);

  -- ---- Publicidad: el gasto del día -----------------------------------------
  perform set_config('request.jwt.claims', null, true);
  perform public.cobrar_dia_de_publicidad();
  insert into _r values ('07 publicidad del dia',
    case when (select sum(monto) from public.campania_gastos where campania_id = camp_pub) = 9000
         then 'OK  gasto $9.000 en el dia'
         else 'MAL  ' || coalesce((select sum(monto)::text from public.campania_gastos where campania_id = camp_pub), 'sin gasto') end);

  perform public.cobrar_dia_de_publicidad();
  insert into _r values ('08 no cobra dos veces el mismo dia',
    case when (select sum(monto) from public.campania_gastos where campania_id = camp_pub) = 9000
         then 'OK  sigue en $9.000' else 'MAL  cobro de mas' end);

  -- ---- Rendimiento -----------------------------------------------------------
  update public.pedidos set estado = 'aceptado' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'en_preparacion' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'listo' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'en_camino' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'entregado', entregado_en = now() where id in (ped.id, ped2.id);

  select * into rend from public.rendimiento_campania(camp_pub);
  insert into _r values ('09 rendimiento de la publicidad',
    case when rend.pedidos = 2 and rend.ingresos = 20000 and rend.costo = 9000 and rend.retorno = 2.22
         then 'OK  2 pedidos, $20.000, costo $9.000, 2,22x'
         else format('MAL  %s pedidos, %s ingresos, %s costo, %s x',
                     rend.pedidos, rend.ingresos, rend.costo, rend.retorno) end);

  select * into rend from public.rendimiento_campania(camp_plus);
  insert into _r values ('10 rendimiento de Plus',
    case when rend.pedidos = 1 and rend.ingresos = 10000 and rend.costo = envio_base
         then format('OK  solo cuenta el pedido con envio gratis (%sx)', rend.retorno)
         else format('MAL  %s pedidos, %s ingresos, %s costo', rend.pedidos, rend.ingresos, rend.costo) end);

  -- ---- Se le descuenta en la liquidación ------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  insert into _r values ('11 entra en la liquidacion',
    (select case when cargos = envio_base + 9000 and ventas = 20000
                 then format('OK  vendio $20.000 y se le descuentan $%s', envio_base + 9000)
                 else format('MAL  ventas=%s cargos=%s', ventas, cargos) end
       from public.pendiente_de_liquidar_comercios(current_date - 1, current_date)
      where comercio_id = com));

  perform set_config('request.jwt.claims', null, true);

  -- ---- Sin fondo, no hay envío gratis ---------------------------------------
  update public.campanias set presupuesto = envio_base where id = camp_plus;  -- ya gastado
  insert into _r values ('12 sin fondo no hay envio gratis',
    case when public.campania_plus_activa(com) is null then 'OK  la campania quedo sin fondo' else 'MAL' end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.campania_gastos where comercio_id = com;
  delete from public.campanias where comercio_id = com;
  delete from public.suscripciones_plus where cliente_id = cli;
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id in (ped.id, ped2.id));
  delete from public.pedido_items where pedido_id in (ped.id, ped2.id);
  delete from public.pedido_eventos where pedido_id in (ped.id, ped2.id);
  update public.pedidos set pago_id = null where id in (ped.id, ped2.id);
  delete from public.pagos where id in (ped.pago_id, ped2.pago_id);
  delete from public.pedidos where id in (ped.id, ped2.id);
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id in (cli, cli2);
  delete from public.clientes where id in (cli, cli2);
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli, u_cli2, u_adm);
end $$;

select paso, resultado from _r order by paso;
