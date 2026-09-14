-- 0019 - Huecos de flujo encontrados al disenar las pantallas
--
-- Ninguno era un error de seguridad; los cuatro habrian roto un flujo real.

-- ---------------------------------------------------------------------------
-- 1. El cliente no podia ver el codigo de entrega de su pedido
--
-- El codigo vive en `envios`, y el cliente no puede leer esa tabla (a
-- proposito: ahi estan los datos del rider y de la operacion). Pero en el
-- marketplace es justamente el cliente quien le dicta el codigo al rider.
--
-- En vez de abrirle `envios`, una funcion le devuelve solo lo que necesita y
-- solo de un pedido suyo.
-- ---------------------------------------------------------------------------

create or replace function public.seguimiento_de_mi_pedido(p_pedido uuid)
returns jsonb
language sql stable security definer set search_path = public, extensions
as $$
  select jsonb_build_object(
    'estado_envio',      e.estado,
    'repartidor_nombre', r.nombre,
    'vehiculo',          r.vehiculo,
    -- El codigo recien tiene sentido cuando el pedido salio del local.
    'codigo_entrega',    case when e.estado in ('retirado','en_camino') then e.codigo_entrega end,
    'minutos_estimados', e.minutos_estimados,
    'rider_lat',         case when e.estado in ('asignado','en_local','retirado','en_camino')
                              then extensions.ST_Y(r.ultima_ubicacion::extensions.geometry) end,
    'rider_lng',         case when e.estado in ('asignado','en_local','retirado','en_camino')
                              then extensions.ST_X(r.ultima_ubicacion::extensions.geometry) end
  )
  from public.pedidos p
  join public.envios e on e.id = p.envio_id
  left join public.repartidores r on r.id = e.repartidor_id
  where p.id = p_pedido
    and p.cliente_id = public.mi_cliente_id()
$$;

-- ---------------------------------------------------------------------------
-- 2 y 3. Horarios
--
-- Antes: `cierra > abre` obligatorio, asi que una pizzeria de 20:00 a 01:00 no
-- se podia cargar. Ahora, si cierra es menor que abre, el turno cruza la
-- medianoche.
--
-- Y un local sin ningun horario cargado se guia solo por su interruptor
-- `acepta_pedidos`. Sin esta regla, un local recien dado de alta figuraba
-- cerrado para siempre hasta que alguien cargara los siete dias.
-- ---------------------------------------------------------------------------

alter table public.horarios_comercio drop constraint if exists horarios_rango_valido;
alter table public.horarios_comercio
  add constraint horarios_rango_valido check (cierra <> abre);

create or replace function public.comercio_abierto(p_comercio uuid)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  c        public.comercios;
  ahora    timestamp := now() at time zone 'America/Argentina/Mendoza';
  hoy      smallint  := extract(dow from ahora);
  ayer     smallint  := (extract(dow from ahora)::int + 6) % 7;
  hora     time      := ahora::time;
begin
  select * into c from public.comercios where id = p_comercio;
  if c.id is null or c.estado_aprobacion <> 'aprobado' or not c.acepta_pedidos then
    return false;
  end if;

  if not exists (select 1 from public.horarios_comercio where comercio_id = c.id) then
    return true;
  end if;

  return exists (
    select 1 from public.horarios_comercio h
    where h.comercio_id = c.id
      and (
        -- Turno normal dentro del mismo dia.
        (h.dia = hoy and h.cierra > h.abre and hora >= h.abre and hora < h.cierra)
        -- Turno que empezo hoy y cruza la medianoche.
        or (h.dia = hoy and h.cierra < h.abre and hora >= h.abre)
        -- Turno que empezo ayer y todavia no cerro.
        or (h.dia = ayer and h.cierra < h.abre and hora < h.cierra)
      )
  );
end;
$$;

-- Carga de horarios de a un dia, reemplazando lo que hubiera.
create or replace function public.guardar_horarios(p_horarios jsonb)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  com uuid := public.mi_comercio_id();
  h   jsonb;
begin
  if com is null then
    raise exception 'Solo un comercio puede cargar horarios' using errcode = '42501';
  end if;

  delete from public.horarios_comercio where comercio_id = com;

  for h in select * from jsonb_array_elements(coalesce(p_horarios, '[]'::jsonb))
  loop
    insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
    values (com, (h->>'dia')::smallint, (h->>'abre')::time, (h->>'cierra')::time);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Vencimiento automatico de ofertas
--
-- Si el rider cierra la app sin responder, la oferta quedaba abierta para
-- siempre y el envio nunca pasaba al siguiente. vencer_ofertas() existia desde
-- 0005 pero nadie la llamaba.
-- ---------------------------------------------------------------------------

create extension if not exists pg_cron;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'vencer-ofertas') then
    perform cron.unschedule('vencer-ofertas');
  end if;
  perform cron.schedule('vencer-ofertas', '10 seconds', 'select public.vencer_ofertas()');
end $$;

-- ---------------------------------------------------------------------------
-- Pago manual mientras no haya pasarela
--
-- En 0013 marcar_pedido_pagado quedo sin grant pensando que la llamaria una
-- Edge Function. Pero hasta que se elija como se cobra, la unica forma de que
-- un pedido llegue al local es que la administracion lo marque pagado desde la
-- app. La funcion ya verifica por dentro que quien llama sea admin.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.seguimiento_de_mi_pedido(uuid),
  public.comercio_abierto(uuid),
  public.guardar_horarios(jsonb),
  public.marcar_pedido_pagado(uuid, metodo_pago, text)
to authenticated;
