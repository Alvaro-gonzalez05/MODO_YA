-- El rider que cerró la app (0078).
--
-- Lo que tiene que pasar:
--   * la oferta no le llega a un rider "conectado" cuya última posición es de
--     hace dos horas, y sí al que mandó la suya recién;
--   * el que lleva 30 minutos sin señales se desconecta solo, salvo que esté
--     llevando un envío;
--   * el proceso está programado.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_fresco uuid := gen_random_uuid(); u_viejo uuid := gen_random_uuid(); u_viaje uuid := gen_random_uuid();
  ciudad uuid; tarifa uuid; loc uuid;
  fresco uuid; viejo uuid; viaje uuid;
  pto constant extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography;
  casa constant extensions.geography := extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography;
  nuevo uuid;
  orden uuid[];
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  tarifa := (public.tarifario_vigente(ciudad, 'delivery')).id;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','senal-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_fresco,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','senal-fresco@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_viejo,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','senal-viejo@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_viaje,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','senal-viaje@test.local','x','{"rol":"repartidor"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Señal', 'Pizzeria', '2604111013', 'Roca 100', pto, 'aprobado') returning id into loc;

  -- El viejo está en la puerta del local; el fresco, a unas cuadras. Si la
  -- posición vieja contara, el viejo saldría primero por cercanía.
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion, conectado,
                                   ultima_ubicacion, ultima_ubicacion_en)
  values (u_fresco, ciudad, 'Fresco', '2604333001', 'moto', 'aprobado', true, casa, now()) returning id into fresco;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion, conectado,
                                   ultima_ubicacion, ultima_ubicacion_en)
  values (u_viejo, ciudad, 'Viejo', '2604333002', 'moto', 'aprobado', true, pto, now() - interval '2 hours') returning id into viejo;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion, conectado,
                                   ultima_ubicacion, ultima_ubicacion_en)
  values (u_viaje, ciudad, 'De viaje', '2604333003', 'moto', 'aprobado', true, pto, now() - interval '2 hours') returning id into viaje;

  -- "De viaje" lleva un envío en camino.
  insert into public.envios (ciudad_id, comercio_id, origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
                             cliente_nombre, cliente_telefono, tarifario_id, distancia_km, ganancia_repartidor,
                             comision, paga, estado, repartidor_id)
  values (ciudad, loc, 'Roca 100', pto, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
          'comercio', 'en_camino', viaje);
  update public.repartidores set ocupado = true where id = viaje;

  -- ---- La oferta ---------------------------------------------------------------
  insert into public.envios (ciudad_id, comercio_id, origen_calle, origen_ubicacion, destino_calle, destino_ubicacion,
                             cliente_nombre, cliente_telefono, tarifario_id, distancia_km, ganancia_repartidor,
                             comision, paga, estado)
  values (ciudad, loc, 'Roca 100', pto, 'San Martin 500', casa, 'Cliente', '2604', tarifa, 1, 2000, 500,
          'comercio', 'buscando_repartidor')
  returning id into nuevo;

  select array_agg(c.rid order by c.ord) into orden
    from public.repartidores_cercanos(nuevo) with ordinality as c(rid, km, ord)
   where c.rid in (fresco, viejo, viaje);

  insert into _r values ('01 al que no da señales hace dos horas no le llega la oferta',
    case when not (viejo = any(coalesce(orden, '{}'))) then 'OK' else 'MAL  le ofrece al viejo' end);
  insert into _r values ('02 al que mandó su posición recién, sí',
    case when orden[1] = fresco then 'OK' else 'MAL  orden ' || coalesce(array_to_string(orden, ','), '-') end);

  -- ---- La desconexión --------------------------------------------------------------
  perform public.desconectar_riders_sin_senal();

  insert into _r values ('03 el que no da señales queda desconectado',
    case when not (select conectado from public.repartidores where id = viejo) then 'OK' else 'MAL  sigue conectado' end);
  insert into _r values ('04 el que está llevando un envío sigue conectado',
    case when (select conectado from public.repartidores where id = viaje) then 'OK' else 'MAL  lo desconecto en pleno viaje' end);
  insert into _r values ('05 el que da señales sigue conectado',
    case when (select conectado from public.repartidores where id = fresco) then 'OK' else 'MAL' end);
  insert into _r values ('06 el proceso está programado cada 5 minutos',
    case when exists (select 1 from cron.job where jobname = 'desconectar-riders-sin-senal' and schedule = '*/5 * * * *')
         then 'OK' else 'MAL' end);

  -- ---- Limpieza -------------------------------------------------------------------
  delete from public.ofertas where envio_id in (select id from public.envios where comercio_id = loc)
     or repartidor_id in (fresco, viejo, viaje);
  delete from public.envio_eventos where envio_id in (select id from public.envios where comercio_id = loc);
  delete from public.envios where comercio_id = loc;
  delete from public.repartidores where id in (fresco, viejo, viaje);
  delete from public.comercios where id = loc;
  delete from auth.users where id in (u_com, u_fresco, u_viejo, u_viaje);
end $$;

select * from _r order by paso;
