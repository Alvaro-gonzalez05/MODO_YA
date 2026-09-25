-- 0041 - MODO YA Plus se renueva solo
--
-- Hasta ahora Plus duraba 30 dias y se apagaba: el cliente tenia que volver a
-- cargar la tarjeta. Ahora se renueva solo con la tarjeta que dejo guardada, y
-- lo puede cortar cuando quiera desde la pantalla de Plus.
--
-- Como el cobro necesita el access token de Mercado Pago, la renovacion la
-- hace la Edge Function `pagar-pedido` (accion `renovar_plus`). Este archivo
-- pone lo que va del lado de la base:
--
--   * a quien hay que cobrarle hoy          -> plus_por_renovar()
--   * que hacer si la tarjeta rebota        -> plus_renovacion_fallo()
--   * el interruptor del cliente            -> cortar_renovacion_plus()
--   * el disparador diario                  -> cron "renovar-plus", que llama
--     a la Edge Function con pg_net y la clave guardada en Vault.
--
-- Si la tarjeta rebota tres veces, se deja de intentar: el cliente renueva a
-- mano. No se le cobra de mas ni se le insiste para siempre.

create extension if not exists pg_net with schema extensions;

alter table public.suscripciones_plus
  add column intentos_fallidos smallint not null default 0 check (intentos_fallidos >= 0),
  add column ultimo_error text;

comment on column public.suscripciones_plus.renovar is
  'Si el cliente quiere que se le vuelva a cobrar al vencerse. Lo corta el desde la app.';

-- ---------------------------------------------------------------------------
-- A quien hay que cobrarle hoy
-- ---------------------------------------------------------------------------

-- La ultima suscripcion de cada cliente que ya se vencio (o se vence hoy), que
-- pidio renovarse y tiene una tarjeta guardada con la cual cobrarle.
create or replace function public.plus_por_renovar()
returns table (
  suscripcion_id uuid,
  cliente_id     uuid,
  mp_card_id     text,
  precio         integer
)
language sql stable security definer set search_path = public
as $$
  select s.id, s.cliente_id, t.mp_card_id, public.precio_plus()
    from public.suscripciones_plus s
    join lateral (
      select g.mp_card_id
        from public.tarjetas_guardadas g
       where g.cliente_id = s.cliente_id
       order by g.predeterminada desc, g.creado_en desc
       limit 1
    ) t on true
   where s.renovar
     and s.intentos_fallidos < 3
     and s.hasta <= current_date
     -- Solo la ultima: si ya se renovo, la vieja no se vuelve a cobrar.
     and s.hasta = (
       select max(x.hasta) from public.suscripciones_plus x where x.cliente_id = s.cliente_id
     );
$$;

-- La tarjeta rebotó: se anota y, al tercer intento, se deja de insistir.
create or replace function public.plus_renovacion_fallo(
  p_suscripcion uuid,
  p_error       text
)
returns void
language sql security definer set search_path = public
as $$
  update public.suscripciones_plus
     set intentos_fallidos = intentos_fallidos + 1,
         ultimo_error = p_error
   where id = p_suscripcion;
$$;

-- ---------------------------------------------------------------------------
-- El interruptor del cliente
-- ---------------------------------------------------------------------------

create or replace function public.cortar_renovacion_plus(p_renovar boolean)
returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  cli uuid := public.mi_cliente_id();
begin
  if cli is null then
    raise exception 'Solo un cliente puede cambiar su suscripcion' using errcode = '42501';
  end if;

  update public.suscripciones_plus
     set renovar = p_renovar,
         -- Si la vuelve a prender, se le da otra chance a la tarjeta.
         intentos_fallidos = case when p_renovar then 0 else intentos_fallidos end,
         ultimo_error = case when p_renovar then null else ultimo_error end
   where cliente_id = cli
     and hasta = (select max(x.hasta) from public.suscripciones_plus x where x.cliente_id = cli);

  return p_renovar;
end;
$$;

revoke execute on function public.plus_por_renovar() from public, anon, authenticated;
revoke execute on function public.plus_renovacion_fallo(uuid, text) from public, anon, authenticated;
revoke execute on function public.cortar_renovacion_plus(boolean) from public, anon;
grant execute on function public.cortar_renovacion_plus(boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- El disparador diario
-- ---------------------------------------------------------------------------

-- Llama a la Edge Function que cobra. La URL y la clave de servicio salen de
-- Vault: no viven en el codigo ni en esta migracion.
-- Las carga `supabase/scripts/guardar_secretos.ps1`.
create or replace function public.renovar_plus_del_dia()
returns bigint
language plpgsql security definer set search_path = public, extensions
as $$
declare
  url   text;
  clave text;
begin
  select decrypted_secret into url   from vault.decrypted_secrets where name = 'url_funciones';
  select decrypted_secret into clave from vault.decrypted_secrets where name = 'clave_de_servicio';

  if url is null or clave is null then
    raise warning 'Falta el secreto para renovar Plus (correr guardar_secretos.ps1)';
    return null;
  end if;

  -- Si hoy no hay nadie por renovar, no se molesta a la Edge Function.
  if not exists (select 1 from public.plus_por_renovar()) then
    return null;
  end if;

  return net.http_post(
    url := url || '/pagar-pedido',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || clave
    ),
    body := jsonb_build_object('accion', 'renovar_plus'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function public.renovar_plus_del_dia() from public, anon, authenticated;

-- 04:10 de Argentina = 07:10 UTC. Despues de la publicidad del dia (03:05) y
-- lejos de las horas de pedidos.
select cron.schedule('renovar-plus', '10 7 * * *', $$select public.renovar_plus_del_dia()$$);
