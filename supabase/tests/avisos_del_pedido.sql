-- Los avisos del pedido (0080).
--
-- Lo que tiene que pasar:
--   * cada cambio del pedido y del envío le avisa a quien le importa, con la
--     pantalla que tiene que abrir, y nunca a quien hizo el cambio;
--   * los avisos no llevan pedido_id (la 1.17 lo abre en la pantalla de pago);
--   * "el rider está llegando" y "te quedan 5 minutos" salen una sola vez;
--   * un pedido que nunca se pagó se cancela sin avisarle a nadie;
--   * se le pide a la Edge Function una sola vez por transacción.
--
-- Borra lo que crea al final. Los avisos van a perfiles de prueba sin celular
-- registrado, así que la Edge Function los da por mandados sin mandar nada.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  u_rid uuid := gen_random_uuid();
  ciudad uuid; tarifa uuid; cli uuid; com uuid; rid uuid;
  ped public.pedidos; ped2 public.pedidos; viejo public.pedidos;
  env public.envios;
  a public.avisos;
  n integer; llamadas_antes integer;
  lejos  extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography;
  casa   extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography;
  -- ~100 m de la casa.
  cerca  extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4709), 4326)::extensions.geography;

begin
  select count(*) into llamadas_antes from net.http_request_queue;
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  tarifa := (public.tarifario_vigente(ciudad, 'delivery')).id;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','avisos-com@modoya.test','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','avisos-cli@modoya.test','x','{"provider":"email"}',now(),now(),now()),
    (u_rid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','avisos-rid@modoya.test','x','{"rol":"repartidor"}',now(),now(),now());
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Pizzeria Avisos', 'Pizzeria', '2604111010', 'Roca 100', lejos, 'aprobado')
  returning id into com;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_rid, ciudad, 'Juan Avisos', '2604222020', 'moto', 'aprobado')
  returning id into rid;
  select id into cli from public.clientes where perfil_id = u_cli;

  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago)
  values (ciudad, cli, com, 'San Martin 500', casa, 10000, 3550, 'pendiente_pago', 'tarjeta')
  returning * into ped;

  -- ---- Pedido nuevo: al local, con el timbre ------------------------------------
  update public.pedidos set estado = 'pagado', pagado_en = now() where id = ped.id;
  select * into a from public.avisos where perfil_id = u_com and tipo = 'pedido_nuevo';
  insert into _r values ('01 pedido nuevo le avisa al local por el canal del timbre',
    case when a.canal = 'pedidos' and a.ruta = '/local/pedidos' and a.titulo like 'Pedido nuevo P-%'
         and a.vence_en <= now() + interval '15 minutes' then 'OK' else 'FALLA ' || coalesce(a.titulo, 'sin aviso') end);

  -- ---- Lo acepta el local: al cliente sí, al local no ---------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  update public.pedidos set estado = 'aceptado' where id = ped.id;
  perform set_config('request.jwt.claims', '', true);
  select * into a from public.avisos where perfil_id = u_cli and tipo = 'pedido_aceptado';
  insert into _r values ('02 aceptado le avisa al cliente y abre su pedido',
    case when a.ruta = '/cliente/pedidos/' || ped.id and a.destino = 'mis_pedidos' then 'OK' else 'FALLA ' || coalesce(a.ruta, 'sin aviso') end);
  select count(*) into n from public.avisos where perfil_id = u_com and tipo <> 'pedido_nuevo';
  insert into _r values ('03 al local que aceptó no le llega nada', case when n = 0 then 'OK' else 'FALLA ' || n end);

  -- ---- El envío: rider asignado, pedido listo -----------------------------------
  insert into public.envios (ciudad_id, servicio, comercio_id, origen_calle, origen_ubicacion,
                             destino_calle, destino_ubicacion, cliente_nombre, cliente_telefono,
                             tarifario_id, distancia_km, ganancia_repartidor, comision, paga,
                             estado, pedido_id)
  values (ciudad, 'delivery', com, 'Roca 100', lejos, 'San Martin 500', casa, 'Cliente', '2604333030',
          tarifa, 1.2, 2500, 1050, 'cliente', 'buscando_repartidor', ped.id)
  returning * into env;
  update public.pedidos set envio_id = env.id where id = ped.id;

  insert into public.ofertas (envio_id, repartidor_id, distancia_al_retiro_km, expira_en)
  values (env.id, rid, 0.8, now() + interval '40 seconds');
  select * into a from public.avisos where perfil_id = u_rid and tipo = 'oferta';
  insert into _r values ('04 la oferta le llega al rider y vence con la oferta',
    case when a.canal = 'ofertas' and a.vence_en <= now() + interval '41 seconds'
         and a.cuerpo like 'Retirás en Pizzeria Avisos%ganás $%' then 'OK' else 'FALLA ' || coalesce(a.cuerpo, 'sin aviso') end);

  update public.envios set repartidor_id = rid, estado = 'asignado' where id = env.id;
  select * into a from public.avisos where perfil_id = u_com and tipo = 'rider_asignado';
  insert into _r values ('05 rider asignado le avisa al local',
    case when a.titulo = 'Juan va para el local' and a.ruta = '/local/envios/' || env.id then 'OK' else 'FALLA ' || coalesce(a.titulo, 'sin aviso') end);

  update public.pedidos set estado = 'en_preparacion' where id = ped.id;
  update public.pedidos set estado = 'listo' where id = ped.id;
  select * into a from public.avisos where perfil_id = u_rid and tipo = 'pedido_listo';
  insert into _r values ('06 pedido listo le avisa al rider y abre el servicio',
    case when a.ruta = '/servicio/' || env.id then 'OK' else 'FALLA ' || coalesce(a.ruta, 'sin aviso') end);

  -- ---- Lo retira: el pedido pasa a en camino ------------------------------------
  update public.envios set estado = 'en_local' where id = env.id;
  update public.envios set estado = 'retirado' where id = env.id;
  update public.envios set estado = 'en_camino' where id = env.id;
  select * into a from public.avisos where perfil_id = u_cli and tipo = 'pedido_en_camino';
  insert into _r values ('07 retirado: el cliente sabe que va en camino y con quién',
    case when a.cuerpo = 'Juan ya lo retiró de Pizzeria Avisos.' then 'OK' else 'FALLA ' || coalesce(a.cuerpo, 'sin aviso') end);

  -- ---- Está llegando: una sola vez ----------------------------------------------
  update public.repartidores set ultima_ubicacion = lejos where id = rid;
  select count(*) into n from public.avisos where tipo = 'rider_cerca';
  insert into _r values ('08 lejos de la casa no avisa', case when n = 0 then 'OK' else 'FALLA ' || n end);
  update public.repartidores set ultima_ubicacion = cerca where id = rid;
  update public.repartidores set ultima_ubicacion = extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4705), 4326)::extensions.geography where id = rid;
  select count(*) into n from public.avisos where perfil_id = u_cli and tipo = 'rider_cerca';
  insert into _r values ('09 a 100 m avisa que está llegando, una sola vez', case when n = 1 then 'OK' else 'FALLA ' || n end);

  -- ---- Entregado ----------------------------------------------------------------
  update public.envios set estado = 'entregado' where id = env.id;
  select count(*) into n from public.avisos where perfil_id = u_cli and tipo = 'pedido_entregado';
  insert into _r values ('10 entregado le avisa al cliente', case when n = 1 then 'OK' else 'FALLA ' || n end);

  -- ---- Ningún aviso lleva pedido_id ---------------------------------------------
  select count(*) into n from public.avisos where perfil_id in (u_com, u_cli, u_rid) and ruta like '%/pagar/%';
  insert into _r values ('11 ninguno abre la pantalla de pago', case when n = 0 then 'OK' else 'FALLA ' || n end);

  -- ---- El reloj: te quedan 5 minutos, una vez -----------------------------------
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago)
  values (ciudad, cli, com, 'San Martin 500', casa, 10000, 3550, 'pendiente_pago', 'tarjeta')
  returning * into viejo;
  update public.pedidos set estado = 'pagado', pagado_en = now() - interval '12 minutes' where id = viejo.id;
  perform public.avisos_del_reloj();
  perform public.avisos_del_reloj();
  select count(*) into n from public.avisos where perfil_id = u_com and tipo = 'pedido_por_vencer';
  insert into _r values ('12 a los 12 minutos: te quedan 5, una sola vez', case when n = 1 then 'OK' else 'FALLA ' || n end);

  -- ---- Cancelado sin pagar: nadie se entera -------------------------------------
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago)
  values (ciudad, cli, com, 'San Martin 500', casa, 10000, 3550, 'pendiente_pago', 'tarjeta')
  returning * into ped2;
  select count(*) into n from public.avisos where perfil_id in (u_com, u_cli);
  update public.pedidos set estado = 'cancelado', cancelado_en = now() where id = ped2.id;
  select count(*) - n into n from public.avisos where perfil_id in (u_com, u_cli);
  insert into _r values ('13 un pedido sin pagar se cancela sin avisar', case when n = 0 then 'OK' else 'FALLA ' || n end);

  -- ---- Una llamada a la Edge Function por transacción ---------------------------
  select count(*) - llamadas_antes into n from net.http_request_queue;
  insert into _r values ('14 una sola llamada a enviar-push por transacción', case when n = 1 then 'OK' else 'FALLA ' || n end);

  -- ---- Limpieza -----------------------------------------------------------------
  update public.pedidos set envio_id = null where id in (ped.id, viejo.id, ped2.id);
  delete from public.ofertas where envio_id = env.id;
  delete from public.envios where id = env.id;
  delete from public.pedidos where id in (ped.id, viejo.id, ped2.id);
  delete from public.clientes where id = cli;
  delete from auth.users where id in (u_com, u_cli, u_rid);
end $$;

select * from _r order by paso;
