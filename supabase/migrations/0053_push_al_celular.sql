-- 0053 - La notificacion llega al celular con la app cerrada
--
-- Hasta ahora la notificacion se veia solo al abrir la app, en la campanita.
-- Sirve para el carrito abandonado (esa persona estuvo en la app hace diez
-- minutos), pero no para nada mas: al cliente dormido, que es justamente el
-- que no la abre, no le llegaba nunca.
--
-- Push de verdad lo entrega Firebase Cloud Messaging. **Firebase entra solo
-- como el cano**: los datos siguen enteros en Supabase y la app sigue leyendo
-- de aca. FCM es lo unico que puede despertar un Android con la app cerrada,
-- porque el sistema operativo mantiene una sola conexion para todas las apps.
--
-- El envio sale **por cron y no al insertar la fila**. Si el push falla (el
-- celular sin senal, el token vencido, Google caido), la fila queda pendiente y
-- se reintenta sola en la proxima vuelta. Colgado del insert, un fallo se
-- perderia sin que nadie se entere.

-- ---------------------------------------------------------------------------
-- 1. A que celular mandarle
-- ---------------------------------------------------------------------------

create table public.push_tokens (
  id        uuid primary key default gen_random_uuid(),
  perfil_id uuid not null references public.perfiles(id) on delete cascade,

  -- El token que da FCM. Es del par (celular, app): la misma persona con la app
  -- del cliente y la del rider tiene dos, y son distintos.
  token     text not null unique,
  plataforma text not null default 'android' check (plataforma in ('android','ios','web')),

  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

comment on table public.push_tokens is
  'Los celulares a los que mandarle push. Un token es del par (celular, app), no de la persona.';

create index push_tokens_perfil_idx on public.push_tokens (perfil_id);

alter table public.push_tokens enable row level security;

-- Nadie necesita leer los tokens de otro, ni siquiera la administracion: los
-- usa la Edge Function, que entra con la clave de servicio y saltea el RLS.
create policy push_tokens_los_mios on public.push_tokens
  for all to authenticated
  using (perfil_id = (select auth.uid()))
  with check (perfil_id = (select auth.uid()));

-- El token cambia solo (reinstalacion, limpieza de datos de Android). Se guarda
-- por token y no por persona: si el mismo celular devuelve uno nuevo, el viejo
-- queda y se limpia cuando FCM lo rechace.
create or replace function public.guardar_push_token(
  p_token      text,
  p_plataforma text default 'android'
)
returns void
language sql security definer set search_path = public
as $$
  insert into public.push_tokens (perfil_id, token, plataforma)
  values (auth.uid(), p_token, p_plataforma)
  on conflict (token) do update
    set perfil_id = excluded.perfil_id,
        plataforma = excluded.plataforma,
        actualizado_en = now();
$$;

-- Al cerrar sesion: si no, el que preste el celular recibe las notificaciones
-- del duenio anterior.
create or replace function public.borrar_push_token(p_token text)
returns void
language sql security definer set search_path = public
as $$
  delete from public.push_tokens where token = p_token and perfil_id = auth.uid();
$$;

revoke execute on function public.guardar_push_token(text, text) from public, anon;
revoke execute on function public.borrar_push_token(text) from public, anon;
grant execute on function public.guardar_push_token(text, text) to authenticated;
grant execute on function public.borrar_push_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Que envios ya se mandaron por push
-- ---------------------------------------------------------------------------

alter table public.notificacion_envios
  add column push_enviado_en timestamptz;

comment on column public.notificacion_envios.push_enviado_en is
  'Cuando se empujo al celular. Nulo = todavia no. No dice que haya llegado: dice que se intento.';

-- El cron lo unico que pregunta es "que quedo sin empujar".
create index notificacion_envios_push_pendiente_idx
  on public.notificacion_envios (creado_en)
  where push_enviado_en is null;

-- ---------------------------------------------------------------------------
-- 3. Empujar lo pendiente
-- ---------------------------------------------------------------------------

create or replace function public.empujar_notificaciones()
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
    raise warning 'Falta el secreto para empujar notificaciones (correr guardar_secretos.ps1)';
    return null;
  end if;

  -- Si no hay nada pendiente no se molesta a la Edge Function. Se miran solo
  -- las ultimas horas: una notificacion de anteayer que no salio ya no sirve
  -- empujarla, y ademas evita que un atasco viejo se reintente para siempre.
  if not exists (
    select 1 from public.notificacion_envios
     where push_enviado_en is null and creado_en > now() - interval '6 hours'
  ) then
    return null;
  end if;

  return net.http_post(
    url := url || '/enviar-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || clave
    ),
    body := jsonb_build_object('accion', 'pendientes'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function public.empujar_notificaciones() from public, anon, authenticated;

-- Cada minuto. El carrito abandonado tiene una ventana de 30 minutos, asi que
-- un minuto de demora no cambia nada, y agrupar evita una llamada por fila.
select cron.schedule('empujar-notificaciones', '* * * * *',
                     $$select public.empujar_notificaciones()$$)
 where not exists (select 1 from cron.job where jobname = 'empujar-notificaciones');
