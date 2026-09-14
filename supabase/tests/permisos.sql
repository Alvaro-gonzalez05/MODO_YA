-- Prueba de permisos por columna (ver migracion 0016).
--
-- Dos lados: lo que NO se tiene que poder (escalar privilegios editando la
-- propia fila) y lo que SI (editar los datos propios). Cerrar de mas tambien es
-- un bug: un local que no puede cambiar su telefono es un ticket de soporte.
--
-- Todo lo que mide RLS o permisos corre con `set local role authenticated`;
-- como postgres saltearia todo y el test pasaria siempre.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli uuid := gen_random_uuid();
  u_com uuid := gen_random_uuid();
  u_rep uuid := gen_random_uuid();
  u_esc uuid := gen_random_uuid();
  ciudad uuid;
  com uuid; rep uuid; doc uuid;
  v text; n int;
  ok boolean;
begin
  select id into ciudad from public.ciudades limit 1;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','perm-cli@test.local','x','{"rol":"cliente"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','perm-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_rep,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','perm-rep@test.local','x','{"rol":"repartidor"}',now(),now(),now());

  -- Si ya existe el trigger de alta (0017), los perfiles se crean solos.
  insert into public.perfiles (id, rol, nombre) values
    (u_cli,'cliente','Perm Cli'), (u_com,'comercio','Perm Com'), (u_rep,'repartidor','Perm Rep')
  on conflict (id) do nothing;

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, estado_aprobacion)
  values (u_com, ciudad, 'Perm', 'x', '111', 'x', 'pendiente') returning id into com;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_rep, ciudad, 'Perm', '222', 'moto', 'pendiente') returning id into rep;

  insert into public.documentos_repartidor (repartidor_id, tipo, estado)
  values (rep, 'DNI', 'pendiente') returning id into doc;

  -- ---- NO: cliente se hace admin -------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  begin
    set local role authenticated;
    update public.perfiles set rol = 'admin' where id = u_cli;
    reset role;
  exception when others then reset role; end;
  select rol::text into v from public.perfiles where id = u_cli;
  insert into _r values ('01 NO cliente -> admin',
    case when v = 'cliente' then 'OK' else 'VULNERABLE rol=' || v end);

  -- ---- SI: cliente cambia su nombre ----------------------------------------
  begin
    set local role authenticated;
    update public.perfiles set nombre = 'Nombre Nuevo' where id = u_cli;
    reset role;
  exception when others then reset role; end;
  select nombre into v from public.perfiles where id = u_cli;
  insert into _r values ('02 SI cliente edita su nombre',
    case when v = 'Nombre Nuevo' then 'OK' else 'BLOQUEADO DE MAS (' || v || ')' end);

  -- ---- NO: comercio se autoaprueba -----------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  begin
    set local role authenticated;
    update public.comercios set estado_aprobacion = 'aprobado' where id = com;
    reset role;
  exception when others then reset role; end;
  select estado_aprobacion::text into v from public.comercios where id = com;
  insert into _r values ('03 NO comercio se autoaprueba',
    case when v = 'pendiente' then 'OK' else 'VULNERABLE ' || v end);

  -- ---- SI: comercio cambia su telefono -------------------------------------
  begin
    set local role authenticated;
    update public.comercios set telefono = '999' where id = com;
    reset role;
  exception when others then reset role; end;
  select telefono into v from public.comercios where id = com;
  insert into _r values ('04 SI comercio edita su telefono',
    case when v = '999' then 'OK' else 'BLOQUEADO DE MAS (' || v || ')' end);

  -- ---- SI: comercio marca su ubicacion por RPC -----------------------------
  begin
    set local role authenticated;
    perform public.set_ubicacion_comercio(-35.4761, -69.5839);
    reset role;
  exception when others then reset role; end;
  select count(*) into n from public.comercios where id = com and ubicacion is not null;
  insert into _r values ('05 SI comercio marca ubicacion',
    case when n = 1 then 'OK' else 'BLOQUEADO DE MAS' end);

  -- ---- NO: comercio llama una funcion de admin -----------------------------
  ok := false;
  begin
    set local role authenticated;
    perform public.admin_aprobacion_comercio(com, 'aprobado');
    reset role;
  exception when others then reset role; ok := true; end;
  insert into _r values ('06 NO comercio usa admin_aprobacion',
    case when ok then 'OK (rechazado)' else 'VULNERABLE' end);

  -- ---- NO: cadete se sube la reputacion o se libera ------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_rep)::text, true);
  begin
    set local role authenticated;
    update public.repartidores set reputacion = 5, viajes_completados = 9999 where id = rep;
    reset role;
  exception when others then reset role; end;
  select viajes_completados::text into v from public.repartidores where id = rep;
  insert into _r values ('07 NO cadete infla sus viajes',
    case when v = '0' then 'OK' else 'VULNERABLE viajes=' || v end);

  -- ---- NO: cadete valida su propio documento -------------------------------
  begin
    set local role authenticated;
    update public.documentos_repartidor set estado = 'aprobado' where id = doc;
    reset role;
  exception when others then reset role; end;
  select estado::text into v from public.documentos_repartidor where id = doc;
  insert into _r values ('08 NO cadete valida su documento',
    case when v = 'pendiente' then 'OK' else 'VULNERABLE ' || v end);

  -- ---- SI: cadete sube el archivo de su documento --------------------------
  begin
    set local role authenticated;
    update public.documentos_repartidor set archivo_url = 'rep/dni.jpg' where id = doc;
    reset role;
  exception when others then reset role; end;
  select coalesce(archivo_url,'(null)') into v from public.documentos_repartidor where id = doc;
  insert into _r values ('09 SI cadete sube su archivo',
    case when v = 'rep/dni.jpg' then 'OK' else 'BLOQUEADO DE MAS (' || v || ')' end);

  -- ---- NO: cadete se conecta sin estar aprobado ----------------------------
  ok := false;
  begin
    set local role authenticated;
    perform public.set_conectado(true);
    reset role;
  exception when others then reset role; ok := true; end;
  insert into _r values ('10 NO cadete pendiente se conecta',
    case when ok then 'OK (rechazado)' else 'VULNERABLE' end);

  -- ---- NO: registrarse como admin por user_metadata ------------------------
  -- signUp(data: {rol: admin}) llega en raw_user_meta_data. El trigger de alta
  -- solo mira app_metadata, asi que tiene que quedar como cliente.
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values (u_esc,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
          'perm-esc@test.local','x','{"provider":"email"}','{"rol":"admin","nombre":"Pillo"}',
          now(),now(),now());
  select rol::text into v from public.perfiles where id = u_esc;
  insert into _r values ('11 NO signup con rol admin en user_metadata',
    case when v = 'cliente' then 'OK (quedo cliente)'
         else 'VULNERABLE rol=' || coalesce(v, '(sin perfil)') end);
  select count(*) into n from public.clientes where perfil_id = u_esc;
  insert into _r values ('12 SI alta crea fila de cliente',
    case when n = 1 then 'OK' else 'FALTA (' || n || ')' end);

  -- ---- Limpieza ------------------------------------------------------------
  perform set_config('request.jwt.claims', null, true);
  delete from auth.users where id = u_esc;
  delete from public.documentos_repartidor where id = doc;
  delete from public.repartidores where id = rep;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_cli, u_com, u_rep);
end $$;

select * from _r order by paso;
