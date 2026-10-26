-- Cargos de un local: lo que se le descuenta en su liquidación.
--
-- Lo que importa: que un cargo que ya entró en una liquidación cerrada no se
-- pueda borrar (los totales guardados no se recalculan, así que al local le
-- quedaría un descuento cobrado sin el renglón que lo explica), y que la vía
-- para corregirlo sea la que el esquema previó desde 0035: cargar otro con
-- monto negativo.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  ciudad uuid; com uuid;
  cargo uuid; devolucion uuid;
  liq public.liquidaciones_comercio;
  n integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','menores-cargo-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','menores-cargo-adm@test.local','x','{"rol":"admin"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Cargos', 'Pizzeria', '2604000091', 'Roca 950',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);

  -- ---- La penalidad por rechazar un pedido cobrado se carga sola (0060) ------
  insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, creado_por)
  values (com, 'ajuste', 'Penalidad por rechazar P-9999', 7000, u_adm)
  returning id into cargo;

  insert into _r values ('01 el cargo se le descuenta',
    (select case when cargos = 7000 and total = -7000
                 then format('OK  cargos $%s', cargos)
                 else format('MAL  cargos=%s total=%s', cargos, total) end
       from public.pendiente_de_liquidar_comercios(public.hoy() - 1, public.hoy())
      where comercio_id = com));

  -- ---- Mientras no esté liquidado se borra ----------------------------------
  perform public.admin_borrar_cargo_comercio(cargo);
  insert into _r values ('02 sin liquidar si se borra',
    case when not exists (select 1 from public.cargos_comercio where id = cargo)
         then 'OK  se fue' else 'MAL  quedo' end);

  -- Se vuelve a cargar para el resto de la prueba.
  insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, creado_por)
  values (com, 'ajuste', 'Penalidad por rechazar P-9999', 7000, u_adm)
  returning id into cargo;
  perform set_config('request.jwt.claims', null, true);

  -- ---- El local no borra lo que le cobran -----------------------------------
  -- Ojo: esto corre como `postgres`, que saltea RLS. Sin `set local role
  -- authenticated` la prueba pasa siempre y no prueba nada.
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  set local role authenticated;
  delete from public.cargos_comercio where id = cargo;
  reset role;
  insert into _r values ('03 el local no borra su propio cargo',
    case when exists (select 1 from public.cargos_comercio where id = cargo)
         then 'OK  el RLS lo dejo sin efecto' else 'MAL  lo borro' end);

  begin
    perform public.admin_borrar_cargo_comercio(cargo);
    insert into _r values ('04 ni por la funcion', 'MAL  lo dejo');
  exception when others then
    insert into _r values ('04 ni por la funcion', 'OK  rechazado');
  end;
  perform set_config('request.jwt.claims', null, true);

  -- ---- Cerrada la liquidación, el cargo ya se cobró --------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_adm)::text, true);
  liq := public.cerrar_liquidacion_comercio(com, public.hoy() - 1, public.hoy());
  insert into _r values ('05 el cierre se lleva el cargo',
    case when liq.cargos = 7000 and liq.total = -7000
         then format('OK  descuento $%s asentado', liq.cargos)
         else format('MAL  cargos=%s total=%s', liq.cargos, liq.total) end);

  begin
    perform public.admin_borrar_cargo_comercio(cargo);
    insert into _r values ('06 ya liquidado no se borra', 'MAL  lo borro ya liquidado');
  exception when others then
    insert into _r values ('06 ya liquidado no se borra',
      'OK  rechazado: ' || left(sqlerrm, 40));
  end;

  insert into _r values ('07 el renglon sigue explicando el descuento',
    (select case when liquidacion_id = liq.id then 'OK  atado a esa liquidacion' else 'MAL' end
       from public.cargos_comercio where id = cargo));

  -- ---- Si el local reclama con razón, se le devuelve ------------------------
  -- Es la vía que el esquema previó: "Negativo: se le suma (una devolucion)".
  insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, creado_por)
  values (com, 'ajuste', 'Le devolvemos la penalidad de P-9999', -7000, u_adm)
  returning id into devolucion;

  insert into _r values ('08 un cargo negativo le devuelve la plata',
    (select case when cargos = -7000 and total = 7000
                 then 'OK  se le suma sin borrar el historial'
                 else format('MAL  cargos=%s total=%s', cargos, total) end
       from public.pendiente_de_liquidar_comercios(public.hoy() - 1, public.hoy())
      where comercio_id = com));

  insert into _r values ('09 y aparece en el detalle del periodo',
    (select case when count(*) = 1 then 'OK  1 renglon' else format('MAL  %s renglones', count(*)) end
       from public.cargos_a_liquidar_comercio(com, public.hoy() - 1, public.hoy())));
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza --------------------------------------------------------------
  update public.cargos_comercio set liquidacion_id = null where comercio_id = com;
  delete from public.cargos_comercio where comercio_id = com;
  delete from public.liquidaciones_comercio where comercio_id = com;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_adm);
end $$;

select paso, resultado from _r order by paso;
