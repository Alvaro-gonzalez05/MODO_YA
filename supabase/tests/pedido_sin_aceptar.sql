-- El pedido que el local no acepta (0076).
--
-- Lo que tiene que pasar:
--   * un pedido pagado hace más de 15 minutos se rechaza solo, se marca la
--     devolución y el local recibe la misma penalidad que si lo rechazaba;
--   * uno pagado hace 5 minutos, uno ya aceptado y uno sin pagar no se tocan;
--   * rechazar con el botón sigue dejando el mismo cargo que antes.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  ciudad uuid; cli uuid; com uuid;
  pct smallint;
  viejo public.pedidos; reciente public.pedidos; aceptado public.pedidos; sin_pagar public.pedidos;
  boton public.pedidos;
  pg_viejo uuid; pg_reciente uuid; pg_aceptado uuid; pg_boton uuid;
  n integer;
  txt text;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  -- La penalidad real, sin tocarla: vencer_pedidos_sin_aceptar() vence todos
  -- los pedidos trabados de la base, y uno de verdad no puede llevarse una
  -- penalidad de prueba.
  pct := coalesce((public.tarifario_vigente(ciudad, 'delivery')).penalidad_rechazo_pct, 50);

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','vence-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','vence-cli@test.local','x','{"provider":"email"}',now(),now(),now());
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Dormido', 'Pizzeria', '2604111010', 'Roca 100',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;
  select id into cli from public.clientes where perfil_id = u_cli;

  -- Cuatro pagos acreditados y cinco pedidos.
  insert into public.pagos (metodo, estado, monto, referencia_externa, acreditado_en)
  values ('tarjeta', 'acreditado', 10000, 'vence-1', now()) returning id into pg_viejo;
  insert into public.pagos (metodo, estado, monto, referencia_externa, acreditado_en)
  values ('tarjeta', 'acreditado', 10000, 'vence-2', now()) returning id into pg_reciente;
  insert into public.pagos (metodo, estado, monto, referencia_externa, acreditado_en)
  values ('tarjeta', 'acreditado', 10000, 'vence-3', now()) returning id into pg_aceptado;
  insert into public.pagos (metodo, estado, monto, referencia_externa, acreditado_en)
  values ('tarjeta', 'acreditado', 10000, 'vence-4', now()) returning id into pg_boton;

  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago, pago_id, pagado_en)
  values (ciudad, cli, com, 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          10000, 0, 'pagado', 'tarjeta', pg_viejo, now() - interval '20 minutes')
  returning * into viejo;
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago, pago_id, pagado_en)
  values (ciudad, cli, com, 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          10000, 0, 'pagado', 'tarjeta', pg_reciente, now() - interval '5 minutes')
  returning * into reciente;
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago, pago_id, pagado_en)
  values (ciudad, cli, com, 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          10000, 0, 'aceptado', 'tarjeta', pg_aceptado, now() - interval '40 minutes')
  returning * into aceptado;
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago)
  values (ciudad, cli, com, 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          10000, 0, 'pendiente_pago', 'tarjeta')
  returning * into sin_pagar;
  update public.pedidos set creado_en = now() - interval '40 minutes' where id = sin_pagar.id;

  -- ---- El vencimiento ----------------------------------------------------------
  n := public.vencer_pedidos_sin_aceptar();
  select * into viejo from public.pedidos where id = viejo.id;

  insert into _r values ('01 el pagado hace 20 minutos se rechaza solo',
    case when viejo.estado = 'rechazado' and viejo.motivo_rechazo like 'El local no respondi%'
         then 'OK' else format('MAL  %s / %s', viejo.estado, viejo.motivo_rechazo) end);

  insert into _r values ('02 y se marca para devolverle la plata al cliente',
    case when (select reembolso_pedido_en from public.pagos where id = pg_viejo) is not null
         then 'OK' else 'MAL  sin reembolso_pedido_en' end);

  select string_agg(detalle || ' = ' || monto, ' | ') into txt
    from public.cargos_comercio where pedido_id = viejo.id;
  insert into _r values ('03 el local recibe la misma penalidad que si lo rechazaba',
    case when txt = format('Penalidad por no responder el pedido %s (%s%% de $10.000) = %s', viejo.codigo, pct, round(10000 * pct / 100.0))
         then 'OK  ' || txt else 'MAL  ' || coalesce(txt, 'sin cargo') end);

  insert into _r values ('04 el pagado hace 5 minutos sigue esperando',
    case when (select estado from public.pedidos where id = reciente.id) = 'pagado'
          and (select reembolso_pedido_en from public.pagos where id = pg_reciente) is null
         then 'OK' else 'MAL' end);

  insert into _r values ('05 el ya aceptado y el sin pagar no se tocan',
    case when (select estado from public.pedidos where id = aceptado.id) = 'aceptado'
          and (select estado from public.pedidos where id = sin_pagar.id) = 'pendiente_pago'
         then 'OK' else 'MAL' end);

  -- `n` no se compara con 1: la base puede tener otro pedido trabado de verdad,
  -- y vencerlo también es lo correcto.
  insert into _r values ('06 una segunda pasada no vuelve a cobrar ni a vencer',
    case when n >= 1 and public.vencer_pedidos_sin_aceptar() = 0
          and (select count(*) from public.cargos_comercio where pedido_id = viejo.id) = 1
         then 'OK' else format('MAL  vencio %s', n) end);

  -- ---- El botón de rechazar sigue igual ------------------------------------------
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, entrega_calle, entrega_ubicacion,
                              subtotal, costo_envio, estado, metodo_pago, pago_id, pagado_en)
  values (ciudad, cli, com, 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography,
          20000, 0, 'pagado', 'tarjeta', pg_boton, now())
  returning * into boton;

  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  boton := public.rechazar_pedido(boton.id, 'Nos quedamos sin muzzarella');
  perform set_config('request.jwt.claims', null, true);

  select string_agg(detalle || ' = ' || monto, ' | ') into txt
    from public.cargos_comercio where pedido_id = boton.id;
  insert into _r values ('07 rechazar con el botón deja el cargo de siempre',
    case when boton.estado = 'rechazado'
          and txt = format('Penalidad por rechazar el pedido %s (%s%% de $20.000) = %s', boton.codigo, pct, round(20000 * pct / 100.0))
          and (select reembolso_pedido_en from public.pagos where id = pg_boton) is not null
         then 'OK  ' || txt else 'MAL  ' || coalesce(txt, 'sin cargo') end);

  insert into _r values ('09 el porcentaje se lee bien con y sin decimales',
    case when public.pct_legible(50) = '50%' and public.pct_legible(10.00) = '10%'
          and public.pct_legible(8.50) = '8,5%' and public.pct_legible(100) = '100%'
         then 'OK' else format('MAL  %s / %s / %s / %s', public.pct_legible(50), public.pct_legible(10.00),
                               public.pct_legible(8.50), public.pct_legible(100)) end);

  insert into _r values ('08 el cron está programado',
    case when exists (select 1 from cron.job where jobname = 'vencer-pedidos-sin-aceptar' and schedule = '* * * * *')
         then 'OK' else 'MAL' end);

  -- ---- Limpieza -------------------------------------------------------------------
  delete from public.cargos_comercio where comercio_id = com;
  delete from public.pedidos where comercio_id = com;
  delete from public.pagos where id in (pg_viejo, pg_reciente, pg_aceptado, pg_boton);
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli);
end $$;

select * from _r order by paso;
