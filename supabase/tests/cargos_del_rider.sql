-- Cargos del rider: lo que se le descuenta de lo que cobra.
--
-- Lo que importa: que llegue a la liquidación y que no lo pueda tocar nadie más
-- que la administración. Y que si debe más de lo que ganó, quede asentado en
-- vez de perderse.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_rid uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  u_otro uuid := gen_random_uuid();
  ciudad uuid; rid uuid; otro uuid;
  c public.cargos_repartidor;
  n integer;
  liq public.liquidaciones;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_rid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','carg-rid@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','carg-otro@test.local','x','{"rol":"repartidor"}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','carg-adm@test.local','x','{"rol":"admin"}',now(),now(),now());

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_rid, ciudad, 'Rider Cargos', '2604222000', 'moto', 'aprobado') returning id into rid;
  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_otro, ciudad, 'Rider Ajeno', '2604222001', 'moto', 'aprobado') returning id into otro;

  -- ---- Solo la administración carga ------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_rid)::text, true);
  begin
    c := public.admin_cargar_a_rider(rid, 'ajuste', 'Me lo perdono', -5000);
    insert into _r values ('01 el rider no se carga a si mismo', 'MAL  lo dejo');
  exception when others then
    insert into _r values ('01 el rider no se carga a si mismo', 'OK  rechazado');
  end;
  perform set_config('request.jwt.claims', null, true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  c := public.admin_cargar_a_rider(rid, 'abandono', 'Se bajó con el pedido en la puerta', 8000);
  insert into _r values ('02 la administracion si carga',
    case when c.monto = 8000 and c.concepto = 'abandono' and c.creado_por = u_adm
         then 'OK  queda con quien lo cargo' else 'MAL' end);

  begin
    c := public.admin_cargar_a_rider(rid, 'ajuste', '   ', 1000);
    insert into _r values ('03 exige decir por que', 'MAL  lo dejo sin detalle');
  exception when others then
    insert into _r values ('03 exige decir por que', 'OK  rechazado');
  end;
  perform set_config('request.jwt.claims', null, true);

  -- ---- Cada uno ve lo suyo ---------------------------------------------------
  -- Ojo: esto corre como `postgres`, que saltea RLS. Sin `set local role
  -- authenticated` la prueba pasa siempre y no prueba nada.
  perform set_config('request.jwt.claims', json_build_object('sub', u_otro)::text, true);
  set local role authenticated;
  select count(*) into n from public.cargos_repartidor where repartidor_id = rid;
  reset role;
  insert into _r values ('04 un rider no ve el cargo de otro',
    case when n = 0 then 'OK  0 filas' else format('MAL  vio %s', n) end);
  perform set_config('request.jwt.claims', null, true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_rid)::text, true);
  set local role authenticated;
  select count(*) into n from public.cargos_repartidor where repartidor_id = rid;
  reset role;
  insert into _r values ('05 el rider si ve el suyo',
    case when n = 1 then 'OK  sabe por que cobra menos' else format('MAL  vio %s', n) end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- Llega a la liquidación -------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  insert into _r values ('06 aparece en lo pendiente de liquidar',
    (select case when cargos = 8000 and total = -8000
                 then format('OK  cargos $%s, total %s', cargos, total)
                 else format('MAL  cargos=%s total=%s', cargos, total) end
       from public.pendiente_de_liquidar_riders(public.hoy() - 1, public.hoy())
      where repartidor_id = rid));

  liq := public.cerrar_liquidacion_rider(rid, public.hoy() - 1, public.hoy());
  insert into _r values ('07 al cerrar queda el numero en contra',
    case when liq.ajustes = 8000 and liq.total = -8000
         then 'OK  debe $8.000 y queda asentado'
         else format('MAL  ajustes=%s total=%s', liq.ajustes, liq.total) end);

  insert into _r values ('08 el cargo queda atado a esa liquidacion',
    (select case when liquidacion_id = liq.id then 'OK  no se cobra dos veces' else 'MAL' end
       from public.cargos_repartidor where repartidor_id = rid));

  insert into _r values ('09 ya liquidado no se borra',
    (select case when count(*) = 0 then 'MAL' else 'OK' end from public.cargos_repartidor where repartidor_id = rid));
  begin
    perform public.admin_borrar_cargo_rider((select id from public.cargos_repartidor where repartidor_id = rid));
    update _r set resultado = 'MAL  lo borro ya liquidado' where paso = '09 ya liquidado no se borra';
  exception when others then
    update _r set resultado = 'OK  rechazado, ya se le pago con ese numero' where paso = '09 ya liquidado no se borra';
  end;

  -- ---- Un cargo negativo devuelve ---------------------------------------------
  c := public.admin_cargar_a_rider(rid, 'ajuste', 'Le cobramos de mas la semana pasada', -3000);
  insert into _r values ('10 un cargo negativo le suma',
    (select case when cargos = -3000 and total = 3000
                 then 'OK  se le devuelve sin borrar el historial'
                 else format('MAL  cargos=%s total=%s', cargos, total) end
       from public.pendiente_de_liquidar_riders(public.hoy() - 1, public.hoy())
      where repartidor_id = rid));
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.cargos_repartidor where repartidor_id in (rid, otro);
  delete from public.liquidacion_items where liquidacion_id in
    (select id from public.liquidaciones where repartidor_id in (rid, otro));
  delete from public.liquidaciones where repartidor_id in (rid, otro);
  delete from public.repartidores where id in (rid, otro);
  delete from auth.users where id in (u_rid, u_otro, u_adm);
end $$;

select paso, resultado from _r order by paso;
