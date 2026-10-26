-- Confirmar la entrega dos veces del mismo envío.
--
-- El trigger de transiciones (`registrar_cambio_estado`) solo valida cuando el
-- estado **cambia**. Si el envío ya está `entregado`, volver a confirmarlo es
-- un `update` de `entregado` a `entregado`: el trigger no mira nada y
-- `viajes_completados` se incrementa de nuevo. El contador es lo que la
-- administración mira para saber cuánto trabajó un rider.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli uuid := gen_random_uuid();
  u_rep uuid := gen_random_uuid();
  ciudad uuid; cli uuid; rep uuid;
  env public.envios;
  of  public.ofertas;
  viajes_antes integer;
  n integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','menores-rep-cli@test.local','x','{"provider":"email"}','{"nombre":"Clienta Repetida","telefono":"+54 260 456-7788"}',now(),now(),now()),
    (u_rep,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','menores-rep-rid@test.local','x','{"rol":"repartidor"}','{"nombre":"Rider Repetido"}',now(),now(),now());

  select id into cli from public.clientes where perfil_id = u_cli;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_rep, ciudad, 'Rider Repetido','2604111777','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5820,-35.4760),4326)::extensions.geography, now())
  returning id into rep;

  select viajes_completados into viajes_antes from public.repartidores where id = rep;

  -- ---- Un mandado, que se cobra entero en la puerta ---------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  env := public.crear_mandado('Roca 400', -35.4761, -69.5839,
                              'San Martin 500', -35.4769, -69.5852,
                              'Un sobre');
  perform set_config('request.jwt.claims', null, true);

  perform set_config('request.jwt.claims', json_build_object('sub',u_rep)::text, true);
  select * into of from public.ofertas where envio_id = env.id and repartidor_id = rep;
  env := public.responder_oferta(of.id, true);
  env := public.avanzar_estado(env.id, 'en_local');
  env := public.avanzar_estado(env.id, 'retirado');
  env := public.avanzar_estado(env.id, 'en_camino');

  -- ---- La primera entrega ----------------------------------------------------
  env := public.confirmar_entrega(env.id, env.codigo_entrega);
  insert into _r values ('01 la entrega buena pasa',
    case when env.estado = 'entregado' then 'OK  entregado' else 'MAL  ' || env.estado end);

  insert into _r values ('02 suma un viaje',
    (select case when viajes_completados = viajes_antes + 1
                 then format('OK  %s viajes', viajes_completados)
                 else format('MAL  %s viajes', viajes_completados) end
       from public.repartidores where id = rep));

  -- ---- La segunda, con el código correcto, tiene que rebotar -----------------
  begin
    perform public.confirmar_entrega(env.id, env.codigo_entrega);
    insert into _r values ('03 confirmar de nuevo rebota', 'MAL  la dejo pasar en silencio');
  exception when others then
    insert into _r values ('03 confirmar de nuevo rebota', 'OK  rechazado: ' || left(sqlerrm, 40));
  end;

  insert into _r values ('04 el contador no se infla',
    (select case when viajes_completados = viajes_antes + 1
                 then format('OK  sigue en %s', viajes_completados)
                 else format('MAL  quedo en %s', viajes_completados) end
       from public.repartidores where id = rep));

  -- Y no se asienta un segundo evento de entrega en la auditoría.
  select count(*) into n from public.envio_eventos
   where envio_id = env.id and estado_nuevo = 'entregado';
  insert into _r values ('05 un solo evento de entrega',
    case when n = 1 then 'OK  1 evento' else format('MAL  %s eventos', n) end);

  -- ---- Un envío que todavía no llegó no se entrega "por las dudas" -----------
  -- El trigger ya frenaba el salto ilegal; lo que se agrega es que el mensaje
  -- diga qué pasó en vez de hablar de una transición.
  perform set_config('request.jwt.claims', null, true);
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  env := public.crear_mandado('Roca 400', -35.4761, -69.5839,
                              'San Martin 500', -35.4769, -69.5852,
                              'Otro sobre');
  perform set_config('request.jwt.claims', null, true);

  perform set_config('request.jwt.claims', json_build_object('sub',u_rep)::text, true);
  update public.envios set estado = 'asignado', repartidor_id = rep, asignado_en = now()
   where id = env.id;
  begin
    perform public.confirmar_entrega(env.id, env.codigo_entrega);
    insert into _r values ('06 asignado no se puede entregar', 'MAL  lo dejo');
  exception when others then
    insert into _r values ('06 asignado no se puede entregar', 'OK  rechazado: ' || left(sqlerrm, 40));
  end;

  insert into _r values ('07 y no suma un viaje de la nada',
    (select case when viajes_completados = viajes_antes + 1
                 then format('OK  sigue en %s', viajes_completados)
                 else format('MAL  quedo en %s', viajes_completados) end
       from public.repartidores where id = rep));
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.envio_eventos where envio_id in
    (select id from public.envios where cliente_id = cli);
  delete from public.ofertas where envio_id in
    (select id from public.envios where cliente_id = cli);
  delete from public.envios where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.repartidores where id = rep;
  delete from auth.users where id in (u_cli, u_rep);
end $$;

select paso, resultado from _r order by paso;
