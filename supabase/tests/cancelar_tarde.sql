-- El cliente cancela solo mientras el local no tomó el pedido (0079).
--
-- Antes `cancelar_pedido` lo dejaba en cualquier estado y le devolvía el 100%:
-- con el pedido aceptado y la comida hecha, el local la perdía sin penalidad
-- para nadie. La pantalla ya escondía el botón; esto prueba que la base
-- también lo frena.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  u_otro uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; dir uuid; prod uuid; sec uuid;
  ped1 public.pedidos;
  ped2 public.pedidos;
  pg   public.pagos;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','tarde-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','tarde-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','tarde-otro@test.local','x','{"provider":"email"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Tarde Local', 'Pizzeria', '2604000091', 'Roca 901',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;
  insert into public.secciones_menu (comercio_id, nombre) values (com, 'Pizzas') returning id into sec;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec, 'Muzzarella', 10000, true) returning id into prod;

  select id into cli from public.clientes where perfil_id = u_cli;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 501',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  -- ---- Dos pedidos pagos ------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped1 := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);
  ped1 := public.confirmar_pago_online(ped1.id, 'PAY-TARDE-1', 'acreditado'::public.estado_pago,
    1::smallint, null, 'simulado-orden-tarde-1');

  -- Uno distinto: `crear_pedido` frena el doble pedido al mismo local (0056)
  -- mientras el primero está abierto, así que el segundo se crea después.

  -- ---- Otro cliente no toca un pedido ajeno ---------------------------------
  -- Para un cliente `mi_comercio_id()` es null: sin el coalesce de 0079 la
  -- comparación daba null y el permiso pasaba.
  perform set_config('request.jwt.claims', json_build_object('sub', u_otro)::text, true);
  begin
    perform public.cancelar_pedido(ped1.id, 'No es mio');
    insert into _r values ('00 un ajeno no lo cancela', 'MAL  lo dejo cancelar');
  exception when others then
    insert into _r values ('00 un ajeno no lo cancela', 'OK  rechazado');
  end;
  perform set_config('request.jwt.claims', null, true);

  -- ---- Pagado: el cliente puede cancelar ------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped1 := public.cancelar_pedido(ped1.id, 'Me equivoque');
  perform set_config('request.jwt.claims', null, true);

  select * into pg from public.pagos where id = ped1.pago_id;
  insert into _r values ('01 pagado sin aceptar se cancela',
    case when ped1.estado = 'cancelado' and pg.reembolso_pedido_en is not null
         then 'OK  cancelado y con la devolucion' else format('MAL  %s', ped1.estado) end);

  -- ---- Aceptado: ya no ------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped2 := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 2)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);
  ped2 := public.confirmar_pago_online(ped2.id, 'PAY-TARDE-2', 'acreditado'::public.estado_pago,
    1::smallint, null, 'simulado-orden-tarde-2');

  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  ped2 := public.aceptar_pedido(ped2.id);
  perform set_config('request.jwt.claims', null, true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  begin
    perform public.cancelar_pedido(ped2.id, 'Ya no lo quiero');
    insert into _r values ('02 aceptado no lo cancela el cliente', 'MAL  lo dejo cancelar');
  exception when others then
    insert into _r values ('02 aceptado no lo cancela el cliente', 'OK  rechazado: ' || left(sqlerrm, 28));
  end;
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('03 el pedido sigue en pie',
    (select case when p.estado = 'aceptado' and pg2.reembolso_pedido_en is null
                 then 'OK  aceptado y sin devolucion' else 'MAL  ' || p.estado end
       from public.pedidos p join public.pagos pg2 on pg2.id = p.pago_id where p.id = ped2.id));

  -- ---- El local sí puede (es su pedido) --------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  ped2 := public.cancelar_pedido(ped2.id, 'Se nos corto la luz');
  perform set_config('request.jwt.claims', null, true);
  insert into _r values ('04 el local cancela el suyo',
    case when ped2.estado = 'cancelado' then 'OK  cancelado' else format('MAL  %s', ped2.estado) end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id in (ped1.id, ped2.id));
  delete from public.pedido_items where pedido_id in (ped1.id, ped2.id);
  delete from public.pedido_eventos where pedido_id in (ped1.id, ped2.id);
  delete from public.cargos_comercio where comercio_id = com;
  update public.pedidos set pago_id = null, envio_id = null where id in (ped1.id, ped2.id);
  delete from public.pagos where id in (ped1.pago_id, ped2.pago_id);
  delete from public.envios where pedido_id in (ped1.id, ped2.id);
  delete from public.pedidos where id in (ped1.id, ped2.id);
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where perfil_id in (u_cli, u_otro);
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli, u_otro);
end $$;

select paso, resultado from _r order by paso;
