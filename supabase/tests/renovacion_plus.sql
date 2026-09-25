-- Renovación automática de MODO YA Plus.
--
-- El cobro lo hace la Edge Function; lo que se prueba acá es a quién decide la
-- base que hay que cobrarle, que no le cobre a quien no corresponde, y el
-- interruptor que el cliente tiene en la app.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_a uuid := gen_random_uuid();  -- vencido, con tarjeta: hay que renovarle
  u_b uuid := gen_random_uuid();  -- vencido, sin tarjeta
  u_c uuid := gen_random_uuid();  -- vigente todavia
  a uuid; b uuid; c uuid;
  sus_a uuid;
  s public.suscripciones_plus;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','renov-a@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_b,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','renov-b@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_c,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','renov-c@test.local','x','{"provider":"email"}',now(),now(),now());

  select id into a from public.clientes where perfil_id = u_a;
  select id into b from public.clientes where perfil_id = u_b;
  select id into c from public.clientes where perfil_id = u_c;

  insert into public.tarjetas_guardadas
    (cliente_id, mp_card_id, marca, ultimos4, vence_mes, vence_anio, titular, predeterminada)
  values (a, 'card-a', 'visa', '4218', 12, 2030, 'PRUEBA', true),
         (c, 'card-c', 'visa', '1111', 12, 2030, 'PRUEBA', true);

  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, renovar)
  values (a, current_date - 31, current_date - 1, 2500, true) returning id into sus_a;
  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, renovar)
  values (b, current_date - 31, current_date - 1, 2500, true);
  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, renovar)
  values (c, current_date - 1, current_date + 29, 2500, true);

  -- ---- A quién le toca -------------------------------------------------------
  insert into _r values ('01 vencido y con tarjeta',
    case when exists (select 1 from public.plus_por_renovar() where cliente_id = a)
         then 'OK  entra en la lista del dia' else 'MAL  no entro' end);

  insert into _r values ('02 sin tarjeta guardada no entra',
    case when not exists (select 1 from public.plus_por_renovar() where cliente_id = b)
         then 'OK  no hay con que cobrarle' else 'MAL' end);

  insert into _r values ('03 el que todavia tiene Plus no entra',
    case when not exists (select 1 from public.plus_por_renovar() where cliente_id = c)
         then 'OK  se le cobra cuando se venza' else 'MAL  se le cobraria de mas' end);

  insert into _r values ('04 el precio sale del tarifario',
    (select case when precio = public.precio_plus()
                 then format('OK  $%s', precio) else format('MAL  %s', precio) end
       from public.plus_por_renovar() where cliente_id = a));

  -- ---- La tarjeta rebota -----------------------------------------------------
  perform public.plus_renovacion_fallo(sus_a, 'La tarjeta no tiene fondos suficientes.');
  insert into _r values ('05 un rechazo no lo saca de la lista',
    case when exists (select 1 from public.plus_por_renovar() where cliente_id = a)
         then 'OK  se reintenta mañana' else 'MAL' end);

  perform public.plus_renovacion_fallo(sus_a, 'otra vez');
  perform public.plus_renovacion_fallo(sus_a, 'y otra');
  insert into _r values ('06 al tercer rechazo se deja de insistir',
    case when not exists (select 1 from public.plus_por_renovar() where cliente_id = a)
         then 'OK  renueva a mano' else 'MAL  seguiria intentando' end);

  -- ---- El interruptor del cliente --------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_a)::text, true);
  perform public.cortar_renovacion_plus(true);
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('07 al reactivarla se perdona lo fallado',
    (select case when renovar and intentos_fallidos = 0 and ultimo_error is null
                 then 'OK  vuelve a intentarse' else 'MAL' end
       from public.suscripciones_plus where id = sus_a));

  perform set_config('request.jwt.claims', json_build_object('sub', u_c)::text, true);
  perform public.cortar_renovacion_plus(false);
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('08 el cliente puede cortarla',
    (select case when not renovar then 'OK  no se le cobra mas' else 'MAL' end
       from public.suscripciones_plus where cliente_id = c));

  -- ---- La renovación no le come días al que todavía tiene --------------------
  s := public.activar_plus(c, 2500, null);
  insert into _r values ('09 renovar no pisa los dias que quedaban',
    case when s.desde = current_date + 29 and s.hasta = current_date + 59
         then 'OK  se le suma un mes a lo que tenia'
         else format('MAL  %s -> %s', s.desde, s.hasta) end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.suscripciones_plus where cliente_id in (a, b, c);
  delete from public.tarjetas_guardadas where cliente_id in (a, b, c);
  delete from public.clientes where id in (a, b, c);
  delete from auth.users where id in (u_a, u_b, u_c);
end $$;

select paso, resultado from _r order by paso;
