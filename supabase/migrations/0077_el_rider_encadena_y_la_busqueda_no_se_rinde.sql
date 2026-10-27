-- 0077 - El rider encadena envíos y la búsqueda no se rinde
--
-- Dos cosas que pidió Carolina sobre cómo se reparte:
--
-- 1. **Un rider que ya está repartiendo puede recibir otro.** Hasta ahora, con
--    un envío en curso solo le llegaba el segundo pedido *del mismo local*
--    (0056). Uno de otro local esperaba a un rider libre aunque el ocupado
--    estuviera a dos cuadras. Ahora el que lleva uno solo también es
--    candidato, dentro del mismo radio de búsqueda y con el mismo tope de dos
--    envíos a la vez (`responder_oferta` lo sigue frenando). La app del rider
--    ya muestra la oferta encima de cualquier pantalla y lista los dos envíos
--    ("Servicio en curso · 1 de 2").
--
--    El orden: primero el que ya va a ese mismo local (se lleva los dos en un
--    viaje), después los libres y recién después los ocupados. Así un rider
--    libre no se queda mirando mientras otro acumula, y el pedido no espera a
--    que el ocupado termine lo suyo si hay alguien disponible.
--
-- 2. **La búsqueda de un pedido o un mandado no se rinde.** Desde 0029, a las 3
--    horas el envío pasaba a `sin_repartidor` y el pedido quedaba en "listo"
--    para siempre: el cliente con la plata cobrada y nadie buscándole rider.
--    Ahora los pedidos de la app y los mandados se siguen ofreciendo hasta que
--    alguien acepte o se cancele.
--
--    El tope de 3 horas queda solo para los envíos que pide el local para su
--    propio reparto (cadetería), que es para lo que se puso: si el local se
--    olvidó de cancelarlo, no puede sonarle a los riders para siempre. El
--    local lo relanza desde su pantalla.

-- ---------------------------------------------------------------------------
-- Quién recibe la oferta
-- ---------------------------------------------------------------------------

-- Misma firma y mismos filtros que en 0056; cambia quién entra y el orden.
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
-- La búsqueda
-- ---------------------------------------------------------------------------

-- Igual que en 0029 salvo el tope de 3 horas, que ahora es solo para la
-- cadetería del local (tiene local y no viene de un pedido de la app).
create or replace function public.vencer_ofertas()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  o public.ofertas;
  e record;
  n integer := 0;
begin
  for o in
    select * from public.ofertas
     where respuesta is null and expira_en <= now()
  loop
    update public.ofertas set respuesta = 'expirada', respondida_en = now()
     where id = o.id;
    n := n + 1;
  end loop;

  update public.envios set estado = 'sin_repartidor'
   where estado = 'buscando_repartidor'
     and comercio_id is not null
     and pedido_id is null
     and creado_en < now() - interval '3 hours'
     and not exists (
       -- "ab" y no "o": o es la variable del primer loop.
       select 1 from public.ofertas ab
       where ab.envio_id = envios.id and ab.respuesta is null and ab.expira_en > now()
     );

  -- Solo los que estan buscando: los `sin_repartidor` los relanza el local.
  for e in
    select id from public.envios
     where estado = 'buscando_repartidor'
     order by creado_en
  loop
    perform public.ofrecer_al_siguiente(e.id);
  end loop;

  return n;
end;
$$;
