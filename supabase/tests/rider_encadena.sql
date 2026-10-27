-- El rider encadena envíos y la búsqueda no se rinde (0077).
--
-- Lo que tiene que pasar:
--   * un rider con un envío en curso recibe ofertas de otro local, pero
--     después de los libres;
--   * el que ya va al mismo local sigue primero (0056);
--   * con dos envíos no le llega un tercero;
--   * un pedido de la app no pasa a `sin_repartidor` a las 3 horas, y la
--     cadetería del local sí.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_cli uuid := gen_random_uuid();
  u_libre uuid := gen_random_uuid(); u_uno uuid := gen_random_uuid(); u_dos uuid := gen_random_uuid();
  ciudad uuid; tarifa uuid; cli uuid;
  loc_a uuid; loc_b uuid;
  libre uuid; uno uuid; dos uuid;
  pto_a constant extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography;
  pto_b constant extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5820, -35.4770), 4326)::extensions.geography;
  casa  constant extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography;
  nuevo uuid; mismo_local uuid; viejo_app uuid; viejo_local uuid;
  ped uuid;
  orden uuid[];
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  tarifa := (public.tarifario_vigente(ciudad, 'delivery')).id;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','enc-a@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_b,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','enc-b@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','enc-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_libre,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','enc-libre@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_uno,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','enc-uno@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_dos,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','enc-dos@test.local','x','{"rol":"repartidor"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_a, ciudad, 'Encadena A', 'Pizzeria', '2604111011', 'Roca 100', pto_a, 'aprobado') returning id into loc_a;
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_b, ciudad, 'Encadena B', 'Pizzeria', '2604111012', 'Roca 300', pto_b, 'aprobado') returning id into loc_b;
  select id into cli from public.clientes where perfil_id = u_cli;

  -- El libre está más lejos del local B que el ocupado: si el orden fuera
  -- solo por distancia, el ocupado saldría primero.
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion, conectado,
                                   ultima_ubicacion, ultima_ubicacion_en)
  values (u_libre, ciudad, 'Libre', '2604222001', 'moto', 'aprobado', true, pto_a, now()) returning id into libre;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion, conectado,
                                   ultima_ubicacion, ultima_ubicacion_en)
  values (u_uno, ciudad, 'Con uno', '2604222002', 'moto', 'aprobado', true, pto_b, now()) returning id into uno;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion, conectado,
                                   ultima_ubicacion, ultima_ubicacion_en)
  values (u_dos, ciudad, 'Con dos', '2604222003', 'moto', 'aprobado', true, pto_b, now()) returning id into dos;

  -- "Con uno" lleva un envío del local A, ya en camino. "Con dos" lleva dos.
  insert into public.envios (ciudad_id, comercio_id, origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
                             cliente_nombre, cliente_telefono, tarifario_id, distancia_km, ganancia_repartidor,
                             comision, paga, estado, repartidor_id)
  select ciudad, loc_a, 'Roca 100', pto_a, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
         'comercio', 'en_camino', r
    from unnest(array[uno, dos, dos]) r;
  update public.repartidores set ocupado = true where id in (uno, dos);

  -- ---- Un envío nuevo del local B --------------------------------------------
  insert into public.envios (ciudad_id, comercio_id, origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
                             cliente_nombre, cliente_telefono, tarifario_id, distancia_km, ganancia_repartidor,
                             comision, paga, estado)
  values (ciudad, loc_b, 'Roca 300', pto_b, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
          'comercio', 'buscando_repartidor')
  returning id into nuevo;

  -- Solo los riders de la prueba: la base puede tener riders de verdad conectados.
  select array_agg(c.rid order by c.ord) into orden
    from public.repartidores_cercanos(nuevo) with ordinality as c(rid, km, ord)
   where c.rid in (libre, uno, dos);

  insert into _r values ('01 el ocupado con uno recibe ofertas de otro local',
    case when uno = any(orden) then 'OK' else 'MAL  no es candidato' end);
  insert into _r values ('02 pero después del libre, aunque esté más cerca',
    case when orden[1] = libre and orden[2] = uno then 'OK' else 'MAL  orden ' || coalesce(array_to_string(orden, ','), '-') end);
  insert into _r values ('03 con dos envíos no le llega un tercero',
    case when not (dos = any(orden)) then 'OK' else 'MAL  le ofrece al que lleva dos' end);

  -- Sin el libre, el ocupado es el primero.
  update public.repartidores set conectado = false where id = libre;
  select array_agg(c.rid order by c.ord) into orden
    from public.repartidores_cercanos(nuevo) with ordinality as c(rid, km, ord)
   where c.rid in (libre, uno, dos);
  insert into _r values ('04 sin libres, el ocupado es el primero',
    case when orden[1] = uno then 'OK' else 'MAL  orden ' || coalesce(array_to_string(orden, ','), '-') end);
  update public.repartidores set conectado = true where id = libre;

  -- ---- El que va al mismo local sigue primero (0056) --------------------------
  -- "Libre" pasa a ir a buscar uno al local A; sale otro de A.
  insert into public.envios (ciudad_id, comercio_id, origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
                             cliente_nombre, cliente_telefono, tarifario_id, distancia_km, ganancia_repartidor,
                             comision, paga, estado, repartidor_id)
  values (ciudad, loc_a, 'Roca 100', pto_a, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
          'comercio', 'asignado', libre);
  update public.repartidores set ocupado = true, ultima_ubicacion = pto_b where id = libre;
  insert into public.envios (ciudad_id, comercio_id, origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
                             cliente_nombre, cliente_telefono, tarifario_id, distancia_km, ganancia_repartidor,
                             comision, paga, estado)
  values (ciudad, loc_a, 'Roca 100', pto_a, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
          'comercio', 'buscando_repartidor')
  returning id into mismo_local;
  select array_agg(c.rid order by c.ord) into orden
    from public.repartidores_cercanos(mismo_local) with ordinality as c(rid, km, ord)
   where c.rid in (libre, uno, dos);
  insert into _r values ('05 el que ya va al mismo local sigue primero',
    case when orden[1] = libre then 'OK' else 'MAL  orden ' || coalesce(array_to_string(orden, ','), '-') end);

  -- ---- Aceptar el segundo y no un tercero ----------------------------------------
  insert into public.ofertas (envio_id, repartidor_id, distancia_al_retiro_km, expira_en)
  values (nuevo, uno, 0.3, now() + interval '30 seconds');
  perform set_config('request.jwt.claims', json_build_object('sub', u_uno)::text, true);
  perform public.responder_oferta((select id from public.ofertas where envio_id = nuevo and repartidor_id = uno), true);
  perform set_config('request.jwt.claims', null, true);
  insert into _r values ('06 el ocupado acepta el de otro local y queda con dos',
    case when (select repartidor_id from public.envios where id = nuevo) = uno
          and (select count(*) from public.envios where repartidor_id = uno
                and estado in ('asignado','en_local','retirado','en_camino')) = 2
         then 'OK' else 'MAL' end);

  -- ---- La búsqueda de un pedido no se rinde ----------------------------------------
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago)
  values (ciudad, cli, loc_b, 'San Martin 500', casa, 10000, 0, 'listo', 'tarjeta')
  returning id into ped;
  insert into public.envios (ciudad_id, comercio_id, pedido_id, origen_calle, origen_ubicacion, destino_calle,
                             destino_ubicacion, cliente_nombre, cliente_telefono, tarifario_id, distancia_km,
                             ganancia_repartidor, comision, paga, estado, creado_en)
  values (ciudad, loc_b, ped, 'Roca 300', pto_b, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
          'cliente', 'buscando_repartidor', now() - interval '4 hours')
  returning id into viejo_app;
  insert into public.envios (ciudad_id, comercio_id, origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
                             cliente_nombre, cliente_telefono, tarifario_id, distancia_km, ganancia_repartidor,
                             comision, paga, estado, creado_en)
  values (ciudad, loc_b, 'Roca 300', pto_b, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
          'comercio', 'buscando_repartidor', now() - interval '4 hours')
  returning id into viejo_local;
  -- Que nadie los pueda tomar: así la prueba mide el tope y no una oferta.
  update public.repartidores set conectado = false where id in (libre, uno, dos);

  perform public.vencer_ofertas();
  insert into _r values ('07 un pedido de la app sigue buscando después de 3 horas',
    case when (select estado from public.envios where id = viejo_app) = 'buscando_repartidor'
         then 'OK' else 'MAL  ' || (select estado from public.envios where id = viejo_app) end);
  insert into _r values ('08 la cadetería del local sí se corta a las 3 horas',
    case when (select estado from public.envios where id = viejo_local) = 'sin_repartidor'
         then 'OK' else 'MAL  ' || (select estado from public.envios where id = viejo_local) end);

  -- ---- Limpieza -------------------------------------------------------------------
  delete from public.ofertas where repartidor_id in (libre, uno, dos)
     or envio_id in (select id from public.envios where comercio_id in (loc_a, loc_b));
  delete from public.envio_eventos where envio_id in (select id from public.envios where comercio_id in (loc_a, loc_b));
  update public.pedidos set envio_id = null where comercio_id in (loc_a, loc_b);
  delete from public.envios where comercio_id in (loc_a, loc_b);
  delete from public.pedidos where comercio_id in (loc_a, loc_b);
  delete from public.repartidores where id in (libre, uno, dos);
  delete from public.comercios where id in (loc_a, loc_b);
  delete from auth.users where id in (u_a, u_b, u_cli, u_libre, u_uno, u_dos);
end $$;

select * from _r order by paso;
