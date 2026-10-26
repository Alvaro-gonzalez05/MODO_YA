-- Un pago que el banco deja en revisión (hallazgos A1 y A3 de la auditoría 2).
--
-- Lo que tiene que pasar:
--   * un cobro en revisión no se le puede volver a pedir al cliente;
--   * si el pedido todavía vive cuando Mercado Pago avisa, se acredita y entra
--     al local;
--   * si el pedido ya se cerró, la plata se devuelve;
--   * un carrito abandonado se sigue cerrando a la media hora, pero un cobro
--     que el banco está mirando espera un día.
--
-- Lo que NO tiene que pasar: que el cliente quede cobrado, sin pedido y sin
-- devolución — que es lo que pasaba antes.
--
-- Los permisos se prueban con `set local role authenticated`: `sql.ps1` corre
-- como `postgres`, que saltea el RLS, y sin eso estas pruebas pasarían siempre.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  u_otro uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; otro uuid; dir uuid; prod uuid; sec uuid;
  vivo  public.pedidos;   -- el que se resuelve bien
  muerto public.pedidos;  -- el que se cierra esperando y hay que devolver
  carrito public.pedidos; -- el abandonado, sin cobro ninguno
  pg public.pagos;
  clave1 text; clave2 text; clave3 text;
  mot text; msj text;
  v text; lo_hecho text; ok boolean; n integer;
  aviso uuid;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','pagos-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','pagos-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','pagos-otro@test.local','x','{"provider":"email"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Pagos Local', 'Pizzeria', '2604000061', 'Roca 610',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;
  insert into public.secciones_menu (comercio_id, nombre) values (com, 'Pizzas') returning id into sec;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec, 'Muzzarella', 10000, true) returning id into prod;

  select id into cli from public.clientes where perfil_id = u_cli;
  select id into otro from public.clientes where perfil_id = u_otro;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 510',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  vivo := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  muerto := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  carrito := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);

  -- ---- A3: la clave del cobro la da la base, no el token --------------------

  select clave, motivo, mensaje into clave1, mot, msj from public.tomar_el_cobro(vivo.id);
  insert into _r values ('01 el primer intento se puede cobrar',
    case when clave1 = 'pedido-' || vivo.id::text || '-1' and mot is null
         then 'OK  clave ' || clave1 else 'MAL  ' || coalesce(clave1, 'sin clave') || ' / ' || coalesce(mot,'-') end);

  select * into pg from public.pagos where id = (select pago_id from public.pedidos where id = vivo.id);
  insert into _r values ('02 el pago nace antes de hablar con Mercado Pago',
    case when pg.estado = 'pendiente' and pg.monto = vivo.total and pg.intentos = 1
         then 'OK  pendiente por $' || pg.monto else 'MAL  ' || coalesce(pg.estado::text, 'sin pago') end);

  -- El banco lo deja en revisión: hay orden, no hay respuesta.
  vivo := public.confirmar_pago_online(vivo.id, 'PAY-REV-1', 'pendiente'::public.estado_pago,
                                       1::smallint, 'El banco está revisando el pago.', 'ORD-REV-1');
  insert into _r values ('03 en revision el pedido no le llega al local',
    case when vivo.estado = 'pendiente_pago' then 'OK  sigue esperando'
         else 'MAL  ' || vivo.estado::text end);

  select clave, motivo, mensaje into clave2, mot, msj from public.tomar_el_cobro(vivo.id);
  insert into _r values ('04 NO se puede cobrar dos veces lo que esta en revision',
    case when clave2 is null and mot = 'en_revision' then 'OK  ' || msj
         else 'VULNERABLE  dio la clave ' || coalesce(clave2, '?') end);

  -- ---- A3: el cliente se entera sin poder leer `pagos` ---------------------

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  begin
    set local role authenticated;
    v := public.estado_del_pago_de_mi_pedido(vivo.id);
    reset role;
  exception when others then reset role; v := 'EXPLOTO'; end;
  insert into _r values ('05 el cliente ve que su pago esta en revision',
    case when v = 'en_revision' then 'OK' else 'MAL  ' || coalesce(v, 'null') end);

  perform set_config('request.jwt.claims', json_build_object('sub', u_otro)::text, true);
  begin
    set local role authenticated;
    v := public.estado_del_pago_de_mi_pedido(vivo.id);
    reset role;
  exception when others then reset role; v := 'EXPLOTO'; end;
  insert into _r values ('06 NO otro cliente ve el pago ajeno',
    case when v is null then 'OK  no devuelve nada' else 'VULNERABLE  ' || v end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- A1: el aviso de Mercado Pago resuelve el pedido vivo ----------------

  lo_hecho := public.resolver_pago_de_mp('ORD-REV-1', 'PAY-REV-1', 'acreditado'::public.estado_pago, null);
  select * into vivo from public.pedidos where id = vivo.id;
  select * into pg from public.pagos where id = vivo.pago_id;
  insert into _r values ('07 aprobado tarde: el pedido entra al local',
    case when vivo.estado = 'pagado' and pg.estado = 'acreditado'
          and pg.acreditado_en is not null and pg.reembolso_pedido_en is null
         then 'OK  ' || lo_hecho
         else 'MAL  pedido=' || vivo.estado::text || ' pago=' || pg.estado::text end);

  insert into _r values ('08 el aviso repetido no hace nada de nuevo',
    case when public.resolver_pago_de_mp('ORD-REV-1', 'PAY-REV-1', 'acreditado'::public.estado_pago, null)
              = 'ya estaba resuelto'
          and (select reembolso_pedido_en from public.pagos where id = vivo.pago_id) is null
         then 'OK  idempotente' else 'MAL  movio algo la segunda vez' end);

  -- ---- A1: el plazo depende de si hay un cobro hecho -----------------------

  perform public.tomar_el_cobro(muerto.id);
  muerto := public.confirmar_pago_online(muerto.id, 'PAY-REV-2', 'pendiente'::public.estado_pago,
                                         1::smallint, null, 'ORD-REV-2');

  -- 45 minutos: antes esto ya lo cancelaba.
  update public.pedidos set creado_en = now() - interval '45 minutes' where id = muerto.id;
  update public.pedidos set creado_en = now() - interval '45 minutes' where id = carrito.id;
  n := public.cerrar_pagos_vencidos();
  select estado::text into v from public.pedidos where id = muerto.id;
  insert into _r values ('09 a los 45 min un cobro en revision NO se cancela',
    case when v = 'pendiente_pago' then 'OK  se le da un dia' else 'MAL  ' || v end);

  select estado::text, motivo_cancelacion into v, msj from public.pedidos where id = carrito.id;
  insert into _r values ('10 a los 45 min el carrito abandonado si se cancela',
    case when v = 'cancelado' and msj = 'El pago no se completó a tiempo'
         then 'OK  ' || msj else 'MAL  ' || v end);

  -- Un día después: ahora sí.
  update public.pedidos set creado_en = now() - interval '2 days' where id = muerto.id;
  perform public.cerrar_pagos_vencidos();
  select estado::text, motivo_cancelacion into v, msj from public.pedidos where id = muerto.id;
  insert into _r values ('11 al dia el cobro sin confirmar cierra el pedido',
    case when v = 'cancelado' and msj = 'El banco no confirmó el pago a tiempo'
         then 'OK  ' || msj else 'MAL  ' || v || ' / ' || coalesce(msj, '-') end);

  -- ---- A1, el corazón: la plata que entra tarde se devuelve ---------------

  lo_hecho := public.resolver_pago_de_mp('ORD-REV-2', 'PAY-REV-2', 'acreditado'::public.estado_pago, null);
  select * into pg from public.pagos where id = muerto.pago_id;
  insert into _r values ('12 cobrado despues de cancelar: se pide la devolucion',
    case when pg.estado = 'acreditado' and pg.reembolso_pedido_en is not null
          and pg.reembolsado_en is null
         then 'OK  ' || lo_hecho else 'MAL  ' || pg.estado::text || ' reembolso=' ||
              coalesce(pg.reembolso_pedido_en::text, 'ninguno') end);

  insert into _r values ('13 el cron de reembolsos lo ve y lo devuelve entero',
    coalesce((select case when monto = muerto.total
                          then format('OK  $%s, el 100%%', monto)
                          else format('MAL  devuelve %s de %s', monto, muerto.total) end
                from public.reembolsos_pendientes() where pago_id = pg.id),
             'MAL  no aparece en reembolsos_pendientes()'));

  -- ---- Un rechazo deja reintentar con otra tarjeta -------------------------

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  carrito := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);

  select clave into clave1 from public.tomar_el_cobro(carrito.id);
  lo_hecho := public.resolver_pago_de_mp(null, null, 'rechazado'::public.estado_pago, 'sin credito');
  -- El aviso sin ids no tiene con qué emparejar: se comprueba aparte.
  insert into _r values ('14 un aviso de un pago que no es nuestro no toca nada',
    case when lo_hecho = 'no corresponde a ningún pago nuestro' then 'OK  ' || lo_hecho
         else 'MAL  ' || lo_hecho end);

  carrito := public.confirmar_pago_online(carrito.id, 'PAY-NO-1', 'rechazado'::public.estado_pago,
                                          1::smallint, 'La tarjeta no tiene fondos.', 'ORD-NO-1');
  select clave, motivo into clave2, mot from public.tomar_el_cobro(carrito.id);
  insert into _r values ('15 despues de un rechazo se puede pagar con otra tarjeta',
    case when clave2 = 'pedido-' || carrito.id::text || '-2' and clave2 <> clave1
         then 'OK  clave nueva ' || clave2
         else 'MAL  ' || coalesce(clave2, 'sin clave') || ' / ' || coalesce(mot, '-') end);

  -- Y el que está en vuelo ahora mismo tampoco se puede duplicar.
  select clave, motivo into clave3, mot from public.tomar_el_cobro(carrito.id);
  insert into _r values ('16 NO dos intentos a la vez sobre el mismo pedido',
    case when clave3 is null and mot = 'en_curso' then 'OK  el segundo espera'
         else 'VULNERABLE  dio ' || coalesce(clave3, '?') end);

  -- ---- El buzón: sin firma válida no se mueve plata ------------------------

  insert into public.mp_notificaciones (tipo, accion, recurso_id, request_id, firma_valida, cuerpo)
  values ('order', 'order.processed', 'ORD-SIN-FIRMA', 'req-pagos-test', false, '{}'::jsonb)
  returning id into aviso;
  insert into _r values ('17 NO un aviso sin firma valida entra a procesarse',
    case when not exists (select 1 from public.mp_avisos_por_procesar() where aviso_id = aviso)
         then 'OK  queda guardado y nada mas' else 'VULNERABLE  lo iba a procesar' end);

  update public.mp_notificaciones set firma_valida = true where id = aviso;
  insert into _r values ('18 con firma valida si entra',
    case when exists (select 1 from public.mp_avisos_por_procesar() where aviso_id = aviso)
         then 'OK' else 'MAL  no lo toma' end);

  perform public.mp_aviso_procesado(aviso, 'probado');
  insert into _r values ('19 tachado deja de aparecer',
    case when not exists (select 1 from public.mp_avisos_por_procesar() where aviso_id = aviso)
          and (select nota from public.mp_notificaciones where id = aviso) = 'probado'
         then 'OK  con la nota a la vista' else 'MAL' end);

  -- ---- Permisos: nada de esto lo puede llamar un cliente -------------------

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ok := false;
  begin
    set local role authenticated;
    perform public.tomar_el_cobro(vivo.id);
    reset role;
  exception when others then reset role; ok := true; end;
  insert into _r values ('20 NO un cliente toma el cobro por su cuenta',
    case when ok then 'OK (rechazado)' else 'VULNERABLE' end);

  ok := false;
  begin
    set local role authenticated;
    perform public.resolver_pago_de_mp('ORD-REV-9', 'PAY-REV-9', 'acreditado'::public.estado_pago, null);
    reset role;
  exception when others then reset role; ok := true; end;
  insert into _r values ('21 NO un cliente se da un pago por acreditado',
    case when ok then 'OK (rechazado)' else 'VULNERABLE' end);

  ok := false;
  begin
    set local role authenticated;
    perform public.mp_aviso_procesado(aviso, 'me lo tacho yo');
    reset role;
  exception when others then reset role; ok := true; end;
  insert into _r values ('22 NO un cliente tacha un aviso',
    case when ok then 'OK (rechazado)' else 'VULNERABLE' end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza ------------------------------------------------------------
  delete from public.mp_notificaciones where id = aviso;
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id in (vivo.id, muerto.id, carrito.id));
  delete from public.pedido_items where pedido_id in (vivo.id, muerto.id, carrito.id);
  delete from public.pedido_eventos where pedido_id in (vivo.id, muerto.id, carrito.id);
  delete from public.cargos_comercio where comercio_id = com;
  update public.pedidos set pago_id = null where id in (vivo.id, muerto.id, carrito.id);
  delete from public.pagos where id in (vivo.pago_id, muerto.pago_id, carrito.pago_id);
  delete from public.pedidos where comercio_id = com;
  delete from public.pagos where mp_order_id in ('ORD-REV-1', 'ORD-REV-2', 'ORD-NO-1');
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id in (cli, otro);
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli, u_otro);
end $$;

select paso, resultado from _r order by paso;
