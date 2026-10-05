-- Solicitud de alta de un rider nuevo (0055): que el local la cree y la vea,
-- que otro local no, que nadie se la apruebe solo, y que rechazar pida motivo.
--
-- La aprobacion crea un usuario de Auth y por eso la hace la Edge Function
-- admin-crear-usuario: no se puede probar desde SQL.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com  uuid := gen_random_uuid();
  u_otro uuid := gen_random_uuid();
  u_adm  uuid := gen_random_uuid();
  ciudad uuid; com uuid; otro uuid;
  sol uuid;
  n integer;
  ok boolean;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_com, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','sol-com@test.local','x','{"rol":"comercio"}','{"nombre":"Local Sol"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','sol-otro@test.local','x','{"rol":"comercio"}','{"nombre":"Otro Local"}',now(),now(),now()),
    (u_adm, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','sol-adm@test.local','x','{"rol":"admin"}','{"nombre":"Admin Sol"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Sol','Pizzeria','2604000060','Roca 600',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5839,-35.4761),4326)::extensions.geography,'aprobado')
  returning id into com;
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_otro, ciudad, 'Otro Local','Pizzeria','2604000061','Roca 700',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5839,-35.4761),4326)::extensions.geography,'aprobado')
  returning id into otro;

  -- ---- El local la crea --------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  set local role authenticated;
  insert into public.solicitudes_rider (comercio_id, nombre, telefono, vehiculo)
  values (com, 'Juan Cadete', '2604555111', 'moto')
  returning id into sol;
  select count(*) into n from public.solicitudes_rider where id = sol;
  reset role;
  insert into _r values ('1. el local la crea y la ve',
    case when n = 1 then 'OK' else 'MAL  no la ve' end);

  -- ---- No puede crearla a nombre de otro local -------------------------------
  set local role authenticated;
  begin
    insert into public.solicitudes_rider (comercio_id, nombre, telefono, vehiculo)
    values (otro, 'Colado', '2604555222', 'moto');
    ok := true;
  exception when others then ok := false;
  end;
  reset role;
  insert into _r values ('2. no la crea a nombre de otro local',
    case when not ok then 'OK  rebota' else 'MAL  entro' end);

  -- ---- No se la aprueba solo -------------------------------------------------
  set local role authenticated;
  begin
    update public.solicitudes_rider set estado = 'aprobada' where id = sol;
    ok := true;
  exception when others then ok := false;
  end;
  reset role;
  insert into _r values ('3. el local no se la aprueba solo',
    case when (select estado from public.solicitudes_rider where id = sol) = 'pendiente'
         then 'OK  sigue pendiente' else 'MAL  se aprobo sola' end);

  -- ---- Otro local no la ve ---------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_otro)::text, true);
  set local role authenticated;
  select count(*) into n from public.solicitudes_rider where id = sol;
  reset role;
  insert into _r values ('4. otro local no la ve',
    case when n = 0 then 'OK' else 'MAL  la ve' end);

  -- ---- Rechazar pide motivo, y solo la administracion ------------------------
  begin
    perform public.admin_rechazar_solicitud_rider(sol, 'No');
    ok := true;
  exception when others then ok := false;
  end;
  insert into _r values ('5. un local no puede rechazar',
    case when not ok then 'OK  rebota' else 'MAL' end);

  perform set_config('request.jwt.claims', json_build_object('sub',u_adm)::text, true);
  begin
    perform public.admin_rechazar_solicitud_rider(sol, '   ');
    ok := true;
  exception when others then ok := false;
  end;
  insert into _r values ('6. rechazar sin motivo no se puede',
    case when not ok then 'OK  rebota' else 'MAL' end);

  perform public.admin_rechazar_solicitud_rider(sol, 'Falta la licencia');
  insert into _r values ('7. rechazada con el motivo que ve el local',
    (select case when estado = 'rechazada' and motivo_rechazo = 'Falta la licencia'
                 then 'OK  ' || motivo_rechazo else 'MAL' end
       from public.solicitudes_rider where id = sol));

  -- ---- Limpieza --------------------------------------------------------------
  perform set_config('request.jwt.claims', null, true);
  delete from public.solicitudes_rider where comercio_id in (com, otro);
  delete from public.comercios where id in (com, otro);
  delete from auth.users where id in (u_com, u_otro, u_adm);
end $$;

select paso, resultado from _r order by paso;
