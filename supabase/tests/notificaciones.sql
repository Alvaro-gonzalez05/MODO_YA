-- Notificaciones: a quien le llega cada segmento, que se manda una sola vez y
-- que cada uno ve nada mas que lo suyo.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_adm uuid := gen_random_uuid();
  u_c1  uuid := gen_random_uuid();  -- cliente activo (pidio hoy)
  u_c2  uuid := gen_random_uuid();  -- cliente dormido (pidio hace 60 dias)
  u_c3  uuid := gen_random_uuid();  -- cliente con Plus, nunca pidio
  u_com uuid := gen_random_uuid();
  u_rep uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli1 uuid; cli2 uuid; cli3 uuid; dir uuid;
  seccion uuid; prod uuid;
  ped public.pedidos;
  noti public.notificaciones;
  n integer;
  vistas integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','noti-adm@test.local','x','{"rol":"admin"}','{"nombre":"Noti Admin"}',now(),now(),now()),
    (u_c1, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','noti-c1@test.local','x','{"provider":"email"}','{"nombre":"Cliente Activo"}',now(),now(),now()),
    (u_c2, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','noti-c2@test.local','x','{"provider":"email"}','{"nombre":"Cliente Dormido"}',now(),now(),now()),
    (u_c3, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','noti-c3@test.local','x','{"provider":"email"}','{"nombre":"Cliente Plus"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','noti-com@test.local','x','{"rol":"comercio"}','{"nombre":"Noti Local"}',now(),now(),now()),
    (u_rep,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','noti-rep@test.local','x','{"rol":"repartidor"}','{"nombre":"Noti Rider"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Noti Pizzeria','Pizzeria','2604000030','Roca 300',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846,-35.4757),4326)::extensions.geography,'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0,6) d;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_rep, ciudad, 'Noti Rider','2604111222','moto','aprobado');

  select id into cli1 from public.clientes where perfil_id = u_c1;
  select id into cli2 from public.clientes where perfil_id = u_c2;
  select id into cli3 from public.clientes where perfil_id = u_c3;

  -- El dormido se dio de alta hace mucho, para que no cuente como recien llegado.
  update public.clientes set creado_en = now() - interval '90 days' where id = cli2;

  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli1,'Casa','San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800,-35.4700),4326)::extensions.geography,true)
  returning id into dir;

  insert into public.secciones_menu (comercio_id, nombre) values (com,'Pizzas') returning id into seccion;
  insert into public.productos (comercio_id, seccion_id, nombre, precio)
  values (com, seccion, 'Muzzarella', 9000) returning id into prod;

  -- cli1 pidio hoy.
  perform set_config('request.jwt.claims', json_build_object('sub',u_c1)::text, true);
  ped := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'efectivo');
  perform set_config('request.jwt.claims', null, true);

  -- cli3 tiene Plus.
  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio)
  values (cli3, public.hoy() - 1, public.hoy() + 29, 2500);

  -- ---- Segmentos ------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_adm)::text, true);

  insert into _r values ('01 segmento clientes',
    case when (select count(*) from public.destinatarios('clientes')
                where perfil_id in (u_c1,u_c2,u_c3)) = 3
         then 'OK  los tres clientes' else 'MAL' end);

  insert into _r values ('02 el local no entra en clientes',
    case when not exists (select 1 from public.destinatarios('clientes') where perfil_id = u_com)
         then 'OK  fuera' else 'MAL  le llego a un local' end);

  insert into _r values ('03 segmento Plus',
    case when (select count(*) from public.destinatarios('clientes_plus')
                where perfil_id in (u_c1,u_c2,u_c3)) = 1
          and exists (select 1 from public.destinatarios('clientes_plus') where perfil_id = u_c3)
         then 'OK  solo el que tiene Plus' else 'MAL' end);

  insert into _r values ('04 inactivos a 30 dias',
    case when exists (select 1 from public.destinatarios('clientes_inactivos', 30) where perfil_id = u_c2)
          and not exists (select 1 from public.destinatarios('clientes_inactivos', 30) where perfil_id = u_c1)
         then 'OK  el dormido si, el que pidio hoy no' else 'MAL' end);

  insert into _r values ('05 el que nunca pidio cuenta por su alta',
    case when exists (select 1 from public.destinatarios('clientes_inactivos', 30) where perfil_id = u_c3)
         then 'MAL  se dio de alta hoy, no esta dormido'
         else 'OK  recien llegado no es inactivo' end);

  insert into _r values ('06 riders y locales',
    case when exists (select 1 from public.destinatarios('riders') where perfil_id = u_rep)
          and exists (select 1 from public.destinatarios('comercios') where perfil_id = u_com)
         then 'OK  cada uno en el suyo' else 'MAL' end);

  -- ---- Mandarla -------------------------------------------------------------
  insert into public.notificaciones (titulo, cuerpo, segmento, destino, creado_por)
  values ('Volve a pedir', 'Te extranamos: hoy tenes envio gratis.', 'clientes_inactivos', 'inicio', u_adm)
  returning * into noti;

  insert into _r values ('07 alcance antes de mandar',
    case when public.alcance_de('clientes_inactivos', 30) = (select count(*) from public.destinatarios('clientes_inactivos', 30))
         then 'OK  el numero que se ve es el que se manda' else 'MAL' end);

  noti := public.enviar_notificacion(noti.id);
  insert into _r values ('08 se mando',
    format('estado=%s alcance=%s', noti.estado, noti.alcance));

  insert into _r values ('09 le llego al dormido',
    case when exists (select 1 from public.notificacion_envios
                       where notificacion_id = noti.id and perfil_id = u_c2)
          and not exists (select 1 from public.notificacion_envios
                           where notificacion_id = noti.id and perfil_id = u_c1)
         then 'OK  al dormido si, al activo no' else 'MAL' end);

  begin
    perform public.enviar_notificacion(noti.id);
    insert into _r values ('10 no se manda dos veces', 'MAL  la dejo pasar');
  exception when others then
    insert into _r values ('10 no se manda dos veces', 'OK  rechazada');
  end;

  -- ---- Privacidad -----------------------------------------------------------
  -- Con `set local role authenticated` el RLS de verdad decide.
  perform set_config('request.jwt.claims', json_build_object('sub',u_c1)::text, true);
  set local role authenticated;
  select count(*) into vistas from public.v_notificaciones;
  reset role;
  insert into _r values ('11 el activo no ve la del dormido',
    case when vistas = 0 then 'OK  0 filas' else format('MAL  ve %s', vistas) end);

  perform set_config('request.jwt.claims', json_build_object('sub',u_c2)::text, true);
  set local role authenticated;
  select count(*) into vistas from public.v_notificaciones;
  reset role;
  insert into _r values ('12 el dormido ve la suya',
    case when vistas = 1 then 'OK  1 fila' else format('MAL  ve %s', vistas) end);

  begin
    perform set_config('request.jwt.claims', json_build_object('sub',u_c2)::text, true);
    set local role authenticated;
    select count(*) into n from public.destinatarios('clientes');
    reset role;
    insert into _r values ('13 un cliente no lista destinatarios',
      case when n = 0 then 'OK  0 filas' else format('MAL  vio %s perfiles', n) end);
  exception when others then
    reset role;
    insert into _r values ('13 un cliente no lista destinatarios', 'OK  rechazada');
  end;

  -- ---- Leerla ---------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_c2)::text, true);
  perform public.marcar_notificacion_leida(
    (select id from public.notificacion_envios where notificacion_id = noti.id and perfil_id = u_c2));
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('14 queda leida',
    case when (select leida_en is not null from public.notificacion_envios
                where notificacion_id = noti.id and perfil_id = u_c2)
         then 'OK  con fecha de lectura' else 'MAL' end);

  -- Un borrador no le aparece a nadie todavia.
  insert into public.notificaciones (titulo, cuerpo, segmento, creado_por)
  values ('Borrador', 'Todavia no se manda.', 'clientes', u_adm);

  perform set_config('request.jwt.claims', json_build_object('sub',u_c2)::text, true);
  set local role authenticated;
  select count(*) into vistas from public.v_notificaciones;
  reset role;
  perform set_config('request.jwt.claims', null, true);
  insert into _r values ('15 el borrador no se ve',
    case when vistas = 1 then 'OK  sigue viendo solo la enviada' else format('MAL  ve %s', vistas) end);

  -- ---- Limpieza -------------------------------------------------------------
  delete from public.notificaciones where creado_por = u_adm;
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id = ped.id);
  delete from public.pedido_items where pedido_id = ped.id;
  delete from public.pedido_eventos where pedido_id = ped.id;
  update public.pedidos set pago_id = null where id = ped.id;
  delete from public.pagos where id = ped.pago_id;
  delete from public.pedidos where id = ped.id;
  delete from public.suscripciones_plus where cliente_id = cli3;
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli1;
  delete from public.clientes where id in (cli1, cli2, cli3);
  delete from public.repartidores where perfil_id = u_rep;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_adm, u_c1, u_c2, u_c3, u_com, u_rep);
end $$;

select paso, resultado from _r order by paso;
