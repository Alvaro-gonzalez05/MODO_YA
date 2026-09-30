-- El rider propio del local: que se le ofrezca primero, que no trabe el envio
-- si no contesta, y que la plata no cambie.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_mio uuid := gen_random_uuid();   -- el rider del local, lejos
  u_otro uuid := gen_random_uuid();  -- uno del pool, pegado al local
  ciudad uuid; com uuid; mio uuid; otro uuid;
  env public.envios;
  of  public.ofertas;
  quien text;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_com, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','propio-com@test.local','x','{"rol":"comercio"}','{"nombre":"Local Propio"}',now(),now(),now()),
    (u_mio, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','propio-mio@test.local','x','{"rol":"repartidor"}','{"nombre":"Rider Del Local"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','propio-otro@test.local','x','{"rol":"repartidor"}','{"nombre":"Rider Del Pool"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Propio','Pizzeria','2604000050','Roca 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5839,-35.4761),4326)::extensions.geography,'aprobado')
  returning id into com;

  -- El del local esta a ~9 km: fuera del radio de busqueda de 3 km.
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_mio, ciudad, 'Rider Del Local','2604111333','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.6800,-35.4761),4326)::extensions.geography, now())
  returning id into mio;

  -- El del pool esta a 400 m: mucho mas cerca.
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_otro, ciudad, 'Rider Del Pool','2604111444','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800,-35.4755),4326)::extensions.geography, now())
  returning id into otro;

  -- ---- Sin vinculo: gana el mas cercano -------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  env := public.crear_envio('Av. San Martin 450', -35.4769, -69.5852,
                            'Marcela Diaz', '+54 260 456-1122', 'cliente');
  env := public.confirmar_envio(env.id);

  select r.nombre into quien
    from public.ofertas o join public.repartidores r on r.id = o.repartidor_id
   where o.envio_id = env.id;

  insert into _r values ('1. sin rider propio gana el mas cercano',
    case when quien = 'Rider Del Pool' then 'OK  ' || quien else 'MAL  ' || coalesce(quien,'nadie') end);

  delete from public.ofertas where envio_id = env.id;
  delete from public.envio_eventos where envio_id = env.id;
  delete from public.envios where id = env.id;

  -- ---- Con vinculo: gana el del local aunque este lejos ---------------------
  insert into public.comercio_riders (comercio_id, repartidor_id) values (com, mio);

  env := public.crear_envio('Av. San Martin 450', -35.4769, -69.5852,
                            'Marcela Diaz', '+54 260 456-1122', 'cliente');
  env := public.confirmar_envio(env.id);

  select * into of from public.ofertas where envio_id = env.id;
  select r.nombre into quien from public.repartidores r where r.id = of.repartidor_id;

  insert into _r values ('2. con rider propio se le ofrece a el',
    case when quien = 'Rider Del Local' then 'OK  ' || quien else 'MAL  ' || coalesce(quien,'nadie') end);

  insert into _r values ('3. aunque este fuera del radio',
    case when of.distancia_al_retiro_km > 3 then format('OK  a %s km, el radio es 3', of.distancia_al_retiro_km)
         else format('MAL  estaba a %s km', of.distancia_al_retiro_km) end);

  -- ---- Si no acepta, la busqueda sigue con el resto --------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_mio)::text, true);
  perform public.responder_oferta(of.id, false);
  perform set_config('request.jwt.claims', null, true);

  perform public.ofrecer_al_siguiente(env.id);

  select r.nombre into quien
    from public.ofertas o join public.repartidores r on r.id = o.repartidor_id
   where o.envio_id = env.id and o.respuesta is null;

  insert into _r values ('4. si no acepta, no traba: pasa al pool',
    case when quien = 'Rider Del Pool' then 'OK  ' || quien else 'MAL  ' || coalesce(quien,'nadie') end);

  -- ---- La plata no cambia ----------------------------------------------------
  insert into _r values ('5. cobra lo mismo que cualquier envio',
    case when env.comision > 0 and env.ganancia_repartidor > 0
         then format('OK  rider $%s + comision $%s', env.ganancia_repartidor, env.comision)
         else 'MAL  se toco la plata' end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.ofertas where envio_id = env.id;
  delete from public.envio_eventos where envio_id = env.id;
  delete from public.envios where id = env.id;
  delete from public.comercio_riders where comercio_id = com;
  delete from public.repartidores where id in (mio, otro);
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_mio, u_otro);
end $$;

select paso, resultado from _r order by paso;
