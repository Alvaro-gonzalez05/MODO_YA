-- Doble pedido del mismo local (0056): que el segundo pedido se le ofrezca al
-- rider que ya va para ese local, que no pase de dos, que no se sumen pedidos
-- de otro local, y que entregar uno no lo libere si le queda el otro.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com  uuid := gen_random_uuid();
  u_com2 uuid := gen_random_uuid();
  u_uno  uuid := gen_random_uuid();  -- a 400 m del local
  u_dos  uuid := gen_random_uuid();  -- a 200 m: el mas cercano
  ciudad uuid; com uuid; com2 uuid; uno uuid; dos uuid;
  e1 public.envios; e2 public.envios; e3 public.envios; e4 public.envios;
  of public.ofertas;
  quien text;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_com, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','doble-com@test.local','x','{"rol":"comercio"}','{"nombre":"Local Doble"}',now(),now(),now()),
    (u_com2,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','doble-com2@test.local','x','{"rol":"comercio"}','{"nombre":"Otro Local"}',now(),now(),now()),
    (u_uno, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','doble-uno@test.local','x','{"rol":"repartidor"}','{"nombre":"Rider Uno"}',now(),now(),now()),
    (u_dos, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','doble-dos@test.local','x','{"rol":"repartidor"}','{"nombre":"Rider Dos"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Doble','Pizzeria','2604000060','Roca 600',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5839,-35.4761),4326)::extensions.geography,'aprobado')
  returning id into com;
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com2, ciudad, 'Otro Local','Heladeria','2604000061','Roca 650',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5835,-35.4760),4326)::extensions.geography,'aprobado')
  returning id into com2;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_uno, ciudad, 'Rider Uno','2604111555','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800,-35.4755),4326)::extensions.geography, now())
  returning id into uno;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_dos, ciudad, 'Rider Dos','2604111666','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5820,-35.4758),4326)::extensions.geography, now())
  returning id into dos;

  -- ---- Primer pedido: lo toma el mas cercano ---------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  e1 := public.confirmar_envio((public.crear_envio('Av. San Martin 450', -35.4769, -69.5852,
                                'Marcela Diaz', '+54 260 456-1122', 'cliente')).id);
  select * into of from public.ofertas where envio_id = e1.id and respuesta is null;
  perform set_config('request.jwt.claims', json_build_object('sub',u_dos)::text, true);
  e1 := public.responder_oferta(of.id, true);

  -- ---- Segundo pedido del mismo local: a Dos, aunque Uno este libre ----------
  -- Dos se aleja un poco: igual va primero, porque ya va para el local.
  update public.repartidores
     set ultima_ubicacion = extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5700,-35.4700),4326)::extensions.geography
   where id = dos;

  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  e2 := public.confirmar_envio((public.crear_envio('Saturnino Torres 120', -35.4720, -69.5880,
                                'Julio Paez', '+54 260 456-3344', 'cliente')).id);
  select * into of from public.ofertas where envio_id = e2.id and respuesta is null;
  select nombre into quien from public.repartidores where id = of.repartidor_id;
  insert into _r values ('1. el segundo pedido va al que ya va al local',
    case when quien = 'Rider Dos' then 'OK  ' || quien else 'MAL  ' || coalesce(quien,'nadie') end);

  perform set_config('request.jwt.claims', json_build_object('sub',u_dos)::text, true);
  e2 := public.responder_oferta(of.id, true);
  insert into _r values ('2. lo acepta y lleva los dos',
    case when (select count(*) from public.envios where repartidor_id = dos and estado = 'asignado') = 2
         then 'OK  dos asignados' else 'MAL' end);

  -- ---- Tercero: Dos ya lleva dos, va a Uno -----------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  e3 := public.confirmar_envio((public.crear_envio('Rufino Ortega 80', -35.4745, -69.5870,
                                'Ana Lopez', '+54 260 456-5566', 'cliente')).id);
  select * into of from public.ofertas where envio_id = e3.id and respuesta is null;
  select nombre into quien from public.repartidores where id = of.repartidor_id;
  insert into _r values ('3. con dos encima no recibe un tercero',
    case when quien = 'Rider Uno' then 'OK  pasa a ' || quien else 'MAL  ' || coalesce(quien,'nadie') end);
  perform set_config('request.jwt.claims', json_build_object('sub',u_uno)::text, true);
  e3 := public.responder_oferta(of.id, true);

  -- ---- Otro local: Uno lleva uno de Local Doble, no se le suma ---------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com2)::text, true);
  e4 := public.confirmar_envio((public.crear_envio('Av. San Martin 900', -35.4790, -69.5850,
                                'Pedro Gil', '+54 260 456-7788', 'cliente')).id);
  insert into _r values ('4. un pedido de otro local no se suma',
    case when not exists (select 1 from public.ofertas where envio_id = e4.id)
         then 'OK  nadie libre, espera' else 'MAL  se lo ofrecio a alguien ocupado' end);

  -- ---- Si ya lo retiro, ya se fue: no se suma ---------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_uno)::text, true);
  perform public.avanzar_estado(e3.id, 'en_local');
  perform public.avanzar_estado(e3.id, 'retirado');
  perform set_config('request.jwt.claims', json_build_object('sub',u_com2)::text, true);
  perform public.cancelar_envio(e4.id, 'prueba');
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  e4 :=public.confirmar_envio((public.crear_envio('Av. San Martin 950', -35.4795, -69.5850,
                                'Pedro Gil', '+54 260 456-7788', 'cliente')).id);
  insert into _r values ('5. si ya retiro el primero no se le suma',
    case when not exists (select 1 from public.ofertas where envio_id = e4.id)
         then 'OK  no se le ofrece' else 'MAL' end);

  -- ---- Entregar uno no lo libera si le queda el otro --------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_dos)::text, true);
  perform public.avanzar_estado(e1.id, 'en_local');
  perform public.avanzar_estado(e1.id, 'retirado');
  perform public.avanzar_estado(e1.id, 'en_camino');
  perform public.confirmar_entrega(e1.id, e1.codigo_entrega);
  insert into _r values ('6. entrega el primero y sigue ocupado',
    case when (select ocupado from public.repartidores where id = dos) then 'OK  le queda uno' else 'MAL  quedo libre' end);

  perform public.cancelar_envio(e2.id, 'prueba');
  insert into _r values ('7. sin envios queda libre',
    case when not (select ocupado from public.repartidores where id = dos) then 'OK  libre' else 'MAL  sigue ocupado' end);

  insert into _r values ('8. cada envio tiene su codigo y su ganancia',
    case when e1.codigo_entrega is not null and e2.codigo_entrega is not null
              and e1.ganancia_repartidor > 0 and e2.ganancia_repartidor > 0
         then 'OK' else 'MAL' end);

  -- ---- Limpieza --------------------------------------------------------------
  perform set_config('request.jwt.claims', null, true);
  delete from public.ofertas where envio_id in (select id from public.envios where comercio_id in (com, com2));
  delete from public.envio_eventos where envio_id in (select id from public.envios where comercio_id in (com, com2));
  delete from public.envios where comercio_id in (com, com2);
  delete from public.repartidores where id in (uno, dos);
  delete from public.comercios where id in (com, com2);
  delete from auth.users where id in (u_com, u_com2, u_uno, u_dos);
end $$;

select paso, resultado from _r order by paso;
