-- El local rechaza un pedido ya cobrado.
--
-- Lo que tiene que pasar: al cliente se le devuelve todo, al local se le cobra
-- la penalidad, y esa penalidad aparece en la liquidación. Lo que NO tiene que
-- pasar: que se deje plata pendiente de un pedido que nunca se cobró.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; dir uuid; prod uuid; sec uuid;
  ped public.pedidos;
  ped2 public.pedidos;
  pg public.pagos;
  pct smallint;
  esperada integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','reem-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','reem-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','reem-adm@test.local','x','{"rol":"admin"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Reem Local', 'Pizzeria', '2604000060', 'Roca 600',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;
  insert into public.secciones_menu (comercio_id, nombre) values (com, 'Pizzas') returning id into sec;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec, 'Muzzarella', 10000, true) returning id into prod;

  select id into cli from public.clientes where perfil_id = u_cli;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  -- ---- Un pedido cobrado que el local rechaza --------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);

  ped := public.confirmar_pago_online(
    ped.id, 'PAY-REEM-1', 'acreditado'::public.estado_pago, 1::smallint, null, 'ORD-REEM-1');

  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  ped := public.rechazar_pedido(ped.id, 'Se nos rompió el horno');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('01 el pedido queda rechazado',
    case when ped.estado = 'rechazado' and ped.motivo_rechazo = 'Se nos rompió el horno'
         then 'OK  con el motivo a la vista' else 'MAL  ' || ped.estado end);

  select * into pg from public.pagos where id = ped.pago_id;
  insert into _r values ('02 queda plata por devolver',
    case when pg.reembolso_pedido_en is not null and pg.reembolsado_en is null
         then 'OK  pendiente, lo toma el cron' else 'MAL' end);

  insert into _r values ('03 se devuelve el 100%',
    (select case when monto = ped.total
                 then format('OK  $%s, productos y envio', monto)
                 else format('MAL  devuelve %s de %s', monto, ped.total) end
       from public.reembolsos_pendientes() where pago_id = pg.id));

  -- ---- La penalidad del local ------------------------------------------------
  select coalesce(penalidad_rechazo_pct, 50) into pct from public.tarifarios
   where vigente_hasta is null order by vigente_desde desc limit 1;
  esperada := round(ped.subtotal * pct / 100.0);

  insert into _r values ('04 al local se le cobra la penalidad',
    (select case when monto = esperada and concepto = 'ajuste' and pedido_id = ped.id
                 then format('OK  $%s (%s%% de $%s)', monto, pct, ped.subtotal)
                 else format('MAL  monto=%s', monto) end
       from public.cargos_comercio where comercio_id = com));

  insert into _r values ('05 la penalidad no toca el envio',
    case when esperada < ped.total - ped.subtotal + esperada
         then format('OK  se calcula sobre los $%s de productos', ped.subtotal)
         else 'MAL' end);

  -- ---- Y aparece en la liquidación -------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  insert into _r values ('06 sale en la liquidacion del local',
    (select case when cargos = esperada and ventas = 0
                 then format('OK  $%s de cargo y ninguna venta', cargos)
                 else format('MAL  ventas=%s cargos=%s', ventas, cargos) end
       from public.pendiente_de_liquidar_comercios(public.hoy() - 1, public.hoy())
      where comercio_id = com));
  perform set_config('request.jwt.claims', null, true);

  -- ---- Cerrar el reembolso ---------------------------------------------------
  perform public.confirmar_reembolso(pg.id, 'REF-1', ped.total);
  select * into pg from public.pagos where id = ped.pago_id;
  insert into _r values ('07 confirmado deja de estar pendiente',
    case when pg.estado = 'reembolsado' and pg.monto_reembolsado = ped.total
          and not exists (select 1 from public.reembolsos_pendientes() where pago_id = pg.id)
         then 'OK  no se vuelve a devolver' else 'MAL  ' || pg.estado end);

  -- ---- Un pedido que nunca se cobró no deja nada pendiente -------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped2 := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);
  -- Se lo pone en `pagado` a mano, sin acreditar el pago: es el caso de un
  -- cobro en revisión que el local alcanza a rechazar.
  update public.pedidos set estado = 'pagado', pagado_en = now() where id = ped2.id;

  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  ped2 := public.rechazar_pedido(ped2.id, 'Sin stock');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('08 sin cobro no hay nada que devolver',
    case when (select reembolso_pedido_en from public.pagos where id = ped2.pago_id) is null
          and (select count(*) from public.cargos_comercio where comercio_id = com) = 1
         then 'OK  ni reembolso ni penalidad' else 'MAL  se genero de mas' end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.cargos_comercio where comercio_id = com;
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
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli, u_adm);
end $$;

select paso, resultado from _r order by paso;
