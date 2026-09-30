-- Notificaciones automaticas: a quien le salta el carrito abandonado, a quien
-- el aviso de dormido, y sobre todo a quien NO se le repite.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_adm uuid := gen_random_uuid();
  u_c1  uuid := gen_random_uuid();  -- deja un pedido sin pagar
  u_c2  uuid := gen_random_uuid();  -- paga, no tiene que recibir nada
  u_c3  uuid := gen_random_uuid();  -- dormido hace 60 dias
  u_com uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli1 uuid; cli2 uuid; cli3 uuid; dir1 uuid; dir2 uuid;
  seccion uuid; prod uuid;
  ped1 public.pedidos;
  ped2 public.pedidos;
  n_carrito public.notificaciones;
  n_dormido public.notificaciones;
  n integer;
  titulo_visto text;
  reales uuid[];
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  -- Solo puede haber una automatica prendida por disparador. Si el proyecto ya
  -- tiene las suyas configuradas, se apagan mientras dura la prueba y se
  -- vuelven a prender al final, tal cual estaban.
  select coalesce(array_agg(id), '{}') into reales
    from public.notificaciones where disparador is not null and activa;
  update public.notificaciones set activa = false where id = any(reales);

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','auto-adm@test.local','x','{"rol":"admin"}','{"nombre":"Auto Admin"}',now(),now(),now()),
    (u_c1, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','auto-c1@test.local','x','{"provider":"email"}','{"nombre":"Marcela"}',now(),now(),now()),
    (u_c2, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','auto-c2@test.local','x','{"provider":"email"}','{"nombre":"Pagador"}',now(),now(),now()),
    (u_c3, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','auto-c3@test.local','x','{"provider":"email"}','{"nombre":"Dormido"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','auto-com@test.local','x','{"rol":"comercio"}','{"nombre":"Auto Local"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Auto Pizzeria','Pizzeria','2604000040','Roca 400',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846,-35.4757),4326)::extensions.geography,'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0,6) d;

  select id into cli1 from public.clientes where perfil_id = u_c1;
  select id into cli2 from public.clientes where perfil_id = u_c2;
  select id into cli3 from public.clientes where perfil_id = u_c3;
  update public.clientes set creado_en = now() - interval '90 days' where id = cli3;

  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli1,'Casa','San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800,-35.4700),4326)::extensions.geography,true)
  returning id into dir1;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli2,'Casa','San Martin 600',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800,-35.4701),4326)::extensions.geography,true)
  returning id into dir2;

  insert into public.secciones_menu (comercio_id, nombre) values (com,'Pizzas') returning id into seccion;
  insert into public.productos (comercio_id, seccion_id, nombre, precio)
  values (com, seccion, 'Muzzarella', 9000) returning id into prod;

  -- cli1 elige tarjeta y no paga: queda en pendiente_pago.
  perform set_config('request.jwt.claims', json_build_object('sub',u_c1)::text, true);
  ped1 := public.crear_pedido(com, dir1,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  -- cli2 paga en efectivo: nace pagado.
  perform set_config('request.jwt.claims', json_build_object('sub',u_c2)::text, true);
  ped2 := public.crear_pedido(com, dir2,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'efectivo');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('01 el pedido sin pagar queda esperando',
    case when ped1.estado = 'pendiente_pago' and ped2.estado = 'pagado'
         then 'OK  uno espera el pago y el otro ya entro' else 'MAL' end);

  -- ---- Carrito abandonado ---------------------------------------------------
  insert into public.notificaciones (titulo, cuerpo, disparador, recordatorios, creado_por)
  values ('{nombre}, te quedo un pedido sin pagar', 'Terminalo antes de que se cancele.',
          'carrito_abandonado', array[10,20]::smallint[], u_adm)
  returning * into n_carrito;

  -- Recien hecho: todavia no le toca.
  insert into _r values ('02 no avisa apenas se crea',
    case when public.avisar_carritos_abandonados() = 0 then 'OK  espera los minutos' else 'MAL  aviso de una' end);

  -- Se lo envejece para que caiga dentro de la ventana.
  update public.pedidos set creado_en = now() - interval '12 minutes' where id = ped1.id;

  insert into _r values ('03 avisa pasados los minutos',
    case when public.avisar_carritos_abandonados() = 1 then 'OK  1 aviso' else 'MAL' end);

  insert into _r values ('04 le avisa al que no pago, no al que pago',
    case when exists (select 1 from public.notificacion_envios
                       where notificacion_id = n_carrito.id and perfil_id = u_c1 and pedido_id = ped1.id)
          and not exists (select 1 from public.notificacion_envios
                           where notificacion_id = n_carrito.id and perfil_id = u_c2)
         then 'OK  solo el abandonado' else 'MAL' end);

  insert into _r values ('05 no repite el mismo recordatorio',
    case when public.avisar_carritos_abandonados() = 0 then 'OK  no insiste' else 'MAL  aviso dos veces' end);

  -- El segundo recordatorio: recien cuando pasan los 20 minutos.
  update public.pedidos set creado_en = now() - interval '22 minutes' where id = ped1.id;

  insert into _r values ('05b el segundo recordatorio si sale',
    case when public.avisar_carritos_abandonados() = 1 then 'OK  insiste una vez mas' else 'MAL' end);

  insert into _r values ('05c y ahi se planta',
    case when public.avisar_carritos_abandonados() = 0 then 'OK  no hay mas momentos' else 'MAL  sigue insistiendo' end);

  insert into _r values ('05d quedaron los dos avisos',
    (select format('%s avisos, en los minutos %s', count(*), string_agg(minuto::text, ' y ' order by minuto))
       from public.notificacion_envios where notificacion_id = n_carrito.id and pedido_id = ped1.id));

  -- Si el cron estuvo caido, el pedido llega viejo con varios recordatorios ya
  -- vencidos. Tiene que mandar UNO, no la pila entera: tres mensajes juntos son
  -- peor que ninguno.
  delete from public.notificacion_envios where notificacion_id = n_carrito.id;
  update public.pedidos set creado_en = now() - interval '25 minutes' where id = ped1.id;

  insert into _r values ('05e con el cron caido manda uno solo',
    case when public.avisar_carritos_abandonados() = 1 then 'OK  se pone al dia con uno' else 'MAL  mando los atrasados juntos' end);

  insert into _r values ('05f y manda el ultimo que correspondia',
    case when (select minuto from public.notificacion_envios
                where notificacion_id = n_carrito.id and pedido_id = ped1.id) = 20
         then 'OK  el de los 20, no el de los 10' else 'MAL' end);

  insert into _r values ('06 el aviso lleva al pago de ese pedido',
    case when (select pedido_id from public.notificacion_envios
                where notificacion_id = n_carrito.id and perfil_id = u_c1) = ped1.id
         then 'OK  sabe que pedido abrir' else 'MAL' end);

  -- ---- Personalizacion ------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_c1)::text, true);
  set local role authenticated;
  select titulo into titulo_visto from public.v_notificaciones where perfil_id = u_c1;
  reset role;
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('07 lo saluda por su nombre',
    case when titulo_visto = 'Marcela, te quedo un pedido sin pagar'
         then 'OK  ' || titulo_visto else 'MAL  ' || coalesce(titulo_visto, 'nada') end);

  -- ---- Clientes dormidos ----------------------------------------------------
  insert into public.notificaciones (titulo, cuerpo, segmento, disparador,
                                     dias_inactividad, repetir_cada_dias, creado_por)
  values ('Te extranamos', 'Volve a pedir y te hacemos el envio gratis.',
          'clientes_inactivos', 'cliente_inactivo', 30, 30, u_adm)
  returning * into n_dormido;

  perform public.avisar_clientes_inactivos();

  insert into _r values ('08 le avisa al dormido',
    case when exists (select 1 from public.notificacion_envios
                       where notificacion_id = n_dormido.id and perfil_id = u_c3)
         then 'OK  le llego' else 'MAL' end);

  insert into _r values ('09 no le avisa al que acaba de pedir',
    case when not exists (select 1 from public.notificacion_envios
                           where notificacion_id = n_dormido.id and perfil_id in (u_c1, u_c2))
         then 'OK  esos pidieron hoy' else 'MAL  le escribio a un cliente activo' end);

  insert into _r values ('10 no lo cansa: no repite antes de tiempo',
    case when public.avisar_clientes_inactivos() = 0 then 'OK  lo deja tranquilo' else 'MAL  insistio' end);

  -- Pasado el periodo, si le vuelve a escribir.
  update public.notificacion_envios set creado_en = now() - interval '40 days'
   where notificacion_id = n_dormido.id and perfil_id = u_c3;

  insert into _r values ('11 pasado el periodo vuelve a escribir',
    case when public.avisar_clientes_inactivos() = 1 then 'OK  le escribio de nuevo' else 'MAL' end);

  -- ---- Apagada no manda -----------------------------------------------------
  -- Se borra el envio para que el pedido vuelva a ser elegible: asi lo que se
  -- prueba es el interruptor y no el control de "no repetir".
  delete from public.notificacion_envios where notificacion_id = n_carrito.id;
  update public.notificaciones set activa = false where id = n_carrito.id;

  insert into _r values ('12 apagada no manda nada',
    case when public.avisar_carritos_abandonados() = 0 then 'OK  esta apagada' else 'MAL  mando igual' end);

  -- ---- Limpieza -------------------------------------------------------------
  delete from public.notificaciones where creado_por = u_adm;
  update public.notificaciones set activa = true where id = any(reales);
  delete from public.pedido_items where pedido_id in (ped1.id, ped2.id);
  delete from public.pedido_eventos where pedido_id in (ped1.id, ped2.id);
  update public.pedidos set pago_id = null where id in (ped1.id, ped2.id);
  delete from public.pagos where id in (ped1.pago_id, ped2.pago_id);
  delete from public.pedidos where id in (ped1.id, ped2.id);
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id in (cli1, cli2, cli3);
  delete from public.clientes where id in (cli1, cli2, cli3);
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_adm, u_c1, u_c2, u_c3, u_com);
end $$;

select paso, resultado from _r order by paso;
