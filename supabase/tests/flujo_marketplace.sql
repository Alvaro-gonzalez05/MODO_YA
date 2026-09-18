-- Prueba de extremo a extremo del flujo de marketplace.
--
-- Cliente arma un pedido con opciones y elige como paga -> le llega al comercio
-- sin esperar a nadie -> lo acepta y se genera el envio -> lo prepara -> sale
-- el cadete (con reoferta si alguno dice que no) -> entrega. La
-- administracion registra el cobro aparte.
-- Verifica sobre todo que los precios los ponga el servidor y que el estado del
-- pedido siga al del envio sin que nadie lo sincronice a mano.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli uuid := gen_random_uuid();
  u_com uuid := gen_random_uuid();
  u_rep uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  ciudad uuid;
  cli uuid; com uuid; rep uuid; dir uuid;
  seccion uuid; prod uuid; op uuid; it_grande uuid; it_queso uuid;
  ped public.pedidos;
  env public.envios;
  of  public.ofertas;
  of2 public.ofertas;
  pago_id uuid;
  cod text;
  esperado integer;
  envio_esperado integer;
  n_ped int; n_items int; n_env int; n_dir int;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  -- El cliente se registra "solo": sin rol en app_metadata cae en cliente y el
  -- trigger le crea perfil y fila en `clientes`. El resto trae rol, como lo
  -- pondria la Edge Function de alta.
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','mk-cli@test.local','x','{"provider":"email"}','{"nombre":"Marcela Diaz","telefono":"+54 260 456-1122"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','mk-com@test.local','x','{"rol":"comercio"}','{"nombre":"MK Comercio"}',now(),now(),now()),
    (u_rep,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','mk-rep@test.local','x','{"rol":"repartidor"}','{"nombre":"MK Cadete"}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','mk-adm@test.local','x','{"rol":"admin"}','{"nombre":"MK Admin"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono,
                                calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Pizzeria MK','Pizzeria','+54 260 000-0000','Av. Roca 420',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5839,-35.4761),4326)::extensions.geography,
          'aprobado')
  returning id into com;

  -- Abierto todos los dias, para que comercio_abierto() no dependa de la hora.
  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0,6) d;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_rep, ciudad, 'MK Cadete','+54 260 111-1111','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800,-35.4755),4326)::extensions.geography, now())
  returning id into rep;

  -- La fila de cliente ya la creo el trigger de alta.
  select id into cli from public.clientes where perfil_id = u_cli;

  insert into public.direcciones_cliente (cliente_id, alias, calle, referencia, ubicacion, predeterminada)
  values (cli,'Casa','Av. San Martin 450','Porton verde',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5852,-35.4769),4326)::extensions.geography, true)
  returning id into dir;

  -- Catalogo: una pizza de $8.000 con tamano grande (+$2.000) y extra queso (+$900).
  insert into public.secciones_menu (comercio_id, nombre) values (com,'Pizzas')
  returning id into seccion;

  insert into public.productos (comercio_id, seccion_id, nombre, precio)
  values (com, seccion, 'Muzzarella', 8000) returning id into prod;

  insert into public.opciones_producto (producto_id, nombre, tipo, obligatoria)
  values (prod, 'Tamano', 'unica', true) returning id into op;

  insert into public.opcion_items (opcion_id, nombre, precio_extra)
  values (op, 'Grande', 2000) returning id into it_grande;

  insert into public.opciones_producto (producto_id, nombre, tipo)
  values (prod, 'Agregados', 'multiple') returning id into op;

  insert into public.opcion_items (opcion_id, nombre, precio_extra)
  values (op, 'Extra queso', 900) returning id into it_queso;

  -- ---- El cliente arma el pedido -------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);

  ped := public.crear_pedido(
    com, dir,
    jsonb_build_array(
      jsonb_build_object(
        'producto_id', prod, 'cantidad', 2, 'nota', 'bien cocida',
        'opciones', jsonb_build_array(it_grande, it_queso)
      )
    ),
    'Tocar timbre',
    'efectivo'
  );
  pago_id := ped.pago_id;

  -- (8000 + 2000 + 900) x 2 = 21800 de productos, + el envio que cotiza el
  -- tarifario vigente (lo cambia la administracion, no se fija en la prueba).
  esperado := (8000 + 2000 + 900) * 2;
  select total into envio_esperado from public.cotizar(
    ciudad,
    (select ubicacion from public.comercios where id = com),
    (select ubicacion from public.direcciones_cliente where id = dir));
  insert into _r values ('1. crear_pedido',
    format('codigo=%s estado=%s subtotal=$%s envio=$%s total=$%s',
           ped.codigo, ped.estado, ped.subtotal, ped.costo_envio, ped.total));
  insert into _r values ('2. precio del servidor',
    case when ped.subtotal = esperado and ped.costo_envio = envio_esperado
         then format('OK  $%s productos + $%s envio', esperado, envio_esperado)
         else format('MAL  esperaba %s + %s, dio %s + %s',
                     esperado, envio_esperado, ped.subtotal, ped.costo_envio) end);

  insert into _r values ('3. opciones copiadas',
    (select format('%s renglon, %s opciones: %s',
              count(distinct pi.id), count(o.id),
              string_agg(o.nombre_opcion || '=' || o.nombre_item, ', '))
     from public.pedido_items pi
     left join public.pedido_item_opciones o on o.pedido_item_id = pi.id
     where pi.pedido_id = ped.id));

  -- ---- RLS de verdad --------------------------------------------------------
  --
  -- Ojo: estas comprobaciones SOLO valen con `set local role authenticated`.
  -- El dueno de la tabla (postgres, que es con quien corre este script) saltea
  -- RLS por completo, asi que sin cambiar de rol el test pasaria siempre.
  begin
    set local role authenticated;
    update public.pedidos set subtotal = 1 where id = ped.id;
    reset role;
    -- Sin politica de UPDATE para el cliente, el update no explota: afecta 0
    -- filas. Hay que mirar el dato, no la ausencia de excepcion.
    insert into _r values ('4. cliente no toca precios',
      case when (select subtotal from public.pedidos where id = ped.id) = esperado
           then 'OK  RLS lo dejo sin efecto'
           else 'MAL  pudo modificarlo' end);
  exception when others then
    reset role;
    insert into _r values ('4. cliente no toca precios', 'OK  RLS lo bloqueo');
  end;

  -- ---- Le llega al local sin esperar a la administracion -------------------
  insert into _r values ('5. directo al local',
    case when ped.estado = 'pagado' and ped.metodo_pago = 'efectivo'
          and (select estado from public.pagos where id = pago_id) = 'pendiente'
         then 'OK  nace "Nuevo" con el cobro pendiente'
         else format('MAL  estado=%s metodo=%s', ped.estado, ped.metodo_pago) end);

  -- ---- La administracion registra el cobro: no mueve el pedido -------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_adm)::text, true);
  ped := public.marcar_pedido_pagado(ped.id, 'efectivo', 'TEST-REF-1');
  insert into _r values ('5b. cobro registrado',
    case when ped.estado = 'pagado'
          and (select estado from public.pagos where id = pago_id) = 'acreditado'
         then 'OK  pago acreditado, el pedido sigue igual'
         else 'MAL  estado=' || ped.estado end);

  -- ---- El comercio lo acepta: nace el envio --------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  ped := public.aceptar_pedido(ped.id);
  select * into env from public.envios where id = ped.envio_id;
  insert into _r values ('6. aceptar_pedido',
    format('pedido=%s envio=%s estado_envio=%s', ped.estado, env.codigo, env.estado));

  insert into _r values ('6b. rider cobra el efectivo',
    case when env.cobrar_al_entregar = ped.total and env.cobro_metodo = 'efectivo'
         then format('OK  el envio dice cobrar $%s en efectivo', ped.total)
         else format('MAL  cobrar=%s metodo=%s', env.cobrar_al_entregar, env.cobro_metodo) end);

  insert into _r values ('7. cotizacion congelada',
    case when env.ganancia_repartidor = ped.envio_ganancia_repartidor
          and env.comision = ped.envio_comision
          and env.total = ped.costo_envio
         then format('OK  el envio hereda los $%s que ya pago el cliente', ped.costo_envio)
         else 'MAL  el envio se recotizo' end);

  -- ---- Lo prepara. Al marcarlo listo se sale a buscar cadete ---------------
  ped := public.avanzar_pedido(ped.id, 'en_preparacion');
  ped := public.avanzar_pedido(ped.id, 'listo');
  select * into env from public.envios where id = ped.envio_id;
  insert into _r values ('8. listo dispara la busqueda',
    case when env.estado = 'buscando_repartidor'
         then 'OK  el envio salio a buscar cadete recien al estar listo'
         else 'MAL  estado_envio=' || env.estado end);

  -- ---- El cadete dice que no: se le vuelve a ofrecer ----------------------
  -- Con un solo rider cerca, antes el envio quedaba sin nadie para siempre.
  select * into of from public.ofertas where envio_id = env.id and respuesta is null;
  perform set_config('request.jwt.claims', json_build_object('sub',u_rep)::text, true);
  perform public.responder_oferta(of.id, false);
  -- Pasa el minuto de espera y se reintenta, como hace el cron cada 10 s. Se
  -- llama solo para este envio: vencer_ofertas() recorre todos los de la base
  -- y podria ofrecerle al cadete de prueba un envio real que este buscando.
  update public.ofertas set ofrecida_en = now() - interval '2 minutes' where id = of.id;
  perform public.ofrecer_al_siguiente(env.id);
  select * into of2 from public.ofertas where envio_id = env.id and respuesta is null;
  select * into env from public.envios where id = env.id;
  insert into _r values ('8b. reoferta tras un no',
    case when of2.id is not null and of2.repartidor_id = rep and env.estado = 'buscando_repartidor'
         then 'OK  se le volvio a ofrecer y el envio sigue buscando'
         else format('MAL  oferta=%s envio=%s', of2.id, env.estado) end);

  -- ---- El cadete acepta y entrega ------------------------------------------
  env := public.responder_oferta(of2.id, true);
  cod := env.codigo_entrega;

  env := public.avanzar_estado(env.id, 'en_local');
  env := public.avanzar_estado(env.id, 'retirado');

  select * into ped from public.pedidos where id = ped.id;
  insert into _r values ('9. retirado arrastra al pedido',
    case when ped.estado = 'en_camino'
         then 'OK  el pedido paso solo a en_camino'
         else 'MAL  pedido=' || ped.estado end);

  env := public.avanzar_estado(env.id, 'en_camino');
  env := public.confirmar_entrega(env.id, cod);

  select * into ped from public.pedidos where id = ped.id;
  insert into _r values ('10. entrega cierra el pedido',
    case when ped.estado = 'entregado' and env.estado = 'entregado'
         then 'OK  pedido y envio entregados'
         else format('MAL  pedido=%s envio=%s', ped.estado, env.estado) end);

  insert into _r values ('11. auditoria del pedido',
    (select string_agg(estado_nuevo::text, ' -> ' order by creado_en)
     from public.pedido_eventos where pedido_id = ped.id));

  -- ---- Privacidad: el cadete no ve el pedido -------------------------------
  --
  -- El documento pide no exponer datos del cliente mas alla de lo necesario
  -- para completar el envio. Que productos pidio y cuanto pago no le hace falta
  -- al cadete, asi que `pedidos` no le tiene que devolver ni una fila.
  -- Se miden los conteos dentro del rol y se escriben despues: la tabla
  -- temporal es de postgres y `authenticated` no puede insertar en ella.
  perform set_config('request.jwt.claims', json_build_object('sub',u_rep)::text, true);
  set local role authenticated;
  select count(*) into n_ped   from public.pedidos where id = ped.id;
  select count(*) into n_items from public.pedido_items where pedido_id = ped.id;
  select count(*) into n_env   from public.envios where id = env.id;
  reset role;

  insert into _r values ('12. cadete no ve pedidos',
    case when n_ped = 0 then 'OK  0 filas' else 'MAL  el cadete ve el pedido' end);
  insert into _r values ('13. cadete no ve renglones',
    case when n_items = 0 then 'OK  0 filas' else 'MAL  ve que productos pidio' end);
  -- En cambio el envio que hizo si lo ve: es su trabajo.
  insert into _r values ('14. cadete si ve su envio',
    case when n_env = 1 then 'OK  1 fila' else 'MAL  no ve su propio envio' end);

  -- ---- Privacidad: la libreta de direcciones es del cliente ----------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  set local role authenticated;
  select count(*) into n_dir from public.direcciones_cliente where cliente_id = cli;
  reset role;

  insert into _r values ('15. comercio no ve direcciones',
    case when n_dir = 0 then 'OK  0 filas' else 'MAL  ve la libreta del cliente' end);

  -- ---- Limpieza ------------------------------------------------------------
  perform set_config('request.jwt.claims', null, true);
  update public.pedidos set envio_id = null where id = ped.id;
  delete from public.envios   where pedido_id = ped.id;
  delete from public.pedidos  where id = ped.id;
  delete from public.pagos    where id = pago_id;
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.repartidores where id = rep;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_cli, u_com, u_rep, u_adm);
end $$;

select paso, resultado from _r order by length(paso), paso;
