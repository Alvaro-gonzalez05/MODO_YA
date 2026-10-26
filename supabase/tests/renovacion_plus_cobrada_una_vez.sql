-- La renovación de Plus se cobra una sola vez (hallazgo A2 de la auditoría 2).
--
-- Antes: si el cobro salía bien y la activación fallaba, la suscripción seguía
-- vencida y el cron la devolvía al día siguiente. Como la clave de idempotencia
-- era la misma todos los días, o se cobraba de nuevo (ventana vencida) o nunca
-- se activaba (respuesta cacheada). Y el `insert` en `pagos` descartaba su
-- error, así que el cliente podía recibir el mes sin registro del cobro.
--
-- Lo que se prueba acá es la mitad que vive en la base. La clave de
-- idempotencia por período la arma la Edge Function (`pagar-pedido`), y lo que
-- se verifica es que la base le dé el dato con el que armarla y que una
-- suscripción cobrada sin activar salga de la cola.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_a uuid := gen_random_uuid();  -- se le cobra y se activa bien
  u_b uuid := gen_random_uuid();  -- se le cobra y la activacion falla
  a uuid; b uuid;
  sus_a uuid; sus_b uuid;
  periodo_a date; periodo_b date;
  s public.suscripciones_plus;
  pg public.pagos;
  ok boolean; n integer;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','pagos-plus-a@test.local','x','{"provider":"email"}',now(),now(),now()),
    (u_b,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','pagos-plus-b@test.local','x','{"provider":"email"}',now(),now(),now());

  select id into a from public.clientes where perfil_id = u_a;
  select id into b from public.clientes where perfil_id = u_b;

  insert into public.tarjetas_guardadas
    (cliente_id, mp_card_id, marca, ultimos4, vence_mes, vence_anio, titular, predeterminada)
  values (a, 'card-pagos-a', 'visa', '4218', 12, 2030, 'PRUEBA', true),
         (b, 'card-pagos-b', 'visa', '1111', 12, 2030, 'PRUEBA', true);

  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, renovar)
  values (a, public.hoy() - 31, public.hoy() - 1, 2500, true) returning id into sus_a;
  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, renovar)
  values (b, public.hoy() - 31, public.hoy() - 1, 2500, true) returning id into sus_b;

  select hasta into periodo_a from public.suscripciones_plus where id = sus_a;
  select hasta into periodo_b from public.suscripciones_plus where id = sus_b;

  -- ---- El período con el que se arma la clave de idempotencia --------------

  insert into _r values ('01 la base da el periodo que se esta cobrando',
    case when periodo_a = public.hoy() - 1
         then format('OK  clave plus-renovacion-<sus>-%s', periodo_a)
         else format('MAL  %s', periodo_a) end);

  insert into _r values ('02 los dos estan en la cola del dia',
    case when (select count(*) from public.plus_por_renovar()
                where cliente_id in (a, b)) = 2
         then 'OK' else 'MAL' end);

  -- ---- El cobro y el mes van juntos ---------------------------------------

  s := public.plus_cobrado(a, 2500, 'PAY-PLUS-A', 'ORD-PLUS-A');
  select * into pg from public.pagos where id = s.pago_id;
  insert into _r values ('03 el mes queda atado al pago que lo pago',
    case when pg.id is not null and pg.estado = 'acreditado' and pg.monto = 2500
          and pg.mp_payment_id = 'PAY-PLUS-A' and pg.mp_order_id = 'ORD-PLUS-A'
         then format('OK  $%s con los dos ids de Mercado Pago', pg.monto)
         else 'MAL  el mes quedo sin registro del cobro' end);

  insert into _r values ('04 renovado, sale de la cola',
    case when not exists (select 1 from public.plus_por_renovar() where cliente_id = a)
         then format('OK  vence el %s', s.hasta)
         else 'MAL  manana se le cobraria de nuevo' end);

  -- El `hasta` es lo que entra en la clave de idempotencia: si avanza, la clave
  -- de mañana es otra y el mismo mes no se puede cobrar dos veces. (El `desde`
  -- arranca hoy y no el día que venció: una suscripción vencida no regala los
  -- días que estuvo caída, y eso ya era así desde 0046.)
  insert into _r values ('05 el periodo nuevo es otro, asi que la clave tambien',
    case when s.hasta > periodo_a and s.hasta > public.hoy() and s.desde = public.hoy()
         then format('OK  el periodo pasa de %s a %s', periodo_a, s.hasta)
         else format('MAL  %s -> %s', s.desde, s.hasta) end);

  -- Si la activación es la que falla, no se escribe ni el pago: la transacción
  -- es una sola. Se fuerza con un cliente que no existe.
  ok := false;
  begin
    perform public.plus_cobrado(gen_random_uuid(), 2500, 'PAY-PLUS-NADIE', null);
  exception when others then ok := true; end;
  insert into _r values ('06 si falla la activacion no queda un pago huerfano',
    case when ok and not exists (select 1 from public.pagos where mp_payment_id = 'PAY-PLUS-NADIE')
         then 'OK  o las dos cosas o ninguna'
         else 'MAL  quedo plata registrada sin mes' end);

  -- ---- Cobrada y no activada: sale de la cola -----------------------------

  perform public.plus_renovacion_trabada(sus_b, 'PAY-PLUS-B', 'activar_plus explotó');
  insert into _r values ('07 cobrada sin activar NO se vuelve a cobrar',
    case when not exists (select 1 from public.plus_por_renovar() where cliente_id = b)
         then 'OK  la mira una persona'
         else 'VULNERABLE  manana se le cobra otra vez' end);

  select * into s from public.suscripciones_plus where id = sus_b;
  insert into _r values ('08 queda el rastro del cobro que no se activo',
    case when s.cobrada_sin_activar_pago = 'PAY-PLUS-B'
          and s.ultimo_error = 'activar_plus explotó'
          and s.cobrada_sin_activar_en is not null
         then 'OK  con el id para buscarlo en Mercado Pago'
         else 'MAL  el unico rastro era un console.error' end);

  insert into _r values ('09 trabarla no le cuenta un rechazo que no existio',
    case when s.intentos_fallidos = 0
         then 'OK  la tarjeta no rebotó' else format('MAL  intentos=%s', s.intentos_fallidos) end);

  -- El resto de la cola sigue funcionando: trabar una no apaga a las demás.
  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, renovar)
  values (b, public.hoy() - 60, public.hoy() - 30, 2500, true);
  select count(*) into n from public.plus_por_renovar() where cliente_id = b;
  insert into _r values ('10 la trabada es la ultima, asi que la vieja tampoco entra',
    case when n = 0 then 'OK  solo se mira la ultima suscripcion'
         else format('MAL  entraron %s', n) end);

  -- ---- Permisos ------------------------------------------------------------

  perform set_config('request.jwt.claims', json_build_object('sub', u_a)::text, true);
  ok := false;
  begin
    set local role authenticated;
    perform public.plus_cobrado(a, 1, 'PAY-PLUS-GRATIS', null);
    reset role;
  exception when others then reset role; ok := true; end;
  insert into _r values ('11 NO un cliente se regala un mes de Plus',
    case when ok and not exists (select 1 from public.pagos where mp_payment_id = 'PAY-PLUS-GRATIS')
         then 'OK (rechazado)' else 'VULNERABLE' end);

  ok := false;
  begin
    set local role authenticated;
    perform public.plus_renovacion_trabada(sus_a, 'x', 'x');
    reset role;
  exception when others then reset role; ok := true; end;
  insert into _r values ('12 NO un cliente traba su propia renovacion',
    case when ok then 'OK (rechazado)' else 'VULNERABLE' end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza ------------------------------------------------------------
  update public.suscripciones_plus set pago_id = null where cliente_id in (a, b);
  delete from public.suscripciones_plus where cliente_id in (a, b);
  delete from public.pagos where mp_payment_id in ('PAY-PLUS-A', 'PAY-PLUS-B', 'PAY-PLUS-NADIE', 'PAY-PLUS-GRATIS');
  delete from public.tarjetas_guardadas where cliente_id in (a, b);
  delete from public.clientes where id in (a, b);
  delete from auth.users where id in (u_a, u_b);
end $$;

select paso, resultado from _r order by paso;
