-- Lo que quedó abierto de los pagos (0072).
--
--   * el alta de Plus no se cobra dos veces, y si queda en revisión el aviso
--     le activa el mes solo;
--   * un pago en revisión se consulta aunque no llegue ningún aviso;
--   * una devolución parcial no deja el pago como si no hubiera entrado nada.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli uuid := gen_random_uuid();
  cli uuid;
  t record;
  pago_plus uuid; pago_rev uuid; pago_sim uuid; pago_viejo uuid; pago_parc uuid;
  nota text;
  n integer;
  ok boolean;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','plus-alta@test.local','x','{"provider":"email"}','{"nombre":"Clienta Plus","telefono":"+54 260 456-0002"}',now(),now(),now());
  select id into cli from public.clientes where perfil_id = u_cli;

  -- ---- El alta de Plus se toma una sola vez ------------------------------------
  select * into t from public.tomar_el_cobro_plus(cli);
  pago_plus := t.pago_id;
  insert into _r values ('01 el primer alta se puede cobrar',
    case when t.clave = 'plus-alta-' || pago_plus || '-1' and t.monto = public.precio_plus()
         then format('OK  $%s, la clave sale del pago', t.monto) else 'MAL  ' || coalesce(t.clave, t.motivo) end);

  select * into t from public.tomar_el_cobro_plus(cli);
  insert into _r values ('02 NO un segundo toque mientras el primero está en vuelo',
    case when t.clave is null and t.motivo = 'en_curso' then 'OK  en curso' else 'MAL  ' || coalesce(t.clave, t.motivo) end);

  perform public.plus_alta_resultado(pago_plus, 'pendiente', 'PAY-PLUS-T1', 'ORD-PLUS-T1',
                                     'El banco está revisando el pago.');
  select * into t from public.tomar_el_cobro_plus(cli);
  insert into _r values ('03 NO se cobra de nuevo lo que el banco está revisando',
    case when t.clave is null and t.motivo = 'en_revision' then 'OK  en revisión' else 'MAL  ' || coalesce(t.clave, t.motivo) end);

  nota := public.resolver_pago_de_mp('ORD-PLUS-T1', 'PAY-PLUS-T1', 'acreditado');
  insert into _r values ('04 aprobado tarde, el mes se activa solo',
    case when nota like '%Plus quedó activo%'
              and exists (select 1 from public.suscripciones_plus where pago_id = pago_plus and hasta > public.hoy())
         then 'OK  sin que lo mire una persona' else 'MAL  ' || nota end);

  nota := public.resolver_pago_de_mp('ORD-PLUS-T1', 'PAY-PLUS-T1', 'acreditado');
  select count(*) into n from public.suscripciones_plus where cliente_id = cli;
  insert into _r values ('05 el aviso repetido no regala otro mes',
    case when n = 1 then 'OK  una sola suscripción' else format('MAL  %s suscripciones', n) end);

  select * into t from public.tomar_el_cobro_plus(cli);
  insert into _r values ('06 NO se cobra otro alta recién pagada',
    case when t.clave is null and t.motivo = 'ya_pago' then 'OK  ya pagó' else 'MAL  ' || coalesce(t.clave, t.motivo) end);

  -- Pasado un rato sí: es renovar a mano, que suma un mes.
  -- Las dos fechas: en una sola transacción `now()` no se mueve, y con el mismo
  -- `creado_en` no habría un "último pago" que mirar.
  update public.pagos
     set acreditado_en = now() - interval '20 minutes', creado_en = now() - interval '20 minutes'
   where id = pago_plus;
  select * into t from public.tomar_el_cobro_plus(cli);
  insert into _r values ('07 pasado el rato se puede volver a pagar',
    case when t.clave like 'plus-alta-%-1' and t.pago_id <> pago_plus then 'OK  pago nuevo' else 'MAL  ' || coalesce(t.clave, t.motivo) end);

  perform public.plus_alta_resultado(t.pago_id, 'rechazado', null, null, 'Fondos insuficientes');
  select * into t from public.tomar_el_cobro_plus(cli);
  insert into _r values ('08 después de un rechazo, clave nueva',
    case when t.clave like 'plus-alta-%-2' then 'OK  segundo intento' else 'MAL  ' || coalesce(t.clave, t.motivo) end);

  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  begin
    set local role authenticated;
    perform public.tomar_el_cobro_plus(cli);
    reset role;
    ok := false;
  exception when others then reset role; ok := true; end;
  insert into _r values ('09 NO un cliente toma el cobro de Plus por su cuenta',
    case when ok then 'OK (rechazado)' else 'MAL' end);

  begin
    set local role authenticated;
    perform public.plus_alta_resultado(t.pago_id, 'acreditado');
    reset role;
    ok := false;
  exception when others then reset role; ok := true; end;
  insert into _r values ('10 NO un cliente se da el alta por pagada',
    case when ok then 'OK (rechazado)' else 'MAL' end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- Los pagos en revisión se consultan sin aviso ------------------------------
  insert into public.pagos (metodo, estado, monto, mp_order_id, cobro_tomado_en, creado_en)
  values ('mercado_pago', 'pendiente', 5000, 'ORD-REV-T1', now() - interval '10 minutes', now() - interval '10 minutes')
  returning id into pago_rev;
  insert into public.pagos (metodo, estado, monto, mp_order_id, cobro_tomado_en, creado_en)
  values ('mercado_pago', 'pendiente', 5000, 'simulado-orden-T1', now() - interval '10 minutes', now() - interval '10 minutes')
  returning id into pago_sim;
  insert into public.pagos (metodo, estado, monto, mp_order_id, cobro_tomado_en, creado_en)
  values ('mercado_pago', 'pendiente', 5000, 'ORD-VIEJA-T1', now() - interval '8 days', now() - interval '8 days')
  returning id into pago_viejo;

  insert into _r values ('11 un pago en revisión sin aviso se consulta',
    case when exists (select 1 from public.pagos_por_consultar() where pago_id = pago_rev) then 'OK' else 'MAL' end);
  insert into _r values ('12 NO se consulta una orden simulada',
    case when not exists (select 1 from public.pagos_por_consultar() where pago_id = pago_sim) then 'OK' else 'MAL' end);
  insert into _r values ('13 NO se consulta pasada la semana',
    case when not exists (select 1 from public.pagos_por_consultar() where pago_id = pago_viejo) then 'OK' else 'MAL' end);

  perform public.pago_consultado(pago_rev);
  insert into _r values ('14 consultado, espera 10 minutos para la próxima',
    case when not exists (select 1 from public.pagos_por_consultar() where pago_id = pago_rev) then 'OK' else 'MAL' end);

  -- ---- Devoluciones parciales --------------------------------------------------
  insert into public.pagos (metodo, estado, monto, mp_order_id, acreditado_en)
  values ('mercado_pago', 'acreditado', 10000, 'ORD-PARC-T1', now())
  returning id into pago_parc;

  nota := public.resolver_pago_de_mp('ORD-PARC-T1', null, 'reembolsado', null, 3000);
  insert into _r values ('15 una devolución parcial no anula el pago',
    (select case when estado = 'acreditado' and monto_reembolsado = 3000 and nota like 'devolución parcial%'
                 then 'OK  sigue acreditado, $3000 devueltos' else format('MAL  %s %s', estado, monto_reembolsado) end
       from public.pagos where id = pago_parc));

  nota := public.resolver_pago_de_mp('ORD-PARC-T1', null, 'reembolsado', null, 10000);
  insert into _r values ('16 la devolución del total sí lo marca devuelto',
    (select case when estado = 'reembolsado' and monto_reembolsado = 10000
                 then 'OK' else format('MAL  %s %s', estado, monto_reembolsado) end
       from public.pagos where id = pago_parc));

  nota := public.resolver_pago_de_mp('ORD-PARC-T1', null, 'reembolsado', null, 10000);
  insert into _r values ('17 el aviso de una devolución ya asentada no cambia nada',
    case when nota = 'ya estaba devuelto' then 'OK' else 'MAL  ' || nota end);

  -- ---- Limpieza ----------------------------------------------------------------
  delete from public.suscripciones_plus where cliente_id = cli;
  delete from public.pagos where plus_cliente_id = cli or id in (pago_rev, pago_sim, pago_viejo, pago_parc);
  delete from public.clientes where id = cli;
  delete from auth.users where id = u_cli;
end $$;

select paso, resultado from _r order by paso;
