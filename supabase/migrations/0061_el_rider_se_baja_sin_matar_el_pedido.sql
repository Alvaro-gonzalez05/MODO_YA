-- 0061 - Si el rider se baja, el envío vuelve a buscar; si se cancela, la plata vuelve
--
-- Dos agujeros del mismo tamaño, los dos con plata del cliente adentro.
--
-- **Uno.** `cancelar_envio` dejaba al rider entre los que podían cancelar, y un
-- envío cancelado es un estado terminal: no vuelve a `buscando_repartidor`.
-- Encima el trigger que sincroniza envío y pedido solo mira "retirado" y
-- "entregado", así que el pedido quedaba en `listo`, pago, sin envío y sin que
-- nadie lo volviera a buscar. La comida en el mostrador para siempre.
--
-- Hoy no pasaba porque la app del rider no tiene botón de cancelar, pero la
-- base se lo permitía: alcanzaba con que alguien llamara la RPC.
--
-- Ahora el rider no cancela: **se baja** (`abandonar_envio`). El envío vuelve a
-- la búsqueda y sigue su curso. Y solo puede bajarse **antes de retirar**: con
-- la comida encima ya no es un problema de asignación y lo resuelve una
-- persona.
--
-- Al que se baja no hay que excluirlo a mano: `repartidores_cercanos` ya saltea
-- a quien tuvo una oferta de ese envío.
--
-- **Dos.** Un pedido pago que se cancela no devolvía nada, aunque la pantalla
-- del cliente dijera "si ya pagaste, te devolvemos el dinero". Lo mismo que
-- pasaba al rechazar (0060), pero por el otro camino. Ahora cancelar un pedido
-- cobrado deja el reembolso del 100% pendiente. Sin penalidad al local: el
-- local no canceló nada.
--
-- Y si se cancela el envío de un pedido que sigue vivo, se cancela también el
-- pedido, que es lo que dispara esa devolución. No se hace recursión porque
-- `cancelar_pedido` marca el pedido antes de llamar acá, y acá se mira que no
-- esté ya cancelado.

create table public.abandonos_envio (
  id            uuid primary key default gen_random_uuid(),
  envio_id      uuid not null references public.envios(id) on delete cascade,
  repartidor_id uuid not null references public.repartidores(id) on delete cascade,
  motivo        text,
  -- En que estado estaba cuando se bajo: no es lo mismo plantar al local que
  -- bajarse apenas acepto.
  estado_al_bajarse public.estado_envio not null,
  creado_en     timestamptz not null default now()
);

create index abandonos_envio_rider_idx on public.abandonos_envio (repartidor_id, creado_en desc);
create index abandonos_envio_envio_idx on public.abandonos_envio (envio_id);

comment on table public.abandonos_envio is
  'Cada vez que un rider se baja de un envio que ya habia aceptado. Es el registro con el que despues se le puede cobrar.';

alter table public.abandonos_envio enable row level security;

create policy abandonos_envio_leer on public.abandonos_envio
  for select to authenticated
  using (repartidor_id = (select public.mi_repartidor_id()) or (select public.es_admin()));

-- ---------------------------------------------------------------------------
-- El rider se baja
-- ---------------------------------------------------------------------------

create or replace function public.abandonar_envio(
  p_envio  uuid,
  p_motivo text default null
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare
  e   public.envios;
  rid uuid := public.mi_repartidor_id();
begin
  if rid is null then
    raise exception 'Solo un rider puede bajarse de un envio' using errcode = '42501';
  end if;

  select * into e from public.envios where id = p_envio for update;

  if e.id is null or e.repartidor_id is distinct from rid then
    raise exception 'Ese envio no es tuyo' using errcode = 'MY004';
  end if;

  -- Con la comida encima ya no alcanza con reasignar: lo resuelve una persona.
  if e.estado not in ('asignado', 'en_local') then
    raise exception 'Ya retiraste el pedido: avisale a la administracion'
      using errcode = 'MY001';
  end if;

  insert into public.abandonos_envio (envio_id, repartidor_id, motivo, estado_al_bajarse)
  values (p_envio, rid, p_motivo, e.estado);

  update public.envios
     set estado = 'buscando_repartidor',
         repartidor_id = null,
         asignado_en = null
   where id = p_envio
  returning * into e;

  -- Las ofertas abiertas de este envio ya no valen.
  update public.ofertas set respuesta = 'expirada', respondida_en = now()
   where envio_id = p_envio and respuesta is null;

  perform public.recalcular_ocupado(rid);

  -- Que salga a buscar ya, sin esperar los 10 segundos del cron.
  perform public.ofrecer_al_siguiente(p_envio);

  return e;
end;
$$;

revoke execute on function public.abandonar_envio(uuid, text) from public, anon;
grant execute on function public.abandonar_envio(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Cancelar un envio ya no deja el pedido colgado (y el rider no cancela)
-- ---------------------------------------------------------------------------

create or replace function public.cancelar_envio(p_envio uuid, p_motivo text)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare
  e   public.envios;
  ped public.pedidos;
begin
  update public.envios
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_envio
     -- El rider sale de la lista: el que quiere bajarse usa `abandonar_envio`,
     -- que devuelve el envio a la busqueda en vez de matarlo.
     and (comercio_id = public.mi_comercio_id()
          or cliente_id = public.mi_cliente_id()
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

  -- Un pedido sin envio no llega a ningun lado: se cancela, y ahi se dispara la
  -- devolucion. Si la cancelacion vino de `cancelar_pedido`, el pedido ya esta
  -- cancelado y esto no hace nada: por eso no hay recursion.
  if e.pedido_id is not null then
    select * into ped from public.pedidos where id = e.pedido_id;
    if ped.id is not null and ped.estado not in ('cancelado', 'entregado', 'rechazado') then
      perform public.cancelar_pedido(ped.id, coalesce(p_motivo, 'Se cancelo el envio'));
    end if;
  end if;

  return e;
end;
$$;

-- ---------------------------------------------------------------------------
-- Cancelar un pedido cobrado devuelve la plata
-- ---------------------------------------------------------------------------

create or replace function public.cancelar_pedido(
  p_pedido uuid,
  p_motivo text
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
  pg  public.pagos;
begin
  update public.pedidos
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_pedido
     and (cliente_id = public.mi_cliente_id()
          or comercio_id = public.mi_comercio_id()
          or public.es_admin())
  returning * into ped;

  if ped.id is null then
    raise exception 'El pedido no existe o no podes cancelarlo'
      using errcode = '42501';
  end if;

  -- Si ya se habia cobrado, se devuelve entero. Sin penalidad al local: acá
  -- no rechazó nada (si rechazó, el camino es `rechazar_pedido`, que sí la
  -- cobra).
  select * into pg from public.pagos where id = ped.pago_id;
  if pg.id is not null and pg.estado = 'acreditado' then
    update public.pagos
       set reembolso_pedido_en = coalesce(reembolso_pedido_en, now())
     where id = pg.id;
  end if;

  if ped.envio_id is not null then
    perform public.cancelar_envio(ped.envio_id, 'Pedido cancelado');
  end if;

  return ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- La máquina de estados tiene que admitir la vuelta atrás
-- ---------------------------------------------------------------------------
--
-- `asignado` y `en_local` no podían volver a `buscando_repartidor` porque hasta
-- ahora nadie podía bajarse: el envío solo avanzaba o se cancelaba. Es el mismo
-- camino que ya existía desde `sin_repartidor`.

create or replace function public.transicion_valida(
  p_desde estado_envio,
  p_hacia estado_envio
)
returns boolean
language sql immutable
as $$
  select case p_desde
    when 'borrador'            then p_hacia in ('cotizado','cancelado')
    when 'cotizado'            then p_hacia in ('buscando_repartidor','cancelado')
    when 'buscando_repartidor' then p_hacia in ('asignado','sin_repartidor','cancelado')
    -- El rider se baja antes de retirar: vuelve a la búsqueda (0061).
    when 'asignado'            then p_hacia in ('en_local','buscando_repartidor','cancelado')
    when 'en_local'            then p_hacia in ('retirado','buscando_repartidor','cancelado')
    when 'retirado'            then p_hacia in ('en_camino','cancelado')
    when 'en_camino'           then p_hacia in ('entregado','cancelado')
    when 'sin_repartidor'      then p_hacia in ('buscando_repartidor','cancelado')
    else false
  end
$$;

alter function public.transicion_valida(estado_envio, estado_envio) set search_path = public;
