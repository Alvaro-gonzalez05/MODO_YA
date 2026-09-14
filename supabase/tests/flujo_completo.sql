-- Prueba de extremo a extremo del flujo de un envio.
-- Simula los JWT de cada rol con set_config, igual que hace PostgREST.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_rep uuid := gen_random_uuid();
  u_rep2 uuid := gen_random_uuid();
  ciudad uuid;
  com    uuid;
  rep    uuid;
  rep2   uuid;
  env    public.envios;
  of     public.ofertas;
  cod    text;
  n      int;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  -- Usuarios de auth minimos (los crea normalmente el signup).
  -- El rol va en raw_app_meta_data, como lo pone la Edge Function de alta.
  -- El trigger alta_usuario (0017) crea el perfil a partir de ahi.
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_com,  '00000000-0000-0000-0000-000000000000','authenticated','authenticated','smoke-com@test.local','x','{"rol":"comercio"}','{"nombre":"Smoke Comercio"}',now(),now(),now()),
    (u_rep,  '00000000-0000-0000-0000-000000000000','authenticated','authenticated','smoke-rep@test.local','x','{"rol":"repartidor"}','{"nombre":"Smoke Cadete Cerca"}',now(),now(),now()),
    (u_rep2, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','smoke-rep2@test.local','x','{"rol":"repartidor"}','{"nombre":"Smoke Cadete Lejos"}',now(),now(),now());

  -- Comercio en Av. Roca 420.
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono,
                                calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Pizzeria Smoke', 'Pizzeria', '+54 260 000-0000',
          'Av. Roca 420',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5839,-35.4761),4326)::extensions.geography,
          'aprobado')
  returning id into com;

  -- Un cadete a ~400 m del comercio y otro a ~9 km (fuera del radio de 3 km).
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_rep, ciudad, 'Cadete Cerca','+54 260 111-1111','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800,-35.4755),4326)::extensions.geography, now())
  returning id into rep;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_rep2, ciudad, 'Cadete Lejos','+54 260 222-2222','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.6800,-35.4761),4326)::extensions.geography, now())
  returning id into rep2;

  -- ---- El comercio crea el envio -------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);

  env := public.crear_envio(
    'Av. San Martin 450', -35.4769, -69.5852,
    'Marcela Diaz', '+54 260 456-1122', 'cliente',
    'Porton verde', 'Tocar timbre'
  );
  insert into _r values ('1. crear_envio',
    format('codigo=%s estado=%s distancia=%s km ganancia=$%s comision=$%s total=$%s',
           env.codigo, env.estado, env.distancia_km, env.ganancia_repartidor,
           env.comision, env.total));

  -- El precio no lo manda la app: lo calculo el servidor.
  insert into _r values ('2. precio del servidor',
    case when env.total = 3500 then 'OK  $3.500 (3000+500)'
         else 'MAL  esperaba 3500, dio ' || env.total end);

  -- ---- Confirma y arranca la busqueda --------------------------------------
  env := public.confirmar_envio(env.id);
  insert into _r values ('3. confirmar_envio', 'estado=' || env.estado);

  select * into of from public.ofertas where envio_id = env.id;
  insert into _r values ('4. motor de asignacion',
    case when of.repartidor_id = rep
         then format('OK  ofrecido al mas cercano (%s km), vence en %s s',
                     of.distancia_al_retiro_km,
                     round(extract(epoch from of.expira_en - now())))
         else 'MAL  ofrecio al cadete equivocado' end);

  select count(*) into n from public.ofertas where envio_id = env.id;
  insert into _r values ('5. una sola oferta abierta',
    case when n = 1 then 'OK  ' || n else 'MAL  ' || n end);

  -- ---- El cadete acepta ----------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_rep)::text, true);

  env := public.responder_oferta(of.id, true);
  cod := env.codigo_entrega;
  insert into _r values ('6. responder_oferta',
    format('estado=%s cadete=%s codigo_entrega=%s', env.estado,
           (select nombre from public.repartidores where id = env.repartidor_id), cod));

  insert into _r values ('7. cadete queda ocupado',
    case when (select ocupado from public.repartidores where id = rep)
         then 'OK  no recibe otra oferta' else 'MAL  sigue libre' end);

  -- ---- Avanza los estados --------------------------------------------------
  env := public.avanzar_estado(env.id, 'en_local');
  env := public.avanzar_estado(env.id, 'retirado');
  env := public.avanzar_estado(env.id, 'en_camino');
  insert into _r values ('8. avanzar_estado', 'estado=' || env.estado);

  -- ---- Una transicion invalida tiene que rebotar ---------------------------
  begin
    perform public.avanzar_estado(env.id, 'asignado');
    insert into _r values ('9. transicion invalida', 'MAL  la dejo pasar');
  exception when others then
    insert into _r values ('9. transicion invalida', 'OK  rechazada: ' || left(SQLERRM, 60));
  end;

  -- ---- Codigo de entrega equivocado ----------------------------------------
  begin
    perform public.confirmar_entrega(env.id, '0000');
    insert into _r values ('10. codigo incorrecto', 'MAL  acepto un codigo cualquiera');
  exception when others then
    insert into _r values ('10. codigo incorrecto', 'OK  rechazado');
  end;

  -- ---- Entrega correcta ----------------------------------------------------
  env := public.confirmar_entrega(env.id, cod);
  insert into _r values ('11. confirmar_entrega', 'estado=' || env.estado);

  insert into _r values ('12. cadete liberado',
    case when not (select ocupado from public.repartidores where id = rep)
          and (select viajes_completados from public.repartidores where id = rep) = 1
         then 'OK  libre y +1 viaje' else 'MAL' end);

  -- ---- Auditoria -----------------------------------------------------------
  select count(*) into n from public.envio_eventos where envio_id = env.id;
  insert into _r values ('13. auditoria',
    format('%s eventos: %s', n,
      (select string_agg(estado_nuevo::text,' -> ' order by creado_en)
       from public.envio_eventos where envio_id = env.id)));

  -- ---- Limpieza ------------------------------------------------------------
  perform set_config('request.jwt.claims', null, true);
  -- Orden importa: los envios no se borran en cascada con el comercio (a
  -- proposito), asi que hay que sacarlos primero. Eventos y ofertas si
  -- cuelgan del envio y se van solos.
  delete from public.envios where comercio_id = com;
  delete from public.repartidores where id in (rep, rep2);
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_rep, u_rep2);
end $$;

select paso, resultado from _r order by paso;
