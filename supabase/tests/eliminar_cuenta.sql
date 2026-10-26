-- El cliente elimina su cuenta (0073).
--
-- Se borra lo que lo identifica y se conserva lo que es plata de otros: los
-- pedidos quedan, anónimos, para las liquidaciones de los locales.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli uuid := gen_random_uuid();
  u_otro uuid := gen_random_uuid();
  u_com uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  ciudad uuid; cli uuid; otro uuid; com uuid; dir uuid; seccion uuid; prod uuid;
  ped1 public.pedidos;  -- pagado: frena la baja hasta que termine
  ped2 public.pedidos;  -- esperando el pago: la baja lo cancela
  rec uuid;
  ok boolean;
  n integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','baja-cli@test.local','x','{"provider":"email"}','{"nombre":"Clienta Baja","telefono":"+54 260 456-0003"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','baja-otro@test.local','x','{"provider":"email"}','{"nombre":"Otro Cliente","telefono":"+54 260 456-0004"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','baja-com@test.local','x','{"rol":"comercio"}','{}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','baja-adm@test.local','x','{"rol":"admin"}','{}',now(),now(),now());
  select id into cli from public.clientes where perfil_id = u_cli;
  select id into otro from public.clientes where perfil_id = u_otro;

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Baja', 'Pizzeria', '2604000093', 'Roca 950',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;
  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;
  insert into public.secciones_menu (comercio_id, nombre) values (com, 'Pizzas') returning id into seccion;
  insert into public.productos (comercio_id, seccion_id, nombre, precio)
  values (com, seccion, 'Muzzarella', 9000) returning id into prod;

  insert into public.direcciones_cliente (cliente_id, alias, calle, referencia, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martín 450', 'Portón verde',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5852, -35.4769), 4326)::extensions.geography, true)
  returning id into dir;
  insert into public.tarjetas_guardadas (cliente_id, mp_card_id, marca, ultimos4, vence_mes, vence_anio, titular, predeterminada)
  values (cli, 'card-baja-1', 'visa', '4242', 12, 2030, 'CLIENTA BAJA', true);
  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio)
  values (cli, public.hoy(), public.hoy() + 30, 2500);
  insert into public.push_tokens (perfil_id, token, plataforma) values (u_cli, 'token-baja-1', 'android');

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped1 := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), 'Tocar timbre 2B', 'mercado_pago');
  ped2 := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 2)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);
  ped1 := public.confirmar_pago_online(ped1.id, 'PAY-BAJA-1', 'acreditado');

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  set local role authenticated;
  insert into public.reclamos (pedido_id, motivo) values (ped1.id, 'Prueba de baja') returning id into rec;
  reset role;

  -- ---- Con un pedido andando, no ------------------------------------------------
  begin
    set local role authenticated;
    perform public.eliminar_mi_cuenta();
    reset role;
    insert into _r values ('01 NO se elimina con un pedido en curso', 'MAL  la eliminó');
  exception when others then
    reset role;
    insert into _r values ('01 NO se elimina con un pedido en curso',
      case when sqlstate = 'MY009' then 'OK  espera a que llegue' else 'MAL  ' || sqlstate || ' ' || sqlerrm end);
  end;

  -- El local lo rechaza: deja de estar en curso (y la plata vuelve, 0060).
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  perform public.rechazar_pedido(ped1.id, 'Prueba');
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);

  -- ---- La baja ------------------------------------------------------------------
  set local role authenticated;
  perform public.eliminar_mi_cuenta();
  reset role;
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('02 el usuario ya no existe',
    case when not exists (select 1 from auth.users where id = u_cli)
              and not exists (select 1 from public.perfiles where id = u_cli)
         then 'OK  ni email ni contraseña' else 'MAL' end);

  insert into _r values ('03 el cliente queda anónimo',
    (select case when perfil_id is null and nombre = 'Cuenta eliminada' and telefono is null
                 then 'OK' else format('MAL  %s %s', nombre, telefono) end
       from public.clientes where id = cli));

  insert into _r values ('04 los pedidos se conservan',
    (select case when count(*) = 2 then 'OK  para las liquidaciones del local' else format('MAL  %s', count(*)) end
       from public.pedidos where cliente_id = cli));

  insert into _r values ('05 sin nombre, teléfono, dirección ni nota',
    case when not exists (select 1 from public.pedidos
                           where cliente_id = cli
                             and (cliente_nombre <> 'Cuenta eliminada' or cliente_telefono is not null
                                  or nota_cliente is not null or entrega_calle <> 'Dirección eliminada'
                                  or entrega_referencia is not null))
         then 'OK' else 'MAL  quedó algo' end);

  insert into _r values ('06 la ubicación ya no señala la casa',
    (select case when extensions.ST_Distance(entrega_ubicacion,
                        extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5852, -35.4769), 4326)::extensions.geography) > 50
                 then 'OK  redondeada a 1 km' else 'MAL  sigue en la puerta' end
       from public.pedidos where id = ped1.id));

  insert into _r values ('07 el que esperaba el pago se canceló',
    (select case when estado = 'cancelado' then 'OK' else 'MAL  ' || estado end
       from public.pedidos where id = ped2.id));

  insert into _r values ('08 direcciones, tarjetas, Plus y dispositivo borrados',
    case when not exists (select 1 from public.direcciones_cliente where cliente_id = cli)
              and not exists (select 1 from public.tarjetas_guardadas where cliente_id = cli)
              and not exists (select 1 from public.suscripciones_plus where cliente_id = cli)
              and not exists (select 1 from public.push_tokens where token = 'token-baja-1')
         then 'OK' else 'MAL' end);

  insert into _r values ('09 el reclamo queda, sin quién lo abrió',
    (select case when abierto_por is null then 'OK' else 'MAL' end from public.reclamos where id = rec));

  -- ---- Quién puede --------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  begin
    set local role authenticated;
    perform public.eliminar_mi_cuenta();
    reset role;
    ok := false;
  exception when others then reset role; ok := sqlstate = '42501'; end;
  insert into _r values ('10 NO un local se da de baja solo', case when ok then 'OK  lo hace la administración' else 'MAL' end);

  begin
    set local role authenticated;
    perform public.admin_eliminar_cliente('baja-otro@test.local');
    reset role;
    ok := false;
  exception when others then reset role; ok := sqlstate = '42501'; end;
  insert into _r values ('11 NO un local da de baja a un cliente', case when ok then 'OK' else 'MAL' end);

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  set local role authenticated;
  perform public.admin_eliminar_cliente('BAJA-OTRO@test.local');
  reset role;
  insert into _r values ('12 la administración da de baja por email',
    case when not exists (select 1 from auth.users where id = u_otro)
              and (select nombre from public.clientes where id = otro) = 'Cuenta eliminada'
         then 'OK  sin importar mayúsculas' else 'MAL' end);
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('13 NO se puede llamar sin sesión',
    case when has_function_privilege('anon', 'public.eliminar_mi_cuenta()', 'execute')
         then 'MAL' else 'OK' end);

  -- ---- Limpieza -----------------------------------------------------------------
  delete from public.reclamos where id = rec;
  update public.pedidos set envio_id = null where comercio_id = com;
  delete from public.envios where comercio_id = com;
  create temporary table _pagos on commit drop as
    select pago_id from public.pedidos where comercio_id = com and pago_id is not null;
  delete from public.cargos_comercio where comercio_id = com;
  delete from public.pedidos where comercio_id = com;
  delete from public.pagos where id in (select pago_id from _pagos);
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.comercios where id = com;
  delete from public.clientes where id in (cli, otro);
  delete from auth.users where id in (u_cli, u_otro, u_com, u_adm);
end $$;

select paso, resultado from _r order by paso;
