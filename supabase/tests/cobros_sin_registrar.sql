-- Qué pedidos tiene que listar "Cobros sin registrar" de la administración.
--
-- La pantalla filtraba por `pago_estado = 'pendiente'`, que antes de 0058
-- (solo tarjeta) significaba "falta cobrar". Hoy significa otra cosa: **el
-- cliente está cargando la tarjeta ahora mismo**. Así, cada pedido nuevo le
-- aparecía a la administración como cobro pendiente, y marcarlo cobrado en
-- efectivo le hacía salir al rider a cobrar en la puerta un pedido que el
-- cliente quizá ya pagó.
--
-- Esto compara el filtro viejo con el nuevo sobre los mismos pedidos. No toca
-- nada de la pasarela: solo mide a quién mira la consulta.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; dir uuid; sec uuid; prod uuid;
  ped public.pedidos;
  n_viejo integer;
  n_nuevo integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','cobro-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','cobro-cli@test.local','x','{"provider":"email"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Cobro Local', 'Pizzeria', '2604000092', 'Roca 980',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;
  insert into public.secciones_menu (comercio_id, nombre) values (com, 'Pizzas') returning id into sec;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec, 'Muzzarella', 10000, true) returning id into prod;

  select id into cli from public.clientes where perfil_id = u_cli;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 580',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  -- ---- Un pedido nuevo: el cliente esta cargando la tarjeta ----------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('01 un pedido nuevo nace esperando el pago',
    (select case when estado = 'pendiente_pago' and pago_estado = 'pendiente'
                 then 'OK  pago en curso'
                 else format('MAL  %s / %s', estado, pago_estado) end
       from public.v_pedidos where id = ped.id));

  -- El filtro viejo de la pantalla.
  select count(*) into n_viejo from public.v_pedidos
   where comercio_id = com
     and pago_estado = 'pendiente'
     and estado not in ('cancelado','rechazado');

  -- El nuevo.
  select count(*) into n_nuevo from public.v_pedidos
   where comercio_id = com
     and pago_estado = 'pendiente'
     and estado not in ('cancelado','rechazado','pendiente_pago');

  insert into _r values ('02 el filtro viejo lo listaba como cobro pendiente',
    case when n_viejo = 1 then 'OK  era el error: invitaba a cobrarlo de nuevo'
         else format('MAL  listaba %s', n_viejo) end);

  insert into _r values ('03 el filtro nuevo no lo lista',
    case when n_nuevo = 0 then 'OK  nadie lo marca cobrado por error'
         else format('MAL  listaba %s', n_nuevo) end);

  -- ---- Pagado con tarjeta: no le queda nada por registrar -------------------
  ped := public.confirmar_pago_online(ped.id, 'PAY-COBRO', 'acreditado'::public.estado_pago,
    1::smallint, null, 'simulado-orden-cobro');

  select count(*) into n_nuevo from public.v_pedidos
   where comercio_id = com
     and pago_estado = 'pendiente'
     and estado not in ('cancelado','rechazado','pendiente_pago');

  insert into _r values ('04 acreditado no aparece en ningun filtro',
    case when n_nuevo = 0 then 'OK' else format('MAL  listaba %s', n_nuevo) end);

  -- ---- Un cobro que si quedo colgado ---------------------------------------
  -- Como los de antes de 0058, o uno al que le fallo la acreditacion: el
  -- pedido ya esta en la cocina y la plata nunca se registro. Ese es el unico
  -- que la pantalla tiene que mostrar.
  update public.pagos set estado = 'pendiente', acreditado_en = null where id = ped.pago_id;

  select count(*) into n_nuevo from public.v_pedidos
   where comercio_id = com
     and pago_estado = 'pendiente'
     and estado not in ('cancelado','rechazado','pendiente_pago');

  insert into _r values ('05 el cobro viejo colgado si se lista',
    case when n_nuevo = 1 then 'OK  es para lo que sirve la pantalla'
         else format('MAL  listaba %s', n_nuevo) end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.envio_eventos where envio_id in (select id from public.envios where comercio_id = com);
  delete from public.ofertas where envio_id in (select id from public.envios where comercio_id = com);
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id = ped.id);
  delete from public.pedido_items where pedido_id = ped.id;
  delete from public.pedido_eventos where pedido_id = ped.id;
  update public.pedidos set pago_id = null, envio_id = null where id = ped.id;
  delete from public.pagos where id = ped.pago_id;
  delete from public.envios where comercio_id = com;
  delete from public.pedidos where id = ped.id;
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli);
end $$;

select paso, resultado from _r order by paso;
