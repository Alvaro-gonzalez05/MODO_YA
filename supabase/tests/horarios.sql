-- Prueba de horarios con momentos fijos (no depende de la hora de corrida).
--
-- Fechas de referencia (2026):
--   sabado 12/09  (dow 6)
--   domingo 13/09 (dow 0)
--   lunes 14/09   (dow 1)

create temporary table _r (paso text, resultado text);

do $$
declare
  u uuid := gen_random_uuid();
  ciudad uuid;
  com uuid;
begin
  select id into ciudad from public.ciudades limit 1;
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values (u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','hor@test.local','x','{"rol":"comercio"}',now(),now(),now());
  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, estado_aprobacion)
  values (u, ciudad, 'Hor', 'x', 'x', 'x', 'aprobado') returning id into com;

  -- ---- Sin horarios: cerrado (0027) ---------------------------------------
  insert into _r values ('01 sin horarios figura cerrado',
    case when not public.comercio_abierto_en(com, '2026-09-14 20:00') then 'OK cerrado' else 'FALLA' end);
  update public.comercios set acepta_pedidos = false where id = com;
  insert into _r values ('02 sin horarios y pausado',
    case when not public.comercio_abierto_en(com, '2026-09-14 20:00') then 'OK cerrado' else 'FALLA' end);
  update public.comercios set acepta_pedidos = true where id = com;

  -- ---- Turno normal: lunes 11:00 a 15:00 ----------------------------------
  insert into public.horarios_comercio (comercio_id, dia, abre, cierra) values (com, 1, '11:00', '15:00');
  insert into _r values ('03 lunes 12:00 dentro',
    case when public.comercio_abierto_en(com, '2026-09-14 12:00') then 'OK abierto' else 'FALLA' end);
  insert into _r values ('04 lunes 15:00 justo al cerrar',
    case when not public.comercio_abierto_en(com, '2026-09-14 15:00') then 'OK cerrado' else 'FALLA' end);
  insert into _r values ('05 lunes 10:59 antes de abrir',
    case when not public.comercio_abierto_en(com, '2026-09-14 10:59') then 'OK cerrado' else 'FALLA' end);
  insert into _r values ('06 domingo 12:00 otro dia',
    case when not public.comercio_abierto_en(com, '2026-09-13 12:00') then 'OK cerrado' else 'FALLA' end);
  delete from public.horarios_comercio where comercio_id = com;

  -- ---- Turno que cruza la medianoche: lunes 20:00 a 01:00 -----------------
  insert into public.horarios_comercio (comercio_id, dia, abre, cierra) values (com, 1, '20:00', '01:00');
  insert into _r values ('07 lunes 23:30 turno de hoy',
    case when public.comercio_abierto_en(com, '2026-09-14 23:30') then 'OK abierto' else 'FALLA' end);
  insert into _r values ('08 martes 00:30 sigue el turno del lunes',
    case when public.comercio_abierto_en(com, '2026-09-15 00:30') then 'OK abierto' else 'FALLA' end);
  insert into _r values ('09 martes 01:30 ya cerro',
    case when not public.comercio_abierto_en(com, '2026-09-15 01:30') then 'OK cerrado' else 'FALLA' end);
  insert into _r values ('10 lunes 00:30 no hay turno del domingo',
    case when not public.comercio_abierto_en(com, '2026-09-14 00:30') then 'OK cerrado' else 'FALLA' end);
  insert into _r values ('11 lunes 19:59 antes de abrir',
    case when not public.comercio_abierto_en(com, '2026-09-14 19:59') then 'OK cerrado' else 'FALLA' end);
  delete from public.horarios_comercio where comercio_id = com;

  -- ---- Vuelta de semana: sabado 22:00 a 02:00, evaluado el domingo --------
  insert into public.horarios_comercio (comercio_id, dia, abre, cierra) values (com, 6, '22:00', '02:00');
  insert into _r values ('12 domingo 01:00 turno del sabado (6 -> 0)',
    case when public.comercio_abierto_en(com, '2026-09-13 01:00') then 'OK abierto' else 'FALLA' end);
  delete from public.horarios_comercio where comercio_id = com;

  -- ---- Dos turnos el mismo dia: 11-15 y 20-00:30 --------------------------
  insert into public.horarios_comercio (comercio_id, dia, abre, cierra) values
    (com, 1, '11:00', '15:00'), (com, 1, '20:00', '00:30');
  insert into _r values ('13 lunes 17:00 entre turnos',
    case when not public.comercio_abierto_en(com, '2026-09-14 17:00') then 'OK cerrado' else 'FALLA' end);
  insert into _r values ('14 lunes 21:00 segundo turno',
    case when public.comercio_abierto_en(com, '2026-09-14 21:00') then 'OK abierto' else 'FALLA' end);

  -- ---- Con horario cargado, el interruptor igual manda --------------------
  update public.comercios set acepta_pedidos = false where id = com;
  insert into _r values ('15 dentro de horario pero pausado',
    case when not public.comercio_abierto_en(com, '2026-09-14 21:00') then 'OK cerrado' else 'FALLA' end);

  delete from public.horarios_comercio where comercio_id = com;
  delete from public.comercios where id = com;
  delete from auth.users where id = u;
end $$;

select * from _r order by paso;
