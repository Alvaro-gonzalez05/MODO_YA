-- El rider se baja de un envío que ya había aceptado.
--
-- Lo que importa: que el pedido NO se muera. Antes el rider podía cancelar el
-- envío y el pedido quedaba pago, en `listo`, sin envío y sin que nadie lo
-- volviera a buscar.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  u_rid uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; dir uuid; prod uuid; sec uuid; rid uuid;
  ped public.pedidos;
  env public.envios;
  pg  public.pagos;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','aband-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','aband-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_rid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','aband-rid@test.local','x','{"rol":"repartidor"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Aband Local', 'Pizzeria', '2604000090', 'Roca 900',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;
  insert into public.secciones_menu (comercio_id, nombre) values (com, 'Pizzas') returning id into sec;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec, 'Muzzarella', 10000, true) returning id into prod;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion)
  values (u_rid, ciudad, 'Rider Aband', '2604111000', 'moto', 'aprobado', true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5840, -35.4750), 4326)::extensions.geography)
  returning id into rid;

  select id into cli from public.clientes where perfil_id = u_cli;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  -- ---- Pedido pago, aceptado y listo ----------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);

  ped := public.confirmar_pago_online(ped.id, 'PAY-ABAND', 'acreditado'::public.estado_pago,
    1::smallint, null, 'simulado-orden-aband');

  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  ped := public.aceptar_pedido(ped.id);
  ped := public.avanzar_pedido(ped.id, 'en_preparacion');
  ped := public.avanzar_pedido(ped.id, 'listo');
  perform set_config('request.jwt.claims', null, true);

  -- Se le asigna a nuestro rider.
  update public.envios set estado = 'asignado', repartidor_id = rid, asignado_en = now()
   where id = ped.envio_id;
  insert into public.ofertas (envio_id, repartidor_id, distancia_al_retiro_km, expira_en, respuesta, respondida_en)
  values (ped.envio_id, rid, 0.2, now() + interval '1 minute', 'aceptada', now());

  insert into _r values ('01 el envio quedo asignado',
    (select case when estado = 'asignado' and repartidor_id = rid
                 then 'OK  el rider lo tiene' else 'MAL  ' || estado end
       from public.envios where id = ped.envio_id));

  -- ---- El rider se baja ------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_rid)::text, true);
  env := public.abandonar_envio(ped.envio_id, 'Se me pinchó la rueda');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('02 el envio vuelve a buscar',
    case when env.estado = 'buscando_repartidor' and env.repartidor_id is null
         then 'OK  sigue vivo y sin rider' else format('MAL  %s', env.estado) end);

  insert into _r values ('03 el pedido no se murio',
    (select case when estado = 'listo'
                 then 'OK  sigue listo, esperando quien lo lleve'
                 else 'MAL  ' || estado end
       from public.pedidos where id = ped.id));

  insert into _r values ('04 queda registrado quien se bajo',
    (select case when motivo = 'Se me pinchó la rueda' and estado_al_bajarse = 'asignado'
                 then 'OK  con el motivo y en que estado' else 'MAL' end
       from public.abandonos_envio where envio_id = ped.envio_id and repartidor_id = rid));

  insert into _r values ('05 el rider queda libre',
    (select case when not ocupado then 'OK  puede tomar otro' else 'MAL  sigue ocupado' end
       from public.repartidores where id = rid));

  insert into _r values ('06 no se le vuelve a ofrecer al que se bajo',
    case when not exists (select 1 from public.repartidores_cercanos(ped.envio_id) where repartidor_id = rid)
         then 'OK  ya tuvo su oferta de este envio' else 'MAL  se lo ofrece de nuevo' end);

  -- ---- Con la comida encima no puede bajarse ---------------------------------
  -- Se le vuelve a asignar y avanza hasta retirado, paso por paso.
  update public.envios set estado = 'asignado', repartidor_id = rid, asignado_en = now()
   where id = ped.envio_id;
  update public.envios set estado = 'en_local' where id = ped.envio_id;
  update public.envios set estado = 'retirado' where id = ped.envio_id;
  perform set_config('request.jwt.claims', json_build_object('sub', u_rid)::text, true);
  begin
    env := public.abandonar_envio(ped.envio_id, 'Me arrepentí');
    insert into _r values ('07 retirado no puede bajarse', 'MAL  lo dejo');
  exception when others then
    insert into _r values ('07 retirado no puede bajarse', 'OK  rechazado: ' || left(sqlerrm, 32));
  end;

  -- Y tampoco puede cancelarlo.
  begin
    env := public.cancelar_envio(ped.envio_id, 'Chau');
    insert into _r values ('08 el rider ya no cancela envios', 'MAL  lo dejo cancelar');
  exception when others then
    insert into _r values ('08 el rider ya no cancela envios', 'OK  rechazado');
  end;
  perform set_config('request.jwt.claims', null, true);

  -- ---- Cancelar el envio arrastra al pedido y deja el reembolso --------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  env := public.cancelar_envio(ped.envio_id, 'No hay quien lo lleve');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('09 cancelar el envio cancela el pedido',
    (select case when estado = 'cancelado' then 'OK  no queda colgado' else 'MAL  ' || estado end
       from public.pedidos where id = ped.id));

  select * into pg from public.pagos where id = ped.pago_id;
  insert into _r values ('10 y deja la plata por devolver',
    case when pg.reembolso_pedido_en is not null
         then 'OK  el cron lo toma' else 'MAL  se quedo con la plata' end);

  insert into _r values ('11 sin penalidad al local',
    case when not exists (select 1 from public.cargos_comercio where comercio_id = com)
         then 'OK  el local no cancelo nada' else 'MAL  le cobro de mas' end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.abandonos_envio where envio_id = ped.envio_id;
  delete from public.ofertas where envio_id = ped.envio_id;
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id = ped.id);
  delete from public.pedido_items where pedido_id = ped.id;
  delete from public.pedido_eventos where pedido_id = ped.id;
  update public.pedidos set pago_id = null, envio_id = null where id = ped.id;
  delete from public.pagos where id = ped.pago_id;
  delete from public.envios where pedido_id = ped.id;
  delete from public.pedidos where id = ped.id;
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.repartidores where id = rid;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli, u_rid);
end $$;

select paso, resultado from _r order by paso;
