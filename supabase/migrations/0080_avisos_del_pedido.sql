-- 0080 - Los avisos del pedido llegan con la app cerrada
--
-- Hasta ahora lo que pasa con un pedido (entró uno nuevo, el local lo aceptó,
-- el rider lo retiró) se enteraba solo quien tenía la app abierta: suena por
-- Realtime adentro de la app. Con la app cerrada, o con el celular del local
-- un rato en el bolsillo, el pedido nuevo no sonaba y a los 15 minutos se
-- rechazaba solo.
--
-- El push ya existía (0053) pero llevaba solo las notificaciones de la
-- campanita, que escribe la administración o dispara el reloj. Esto suma una
-- cola aparte, `avisos`, para lo que pasa con cada pedido y cada envío:
--
--   * **Aparte de la campanita a propósito.** "Tu pedido va en camino" no es un
--     mensaje para guardar: la pantalla del pedido ya lo dice. Mezclado con las
--     promociones llenaría la bandeja de cosas viejas.
--   * **Sale en el momento**, no en la próxima vuelta del cron como las
--     notificaciones: al pedido nuevo se le cuentan 15 minutos desde que entra,
--     y un minuto de demora es mucho. El cron queda de red: si el envío falló,
--     lo reintenta.
--   * **No le avisa a quien hizo el cambio.** El local que acepta no necesita
--     que le llegue "aceptaste el pedido"; el cliente que cancela, tampoco.
--   * **Vence.** Una oferta de envío que ya caducó, o "el rider está llegando"
--     media hora después, molestan más de lo que ayudan: el push no sale y FCM
--     tampoco lo entrega tarde (ttl).
--
-- Los textos y la pantalla que abre cada aviso se arman acá y no en la app,
-- para que una corrección no obligue a sacar versión. La pantalla viaja en
-- `ruta`, un campo que las versiones hasta la 1.17 no leen: esas apps navegan
-- con `pedido_id` y lo mandan a la pantalla de PAGO, así que los avisos no lo
-- llevan.

-- ---------------------------------------------------------------------------
-- 1. La cola
-- ---------------------------------------------------------------------------

create table public.avisos (
  id         uuid primary key default gen_random_uuid(),
  perfil_id  uuid not null references public.perfiles(id) on delete cascade,
  tipo       text not null,
  -- El canal de Android: con qué sonido y con qué importancia aparece.
  -- `pedidos` (timbre del local), `ofertas` (la marimba del rider), `estado`
  -- (el sonido normal del celular).
  canal      text not null default 'estado' check (canal in ('pedidos', 'ofertas', 'estado')),
  titulo     text not null,
  cuerpo     text not null,
  -- Lo que abre al tocarlo, en la app que la tenga (1.18 en adelante).
  ruta       text,
  -- Para las versiones viejas: el switch de la 1.17 entiende 'mis_pedidos'.
  destino    text,
  -- Avisos que tienen que salir una sola vez ("el rider está llegando" se
  -- evaluaría con cada posición del GPS).
  clave      text unique,
  vence_en   timestamptz not null default now() + interval '30 minutes',
  creado_en  timestamptz not null default now(),
  -- `tomado_en` lo marca la Edge Function al agarrarlo, para que dos vueltas
  -- simultáneas no lo manden dos veces; `enviado_en`, cuando salió.
  tomado_en  timestamptz,
  enviado_en timestamptz,
  intentos   smallint not null default 0
);

comment on table public.avisos is
  'Push de lo que pasa con un pedido o un envío. No se ve en la campanita: la pantalla del pedido ya lo dice.';

create index avisos_pendientes on public.avisos (creado_en) where enviado_en is null;
create index avisos_perfil_idx on public.avisos (perfil_id);

-- Solo la Edge Function (clave de servicio) la lee y la escribe.
alter table public.avisos enable row level security;

-- ---------------------------------------------------------------------------
-- 2. Mandar uno
-- ---------------------------------------------------------------------------

-- Le pide a la Edge Function que mande lo pendiente. Una vez por transacción:
-- aceptar un pedido puede generar tres avisos, y con una llamada alcanza.
-- pg_net encola el pedido y lo manda al confirmarse la transacción, así que un
-- cambio que se deshace no avisa nada.
create or replace function public.empujar_avisos()
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  url   text;
  clave text;
begin
  if current_setting('modoya.avisos_empujados', true) = 'si' then return; end if;

  select decrypted_secret into url   from vault.decrypted_secrets where name = 'url_funciones';
  select decrypted_secret into clave from vault.decrypted_secrets where name = 'clave_de_servicio';
  if url is null or clave is null then
    raise warning 'Falta el secreto para empujar avisos (correr guardar_secretos.ps1)';
    return;
  end if;

  perform net.http_post(
    url := url || '/enviar-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || clave
    ),
    body := jsonb_build_object('accion', 'avisos'),
    timeout_milliseconds := 30000
  );
  perform set_config('modoya.avisos_empujados', 'si', true);
end;
$$;

create or replace function public.avisar(
  p_perfil  uuid,
  p_tipo    text,
  p_canal   text,
  p_titulo  text,
  p_cuerpo  text,
  p_ruta    text,
  p_destino text default null,
  p_clave   text default null,
  p_dura    interval default interval '30 minutes'
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  -- Sin destinatario (un envío sin rider todavía) o el que hizo el cambio.
  if p_perfil is null or p_perfil = auth.uid() then return; end if;

  insert into public.avisos (perfil_id, tipo, canal, titulo, cuerpo, ruta, destino, clave, vence_en)
  values (p_perfil, p_tipo, p_canal, p_titulo, p_cuerpo, p_ruta, p_destino, p_clave, now() + p_dura)
  on conflict (clave) do nothing;

  if found then perform public.empujar_avisos(); end if;
end;
$$;

revoke execute on function public.empujar_avisos() from public, anon, authenticated;
revoke execute on function public.avisar(uuid, text, text, text, text, text, text, text, interval)
  from public, anon, authenticated;

-- La Edge Function toma lo pendiente de a una tanda. `skip locked` y la marca
-- de `tomado_en` hacen que dos vueltas a la vez no se repartan el mismo aviso.
-- Uno tomado hace más de dos minutos y sin enviar es de una vuelta que se cayó
-- a mitad de camino: vuelve a la cola.
create or replace function public.tomar_avisos(p_cuantos integer default 200)
returns setof public.avisos
language sql security definer set search_path = public
as $$
  update public.avisos a
     set tomado_en = now(), intentos = a.intentos + 1
   where a.id in (
     select id from public.avisos
      where enviado_en is null
        and vence_en > now()
        and intentos < 5
        and (tomado_en is null or tomado_en < now() - interval '2 minutes')
      order by creado_en
      limit p_cuantos
        for update skip locked
   )
  returning a.*;
$$;

revoke execute on function public.tomar_avisos(integer) from public, anon, authenticated;
grant execute on function public.tomar_avisos(integer) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Lo que pasa con el pedido
-- ---------------------------------------------------------------------------

create or replace function public.avisos_del_pedido()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  local_perfil  uuid;
  local_nombre  text;
  cliente_perfil uuid;
  rider_perfil  uuid;
  rider_nombre  text;
  ruta_cliente  text := '/cliente/pedidos/' || new.id;
begin
  if new.estado is not distinct from old.estado then return null; end if;

  select perfil_id, nombre into local_perfil, local_nombre
    from public.comercios where id = new.comercio_id;
  select perfil_id into cliente_perfil from public.clientes where id = new.cliente_id;
  select r.perfil_id, split_part(r.nombre, ' ', 1) into rider_perfil, rider_nombre
    from public.envios e join public.repartidores r on r.id = e.repartidor_id
   where e.id = new.envio_id;

  case new.estado
    when 'pagado' then
      perform public.avisar(local_perfil, 'pedido_nuevo', 'pedidos',
        'Pedido nuevo ' || new.codigo,
        public.pesos_legibles(new.total) || '. Tenés 15 minutos para aceptarlo.',
        '/local/pedidos', null, 'pedido_nuevo:' || new.id, interval '15 minutes');

    when 'aceptado' then
      perform public.avisar(cliente_perfil, 'pedido_aceptado', 'estado',
        local_nombre || ' aceptó tu pedido',
        'Lo están preparando. Te avisamos cuando salga.',
        ruta_cliente, 'mis_pedidos');

    when 'listo' then
      perform public.avisar(rider_perfil, 'pedido_listo', 'estado',
        'El pedido ' || new.codigo || ' está listo',
        'Pasá a retirarlo por ' || local_nombre || '.',
        '/servicio/' || new.envio_id);

    when 'en_camino' then
      perform public.avisar(cliente_perfil, 'pedido_en_camino', 'estado',
        'Tu pedido va en camino',
        coalesce(rider_nombre, 'El rider') || ' ya lo retiró de ' || local_nombre || '.',
        ruta_cliente, 'mis_pedidos');

    when 'entregado' then
      perform public.avisar(cliente_perfil, 'pedido_entregado', 'estado',
        'Pedido entregado',
        '¡Que lo disfrutes! Gracias por pedir en MODO YA.',
        ruta_cliente, 'mis_pedidos', null, interval '2 hours');

    when 'rechazado' then
      perform public.avisar(cliente_perfil, 'pedido_rechazado', 'estado',
        local_nombre || ' no pudo tomar tu pedido',
        'Te devolvemos ' || public.pesos_legibles(new.total) || ' a la tarjeta.',
        ruta_cliente, 'mis_pedidos', null, interval '2 hours');

    when 'cancelado' then
      -- Un pedido que nunca se pagó se cancela solo a los 30 minutos y no le
      -- interesa a nadie. Del pagado en adelante sí: había plata y alguien
      -- esperando.
      if old.estado not in ('carrito', 'pendiente_pago') then
        perform public.avisar(cliente_perfil, 'pedido_cancelado', 'estado',
          'Se canceló tu pedido ' || new.codigo,
          'Te devolvemos ' || public.pesos_legibles(new.total) || ' a la tarjeta.',
          ruta_cliente, 'mis_pedidos', null, interval '2 hours');
        perform public.avisar(local_perfil, 'pedido_cancelado', 'pedidos',
          'Se canceló el pedido ' || new.codigo,
          'Si lo estabas preparando, frená.',
          '/local/pedidos', null, null, interval '1 hour');
      end if;

    else
      null;
  end case;

  return null;
end;
$$;

create trigger pedidos_avisar
  after update of estado on public.pedidos
  for each row execute function public.avisos_del_pedido();

-- ---------------------------------------------------------------------------
-- 4. Lo que pasa con el envío
-- ---------------------------------------------------------------------------
--
-- El envío de un pedido ya avisa por el pedido (retirado -> en camino,
-- entregado). Acá queda lo que el pedido no cuenta: el rider que se asigna, el
-- que no aparece, y los envíos que no son de un pedido: los que el local pide
-- por su cuenta y los mandados del cliente.

create or replace function public.avisos_del_envio()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  local_perfil  uuid;
  cliente_perfil uuid;
  rider_perfil  uuid;
  rider_viejo   uuid;
  rider_nombre  text;
  ruta_local    text := '/local/envios/' || new.id;
  ruta_cliente  text := '/cliente/mandados';
  que           text;
begin
  if new.estado is not distinct from old.estado then return null; end if;

  select perfil_id into local_perfil from public.comercios where id = new.comercio_id;
  select perfil_id into cliente_perfil from public.clientes where id = new.cliente_id;
  select perfil_id, split_part(nombre, ' ', 1) into rider_perfil, rider_nombre
    from public.repartidores where id = new.repartidor_id;
  select perfil_id into rider_viejo from public.repartidores where id = old.repartidor_id;

  -- Un mandado es del cliente que lo pidió, no del local (que no hay).
  if new.cliente_id is not null and new.pedido_id is null then
    local_perfil := null;
  else
    cliente_perfil := null;
  end if;

  que := case when new.pedido_id is not null then 'el pedido' else 'el envío ' || new.codigo end;

  case new.estado
    when 'asignado' then
      perform public.avisar(local_perfil, 'rider_asignado', 'estado',
        coalesce(rider_nombre, 'Un rider') || ' va para el local',
        'Va a retirar ' || que || '.', ruta_local);
      perform public.avisar(cliente_perfil, 'rider_asignado', 'estado',
        coalesce(rider_nombre, 'Un rider') || ' va a hacer tu mandado',
        'Te avisamos cuando lo retire.', ruta_cliente);

    when 'sin_repartidor' then
      perform public.avisar(local_perfil, 'sin_rider', 'pedidos',
        'No encontramos rider para ' || que,
        'Entrá para volver a buscar o avisarle al cliente.', ruta_local);
      perform public.avisar(cliente_perfil, 'sin_rider', 'estado',
        'No encontramos rider para tu mandado',
        'Probá de nuevo en unos minutos.', ruta_cliente);

    when 'retirado' then
      perform public.avisar(cliente_perfil, 'mandado_en_camino', 'estado',
        'Tu mandado va en camino',
        coalesce(rider_nombre, 'El rider') || ' ya lo retiró.', ruta_cliente);

    when 'entregado' then
      if new.pedido_id is null then
        perform public.avisar(local_perfil, 'envio_entregado', 'estado',
          'Se entregó el envío ' || new.codigo, 'Listo, quedó en destino.', ruta_local,
          null, null, interval '2 hours');
        perform public.avisar(cliente_perfil, 'mandado_entregado', 'estado',
          'Mandado entregado', 'Listo, quedó en destino.', ruta_cliente,
          null, null, interval '2 hours');
      end if;

    when 'cancelado' then
      -- Al rider que lo tenía, para que no vaya a buscar algo que ya no existe.
      perform public.avisar(coalesce(rider_perfil, rider_viejo), 'envio_cancelado', 'estado',
        'Se canceló ' || que,
        coalesce(nullif(new.motivo_cancelacion, ''), 'No hace falta que vayas.'), '/');
      if new.pedido_id is null then
        perform public.avisar(local_perfil, 'envio_cancelado', 'estado',
          'Se canceló el envío ' || new.codigo,
          coalesce(nullif(new.motivo_cancelacion, ''), 'No hace falta que hagas nada.'), ruta_local);
        perform public.avisar(cliente_perfil, 'mandado_cancelado', 'estado',
          'Se canceló tu mandado',
          coalesce(nullif(new.motivo_cancelacion, ''), 'Si lo pagaste, te devolvemos la plata.'), ruta_cliente);
      end if;

    else
      null;
  end case;

  return null;
end;
$$;

create trigger envios_avisar
  after update of estado on public.envios
  for each row execute function public.avisos_del_envio();

-- ---------------------------------------------------------------------------
-- 5. La oferta al rider
-- ---------------------------------------------------------------------------
--
-- Dura lo que dura la oferta: una oferta vencida que llega tarde haría que el
-- rider abra la app para nada.

create or replace function public.avisos_de_la_oferta()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  rider_perfil uuid;
  env    public.envios;
  desde  text;
begin
  if new.respondida_en is not null or new.expira_en <= now() then return null; end if;

  select perfil_id into rider_perfil from public.repartidores where id = new.repartidor_id;
  select * into env from public.envios where id = new.envio_id;
  select coalesce(c.nombre, env.origen_calle) into desde
    from (select 1) x left join public.comercios c on c.id = env.comercio_id;

  perform public.avisar(rider_perfil, 'oferta', 'ofertas',
    'Te ofrecen un envío',
    'Retirás en ' || coalesce(desde, 'el local') ||
      coalesce(' · ganás ' || public.pesos_legibles(env.ganancia_repartidor), '') ||
      coalesce(' · ' || replace(round(env.distancia_km, 1)::text, '.', ',') || ' km', '') || '.',
    '/', null, 'oferta:' || new.id, new.expira_en - now());
  return null;
end;
$$;

create trigger ofertas_avisar
  after insert on public.ofertas
  for each row execute function public.avisos_de_la_oferta();

-- ---------------------------------------------------------------------------
-- 6. El rider está llegando
-- ---------------------------------------------------------------------------
--
-- Con cada posición nueva del rider se mira si el envío que lleva quedó a
-- menos de 300 m de la entrega. Una sola vez por envío (la clave): el GPS
-- manda cada pocos segundos y sin eso serían veinte avisos.

create or replace function public.avisos_del_rider_cerca()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  e record;
begin
  if new.ultima_ubicacion is null then return null; end if;

  for e in
    select en.id, en.pedido_id, en.cliente_id, ped.cliente_id as cliente_del_pedido
      from public.envios en
      left join public.pedidos ped on ped.id = en.pedido_id
     where en.repartidor_id = new.id
       and en.estado in ('retirado', 'en_camino')
       and en.destino_ubicacion is not null
       and extensions.st_dwithin(en.destino_ubicacion, new.ultima_ubicacion, 300)
       and not exists (select 1 from public.avisos a where a.clave = 'cerca:' || en.id)
  loop
    perform public.avisar(
      (select perfil_id from public.clientes where id = coalesce(e.cliente_del_pedido, e.cliente_id)),
      'rider_cerca', 'estado',
      case when e.pedido_id is not null then 'Tu pedido está llegando' else 'Tu mandado está llegando' end,
      split_part(new.nombre, ' ', 1) || ' está a menos de 300 metros.',
      case when e.pedido_id is not null then '/cliente/pedidos/' || e.pedido_id else '/cliente/mandados' end,
      case when e.pedido_id is not null then 'mis_pedidos' end,
      'cerca:' || e.id, interval '10 minutes');
  end loop;
  return null;
end;
$$;

create trigger repartidores_avisar_cerca
  after update of ultima_ubicacion on public.repartidores
  for each row
  when (new.ultima_ubicacion is distinct from old.ultima_ubicacion)
  execute function public.avisos_del_rider_cerca();

-- ---------------------------------------------------------------------------
-- 7. El reloj: el pedido por vencer y la red de reintentos
-- ---------------------------------------------------------------------------
--
-- A los 10 minutos sin respuesta, un recordatorio al local: a los 15 el pedido
-- se rechaza solo (0076) y paga la penalidad. Y si algún aviso no salió (la
-- Edge Function caída, Google caído) se vuelve a pedir el envío.

create or replace function public.avisos_del_reloj()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  p record;
begin
  for p in
    select ped.id, ped.codigo, c.perfil_id
      from public.pedidos ped join public.comercios c on c.id = ped.comercio_id
     where ped.estado = 'pagado'
       and coalesce(ped.pagado_en, ped.creado_en) < now() - interval '10 minutes'
       and coalesce(ped.pagado_en, ped.creado_en) > now() - interval '15 minutes'
  loop
    perform public.avisar(p.perfil_id, 'pedido_por_vencer', 'pedidos',
      'Te quedan 5 minutos para aceptar ' || p.codigo,
      'Si no lo aceptás, se rechaza solo y se le devuelve la plata al cliente.',
      '/local/pedidos', null, 'por_vencer:' || p.id, interval '5 minutes');
  end loop;

  if exists (
    select 1 from public.avisos
     where enviado_en is null and vence_en > now() and intentos < 5
       and (tomado_en is null or tomado_en < now() - interval '2 minutes')
  ) then
    perform public.empujar_avisos();
  end if;
end;
$$;

revoke execute on function public.avisos_del_reloj() from public, anon, authenticated;

select cron.schedule('avisos-del-reloj', '* * * * *', $$select public.avisos_del_reloj()$$)
 where not exists (select 1 from cron.job where jobname = 'avisos-del-reloj');

-- Los avisos viejos no sirven para nada: una vez por día se borran los de más
-- de una semana.
select cron.schedule('avisos-limpiar', '17 7 * * *',
  $$delete from public.avisos where creado_en < now() - interval '7 days'$$)
 where not exists (select 1 from cron.job where jobname = 'avisos-limpiar');
