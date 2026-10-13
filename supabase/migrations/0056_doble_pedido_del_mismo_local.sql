-- 0056 - Un rider lleva dos pedidos del mismo local
--
-- Si un local tiene un pedido listo y ya hay un rider yendo a buscarle otro (o
-- esperando en la puerta), lo logico es que se lleve los dos en el mismo
-- viaje. Hasta ahora no podia: aceptar un envio lo marcaba `ocupado` y quedaba
-- afuera de la busqueda hasta entregar.
--
-- Ahora ese rider es el **primer candidato** para el segundo pedido del mismo
-- local, aunque este fuera del radio de busqueda (ya va para ahi). Las reglas:
--
--   * Como mucho dos envios a la vez.
--   * El que tiene en curso tiene que ser de ese mismo local y estar todavia
--     en `asignado` o `en_local`: si ya lo retiro, ya se fue.
--   * Los mandados no se suman: no tienen local.
--
-- Cada envio sigue siendo independiente: su codigo de entrega, sus estados y
-- su ganancia. Lo unico que cambia es quien lo recibe y cuando el rider queda
-- libre: `ocupado` pasa a ser "tiene algun envio activo", asi que entregar el
-- primero no lo libera si le queda el segundo.

-- ---------------------------------------------------------------------------
-- Ocupado = tiene algun envio activo
-- ---------------------------------------------------------------------------

create or replace function public.recalcular_ocupado(p_repartidor uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.repartidores r
     set ocupado = exists (
       select 1 from public.envios e
        where e.repartidor_id = r.id
          and e.estado in ('asignado', 'en_local', 'retirado', 'en_camino')
     )
   where r.id = p_repartidor;
$$;

revoke execute on function public.recalcular_ocupado(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Quien recibe la oferta
-- ---------------------------------------------------------------------------

create or replace function public.repartidores_cercanos(p_envio uuid)
returns table(repartidor_id uuid, distancia_km numeric)
language sql stable security definer set search_path = public, extensions
as $$
  with cand as (
    select r.id,
           r.ultima_ubicacion,
           r.ocupado,
           -- Ya va a este mismo local con un solo envio que todavia no retiro.
           (e.comercio_id is not null and r.ocupado and (
              select count(*) = 1
                     and bool_and(a.comercio_id = e.comercio_id
                                  and a.estado in ('asignado', 'en_local'))
                from public.envios a
               where a.repartidor_id = r.id
                 and a.estado in ('asignado', 'en_local', 'retirado', 'en_camino')
           )) as suma,
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
      or (not c.ocupado
          and (c.propio
               or extensions.ST_DWithin(c.ultima_ubicacion, c.origen_ubicacion, c.radio_busqueda_km * 1000)))
   order by not c.suma, not c.propio, 2
$$;

-- ---------------------------------------------------------------------------
-- Aceptar: con dos envios activos no entra un tercero
-- ---------------------------------------------------------------------------

create or replace function public.responder_oferta(p_oferta uuid, p_acepta boolean)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare
  o   public.ofertas;
  e   public.envios;
  rep uuid;
begin
  rep := public.mi_repartidor_id();

  select * into o from public.ofertas
   where id = p_oferta and repartidor_id = rep and respuesta is null
   for update;

  if o.id is null then
    raise exception 'La oferta no existe o ya fue respondida' using errcode = 'MY003';
  end if;

  if o.expira_en <= now() then
    update public.ofertas set respuesta = 'expirada', respondida_en = now()
     where id = o.id;
    perform public.ofrecer_al_siguiente(o.envio_id);
    raise exception 'La oferta vencio' using errcode = 'MY003';
  end if;

  if not p_acepta then
    update public.ofertas set respuesta = 'rechazada', respondida_en = now()
     where id = o.id;
    perform public.ofrecer_al_siguiente(o.envio_id);
    return null;
  end if;

  -- El rider se bloquea para que dos aceptaciones a la vez no le sumen tres.
  perform 1 from public.repartidores where id = rep for update;
  if (select count(*) from public.envios
       where repartidor_id = rep
         and estado in ('asignado', 'en_local', 'retirado', 'en_camino')) >= 2 then
    raise exception 'Ya llevas dos envios' using errcode = 'MY003';
  end if;

  update public.ofertas set respuesta = 'aceptada', respondida_en = now()
   where id = o.id;

  update public.envios
     set estado = 'asignado',
         repartidor_id = rep,
         codigo_entrega = lpad((floor(random() * 10000))::int::text, 4, '0')
   where id = o.envio_id
     and estado = 'buscando_repartidor'
  returning * into e;

  if e.id is null then
    raise exception 'El envio ya no estaba disponible' using errcode = 'MY003';
  end if;

  update public.repartidores set ocupado = true where id = rep;
  return e;
end;
$$;

-- ---------------------------------------------------------------------------
-- Entregar o cancelar uno no libera al rider si le queda el otro
-- ---------------------------------------------------------------------------

create or replace function public.confirmar_entrega(p_envio uuid, p_codigo text)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare
  e   public.envios;
  rep uuid;
begin
  rep := public.mi_repartidor_id();

  select * into e from public.envios
   where id = p_envio and repartidor_id = rep for update;

  if e.id is null then
    raise exception 'El envio no existe o no es tuyo' using errcode = 'MY004';
  end if;
  if e.codigo_entrega is distinct from p_codigo then
    raise exception 'El codigo de entrega no es correcto' using errcode = 'MY002';
  end if;

  update public.envios set estado = 'entregado'
   where id = p_envio returning * into e;

  update public.repartidores
     set viajes_completados = viajes_completados + 1
   where id = rep;
  perform public.recalcular_ocupado(rep);

  return e;
end;
$$;

create or replace function public.cancelar_envio(p_envio uuid, p_motivo text)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare e public.envios;
begin
  update public.envios
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_envio
     and (comercio_id = public.mi_comercio_id()
          or cliente_id = public.mi_cliente_id()
          or repartidor_id = public.mi_repartidor_id()
          or public.es_admin())
  returning * into e;

  if e.id is null then
    raise exception 'El envio no existe o no podes cancelarlo' using errcode = '42501';
  end if;

  if e.repartidor_id is not null then
    perform public.recalcular_ocupado(e.repartidor_id);
  end if;

  update public.ofertas set respuesta = 'expirada', respondida_en = now()
   where envio_id = p_envio and respuesta is null;

  return e;
end;
$$;
