-- Promociones del local: descuentos sobre el menú.
--
-- Arma un local con dos secciones y revisa qué precio ve el cliente y, sobre
-- todo, qué precio termina cobrando `crear_pedido` (que es el único que vale).

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; dir uuid;
  sec_pizzas uuid; sec_bebidas uuid;
  muzza uuid; coca uuid;
  opcion uuid; agregado uuid;
  promo uuid; promo2 uuid;
  ped public.pedidos;
  ped2 public.pedidos;
  hoy smallint;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';
  hoy := extract(dow from now() at time zone 'America/Argentina/Mendoza')::smallint;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','promo-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','promo-cli@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','promo-adm@test.local','x','{"rol":"admin"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Promo Local', 'Pizzeria', '2604000020', 'Roca 200',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;

  insert into public.secciones_menu (comercio_id, nombre, orden) values (com, 'Pizzas', 1) returning id into sec_pizzas;
  insert into public.secciones_menu (comercio_id, nombre, orden) values (com, 'Bebidas', 2) returning id into sec_bebidas;

  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec_pizzas, 'Muzzarella', 10000, true) returning id into muzza;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec_bebidas, 'Coca 1.5', 3000, true) returning id into coca;

  insert into public.opciones_producto (producto_id, nombre, tipo, obligatoria)
  values (muzza, 'Agregados', 'multiple', false) returning id into opcion;
  insert into public.opcion_items (opcion_id, nombre, precio_extra)
  values (opcion, 'Jamon', 2000) returning id into agregado;

  select id into cli from public.clientes where perfil_id = u_cli;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 500',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  -- ---- Sin promociones -------------------------------------------------------
  insert into _r values ('01 sin promo, precio de lista',
    case when not exists (select 1 from public.promociones_del_local(com))
         then 'OK  no hay nada con descuento' else 'MAL  aparecio una promo' end);

  -- ---- Todo el menú ----------------------------------------------------------
  insert into public.promociones (comercio_id, nombre, porcentaje, alcance)
  values (com, '20% en todo', 20, 'todo') returning id into promo;

  insert into _r values ('02 promo en todo el menu',
    (select case when count(*) = 2
                  and max(case when producto_id = muzza then precio end) = 8000
                  and max(case when producto_id = coca then precio end) = 2400
                 then 'OK  muzza $8.000 y coca $2.400'
                 else format('MAL  %s filas', count(*)) end
       from public.promociones_del_local(com)));

  -- ---- Lo que realmente se cobra ---------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', muzza, 'cantidad', 2)), null, 'efectivo');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('03 el pedido cobra el precio con descuento',
    (select case when i.precio_unitario = 8000 and i.precio_lista = 10000
                  and i.subtotal = 16000 and i.promocion_id = promo and ped.subtotal = 16000
                 then 'OK  $8.000 c/u, guarda que valia $10.000'
                 else format('MAL  unitario=%s lista=%s subtotal=%s', i.precio_unitario, i.precio_lista, i.subtotal) end
       from public.pedido_items i where i.pedido_id = ped.id));

  -- ---- El descuento no toca los agregados ------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped2 := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object(
      'producto_id', muzza, 'cantidad', 1,
      'opciones', jsonb_build_array(agregado))), null, 'efectivo');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('04 el agregado se cobra entero',
    case when ped2.subtotal = 10000 then 'OK  $8.000 la pizza + $2.000 el jamon'
         else format('MAL  subtotal=%s', ped2.subtotal) end);

  -- ---- Solo algunas secciones ------------------------------------------------
  update public.promociones set alcance = 'secciones' where id = promo;
  insert into public.promocion_secciones (promocion_id, seccion_id) values (promo, sec_pizzas);

  insert into _r values ('05 alcance por seccion',
    (select case when count(*) = 1 and bool_and(producto_id = muzza)
                 then 'OK  descuenta las pizzas, no las bebidas'
                 else format('MAL  %s filas', count(*)) end
       from public.promociones_del_local(com)));

  -- ---- Productos sueltos -----------------------------------------------------
  update public.promociones set alcance = 'productos' where id = promo;
  insert into public.promocion_productos (promocion_id, producto_id) values (promo, coca);

  insert into _r values ('06 alcance por producto',
    (select case when count(*) = 1 and bool_and(producto_id = coca) and min(precio) = 2400
                 then 'OK  solo la coca a $2.400'
                 else format('MAL  %s filas', count(*)) end
       from public.promociones_del_local(com)));

  -- ---- Solo ciertos dias -----------------------------------------------------
  update public.promociones
     set alcance = 'todo', dias = array[(hoy + 3) % 7]::smallint[]
   where id = promo;

  insert into _r values ('07 otro dia de la semana no rige',
    case when not public.promocion_vigente(promo)
          and not exists (select 1 from public.promociones_del_local(com))
         then 'OK  la promo es de otro dia' else 'MAL  rigio igual' end);

  update public.promociones set dias = array[hoy]::smallint[] where id = promo;
  insert into _r values ('08 el dia que toca si rige',
    case when public.promocion_vigente(promo) then 'OK  hoy si' else 'MAL' end);

  -- ---- Vencida y pausada -----------------------------------------------------
  update public.promociones
     set dias = '{}', desde = current_date - 3, hasta = current_date - 1
   where id = promo;
  insert into _r values ('09 vencida no rige',
    case when not public.promocion_vigente(promo) then 'OK  se termino ayer' else 'MAL' end);

  update public.promociones set hasta = null, activa = false where id = promo;
  insert into _r values ('10 pausada no rige',
    case when not public.promocion_vigente(promo) then 'OK  esta pausada' else 'MAL' end);

  -- ---- Si hay dos, gana la que mas descuenta ---------------------------------
  update public.promociones set activa = true where id = promo;
  insert into public.promociones (comercio_id, nombre, porcentaje, alcance)
  values (com, 'Martes de pizza 35%', 35, 'secciones') returning id into promo2;
  insert into public.promocion_secciones (promocion_id, seccion_id) values (promo2, sec_pizzas);

  insert into _r values ('11 gana la que mas descuenta',
    (select case when precio = 6500 and porcentaje = 35
                 then 'OK  la muzza queda a $6.500 (35%)'
                 else format('MAL  precio=%s pct=%s', precio, porcentaje) end
       from public.promociones_del_local(com) where producto_id = muzza));

  -- ---- La vidriera -----------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  insert into _r values ('12 la vidriera muestra el descuento',
    (select case when v.descuento = 35 then 'OK  "35% OFF" en la tarjeta del local'
                 else format('MAL  descuento=%s', v.descuento) end
       from public.v_comercios v where v.id = com));
  perform set_config('request.jwt.claims', null, true);

  -- ---- La liquidación cuenta lo que se vendió de verdad -----------------------
  update public.pedidos set estado = 'aceptado' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'en_preparacion' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'listo' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'en_camino' where id in (ped.id, ped2.id);
  update public.pedidos set estado = 'entregado', entregado_en = now() where id in (ped.id, ped2.id);
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  insert into _r values ('13 la liquidacion usa el precio con descuento',
    (select case when ventas = 26000
                 then 'OK  vendio $26.000, no $32.000'
                 else format('MAL  ventas=%s', ventas) end
       from public.pendiente_de_liquidar_comercios(current_date - 1, current_date)
      where comercio_id = com));
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id in (ped.id, ped2.id));
  delete from public.pedido_items where pedido_id in (ped.id, ped2.id);
  delete from public.pedido_eventos where pedido_id in (ped.id, ped2.id);
  update public.pedidos set pago_id = null where id in (ped.id, ped2.id);
  delete from public.pagos where id in (ped.pago_id, ped2.pago_id);
  delete from public.pedidos where id in (ped.id, ped2.id);
  delete from public.promociones where comercio_id = com;
  delete from public.opcion_items where opcion_id = opcion;
  delete from public.opciones_producto where producto_id = muzza;
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli, u_adm);
end $$;

select paso, resultado from _r order by paso;
