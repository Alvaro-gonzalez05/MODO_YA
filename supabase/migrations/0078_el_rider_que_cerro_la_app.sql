-- 0078 - El rider que cerró la app deja de recibir ofertas
--
-- "Conectado" era lo que el rider eligió en la app, no si la app seguía
-- viva. Si se le cerraba (se quedó sin batería, la mató el sistema, la
-- desinstaló) quedaba conectado para siempre: en la base hay un rider
-- conectado desde el 19/09 con la última posición de ese día. Las ofertas le
-- seguían llegando, y cada una esperaba a vencerse antes de pasar al
-- siguiente rider, demorando pedidos de verdad. Y la administración lo contaba
-- entre los "riders conectados".
--
-- Dos cambios:
--
--   * La oferta solo va a quien mandó su posición en los últimos 10 minutos.
--   * Cada 5 minutos se desconecta al que lleva 30 sin dar señales, salvo que
--     tenga un envío en curso: ese puede estar en una zona sin señal y no se
--     lo saca de su viaje. La app, al ver que la base lo desconectó, deja de
--     mandar la ubicación (antes seguía mandándola, y la app promete que solo
--     se comparte mientras está conectado).

-- ---------------------------------------------------------------------------
-- Quién recibe la oferta
-- ---------------------------------------------------------------------------

-- Igual que en 0077 más el filtro de la posición reciente.
create or replace function public.repartidores_cercanos(p_envio uuid)
returns table(repartidor_id uuid, distancia_km numeric)
language sql stable security definer set search_path = public, extensions
as $$
  with cand as (
    select r.id,
           r.ultima_ubicacion,
           a.activos,
           -- Ya va a este mismo local con un solo envio que todavia no retiro.
           (e.comercio_id is not null and a.activos = 1 and a.mismo_local_sin_retirar) as suma,
           exists (select 1 from public.comercio_riders cr
                    where cr.comercio_id = e.comercio_id and cr.repartidor_id = r.id) as propio,
           e.origen_ubicacion,
           t.radio_busqueda_km
      from public.envios e
      join public.tarifarios t on t.id = e.tarifario_id
      join public.repartidores r
        on r.ciudad_id = e.ciudad_id
       and r.estado_aprobacion = 'aprobado'
       and r.conectado
       and r.ultima_ubicacion is not null
       -- La app manda la posición cada 30 s aunque el rider esté quieto: diez
       -- minutos sin noticias es una app cerrada, no un rider esperando.
       and r.ultima_ubicacion_en > now() - interval '10 minutes'
      cross join lateral (
        select count(*)::integer as activos,
               coalesce(bool_and(x.comercio_id = e.comercio_id and x.estado in ('asignado', 'en_local')), false)
                 as mismo_local_sin_retirar
          from public.envios x
         where x.repartidor_id = r.id
           and x.estado in ('asignado', 'en_local', 'retirado', 'en_camino')
      ) a
     where e.id = p_envio
       and r.id is distinct from e.repartidor_id
       and not exists (
         select 1 from public.ofertas o
          where o.repartidor_id = r.id and o.respuesta is null and o.expira_en > now()
       )
       and not exists (
         select 1 from public.ofertas o
          where o.envio_id = e.id and o.repartidor_id = r.id
            and o.ofrecida_en > now() - interval '1 minute'
       )
  )
  select c.id,
         round((extensions.ST_Distance(c.ultima_ubicacion, c.origen_ubicacion) / 1000)::numeric, 2)
    from cand c
   where c.suma
      -- Libre, o con un solo envío: los dos dentro del radio (o propios del local).
      or (c.activos < 2
          and (c.propio
               or extensions.ST_DWithin(c.ultima_ubicacion, c.origen_ubicacion, c.radio_busqueda_km * 1000)))
   order by not c.suma, c.activos > 0, not c.propio, 2
$$;

-- ---------------------------------------------------------------------------
-- El que no da señales se desconecta
-- ---------------------------------------------------------------------------

create or replace function public.desconectar_riders_sin_senal()
returns integer
language sql security definer set search_path = public
as $$
  with fuera as (
    update public.repartidores r
       set conectado = false
     where r.conectado
       and (r.ultima_ubicacion_en is null or r.ultima_ubicacion_en < now() - interval '30 minutes')
       and not exists (
         select 1 from public.envios e
          where e.repartidor_id = r.id
            and e.estado in ('asignado', 'en_local', 'retirado', 'en_camino')
       )
    returning 1
  )
  select count(*)::integer from fuera;
$$;

revoke execute on function public.desconectar_riders_sin_senal() from public, anon, authenticated;

select cron.schedule('desconectar-riders-sin-senal', '*/5 * * * *',
                     $$select public.desconectar_riders_sin_senal()$$)
 where not exists (select 1 from cron.job where jobname = 'desconectar-riders-sin-senal');
