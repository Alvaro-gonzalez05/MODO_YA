-- 0076 - El pedido que el local no acepta no queda trabado
--
-- Un pedido pagado con tarjeta queda en `pagado` hasta que el local lo acepta
-- o lo rechaza. Si el local no hace ninguna de las dos cosas (cerró la app, se
-- quedó sin internet, no lo vio) el pedido quedaba así para siempre: el
-- cliente con la plata cobrada mirando "Esperando que el local lo acepte", y
-- ningún proceso que se la devolviera. Se vio con un pedido de prueba que pasó
-- doce horas en ese estado.
--
-- Ahora, a los 15 minutos sin respuesta el pedido se da por rechazado y se
-- devuelve igual que cuando el local aprieta "Rechazar" (0060): el 100% al
-- cliente y la misma penalidad al local. Con la misma penalidad a propósito:
-- si no responder saliera gratis, dejar sonar el pedido sería más barato que
-- rechazarlo. Si fue un corte de luz, la administración borra el cargo desde
-- la liquidación antes de cerrarla.
--
-- La devolución y la penalidad pasan a una sola función que usan las dos
-- puntas, para que no se separen con el tiempo.

-- ---------------------------------------------------------------------------
-- pct_legible() de 0075 se comía los ceros de un entero
-- ---------------------------------------------------------------------------

-- Sacaba los ceros de la derecha siempre, así que 50 quedaba "5%". Con la
-- comisión no se notaba porque viene como numeric(5,2) ("10.00"); la
-- penalidad es un smallint. Ahora solo los saca si hay decimales.
create or replace function public.pct_legible(p numeric)
returns text
language sql immutable set search_path = public
as $$
  select case when position('.' in p::text) > 0
              then replace(rtrim(rtrim(p::text, '0'), '.'), '.', ',')
              else p::text
         end || '%';
$$;

-- ---------------------------------------------------------------------------
-- Lo que pasa cuando un pedido pagado no se hace
-- ---------------------------------------------------------------------------

create or replace function public.devolver_pedido_rechazado(
  p_pedido  public.pedidos,
  p_detalle text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  pg public.pagos;
  pct smallint;
  penalidad integer;
begin
  select * into pg from public.pagos where id = p_pedido.pago_id;

  -- Solo hay plata que devolver si entro de verdad. Un pedido que todavia
  -- estaba por cobrarse no deja nada pendiente.
  if pg.id is null or pg.estado <> 'acreditado' then
    return;
  end if;

  update public.pagos
     set reembolso_pedido_en = coalesce(reembolso_pedido_en, now())
   where id = pg.id;

  -- El tarifario de delivery de la ciudad del pedido. Antes se tomaba el
  -- último vigente de cualquier servicio, que podía ser el de mandados.
  pct := (public.tarifario_vigente(p_pedido.ciudad_id, 'delivery')).penalidad_rechazo_pct;

  -- Sobre lo que el local hubiera cobrado (los productos), no sobre el
  -- envio: el envio es de MODO YA y ademas no se hizo.
  penalidad := round(p_pedido.subtotal * coalesce(pct, 50) / 100.0);

  if penalidad > 0 then
    -- "(50% de $19.600)" y no "(50% de 19600)": es un renglón que lee el local.
    insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, fecha, pedido_id)
    values (
      p_pedido.comercio_id, 'ajuste',
      format('%s (%s de %s)', p_detalle, public.pct_legible(coalesce(pct, 50)), public.pesos_legibles(p_pedido.subtotal)),
      penalidad, public.hoy(), p_pedido.id
    );
  end if;
end;
$$;

revoke execute on function public.devolver_pedido_rechazado(public.pedidos, text) from public, anon, authenticated;

-- Misma firma y mismo comportamiento que en 0060; solo delega la devolución.
create or replace function public.rechazar_pedido(
  p_pedido uuid,
  p_motivo text
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
begin
  update public.pedidos
     set estado = 'rechazado', motivo_rechazo = p_motivo
   where id = p_pedido
     and comercio_id = public.mi_comercio_id()
     and estado = 'pagado'
  returning * into ped;

  if ped.id is null then
    raise exception 'El pedido no existe o ya no se puede rechazar'
      using errcode = 'MY004';
  end if;

  perform public.devolver_pedido_rechazado(ped, format('Penalidad por rechazar el pedido %s', ped.codigo));
  return ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- El vencimiento
-- ---------------------------------------------------------------------------

create index if not exists pedidos_esperando_al_local
  on public.pedidos (pagado_en) where estado = 'pagado';

-- Devuelve cuántos venció, para verlo en el historial del cron.
create or replace function public.vencer_pedidos_sin_aceptar()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
  n integer := 0;
begin
  -- `pagado_en` lo pone el trigger al pasar a pagado; el coalesce cubre un
  -- pedido que se haya insertado ya pagado.
  for ped in
    update public.pedidos
       set estado = 'rechazado',
           motivo_rechazo = 'El local no respondió a tiempo. Te devolvemos todo lo que pagaste.'
     where estado = 'pagado'
       and coalesce(pagado_en, creado_en) < now() - interval '15 minutes'
    returning *
  loop
    perform public.devolver_pedido_rechazado(ped, format('Penalidad por no responder el pedido %s', ped.codigo));
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke execute on function public.vencer_pedidos_sin_aceptar() from public, anon, authenticated;

-- Cada minuto: el cliente no tiene que esperar más de 16 minutos en el peor caso.
select cron.schedule('vencer-pedidos-sin-aceptar', '* * * * *',
                     $$select public.vencer_pedidos_sin_aceptar()$$)
 where not exists (select 1 from cron.job where jobname = 'vencer-pedidos-sin-aceptar');
