-- 0079 - No se cancela lo que ya salió
--
-- Dos funciones que cancelaban en cualquier estado. La app escondía el botón,
-- pero la base lo dejaba igual: cualquiera con la sesión abierta podía llamar
-- a la RPC directo.
--
--   * `cancelar_envio`: el local o el cliente podían cancelar un envío con el
--     paquete ya en la mano del rider (`retirado`, `en_camino`). En un pedido
--     de la app eso arrastra a `cancelar_pedido` y le devuelve todo al
--     cliente con la comida ya en camino; en un mandado el rider hizo el viaje
--     y no cobra. La pantalla del local mostraba "Cancelar envío" en
--     `retirado` (solo lo escondía en `en_camino`) y la de mandados del
--     cliente en cualquier estado no final.
--
--   * `cancelar_pedido`: el cliente podía cancelar un pedido aceptado, en
--     preparación o listo, y se le devolvía el 100% sin penalidad a nadie. La
--     pantalla del cliente solo ofrece cancelar en `pendiente_pago` y
--     `pagado`; ahora la base dice lo mismo.
--
-- La administración sigue pudiendo cancelar en cualquier estado no final: es
-- la salida cuando un rider se queda sin batería con el pedido encima.

create or replace function public.cancelar_envio(p_envio uuid, p_motivo text)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare
  e   public.envios;
  ped public.pedidos;
begin
  select * into e from public.envios where id = p_envio;

  -- El coalesce no es decorativo: en un mandado `comercio_id` es null y la
  -- comparación da null, no falso. Sin él, `not (null or false)` es null, el
  -- `if` no entra y cualquiera podía cancelar el mandado de otro. La versión
  -- de 0061 filtraba en el `where`, donde null cuenta como falso.
  if e.id is null
     or not coalesce(e.comercio_id = public.mi_comercio_id()
                     or e.cliente_id = public.mi_cliente_id()
                     or public.es_admin(), false) then
    raise exception 'El envio no existe o no podes cancelarlo' using errcode = '42501';
  end if;

  -- Con el paquete encima del rider ya no es una cancelación: es un reclamo.
  if e.estado in ('retirado', 'en_camino') and not public.es_admin() then
    raise exception 'El rider ya lo retiro: no se puede cancelar. Si hubo un problema, abri un reclamo.'
      using errcode = 'MY001';
  end if;

  update public.envios
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_envio
  returning * into e;

  if e.repartidor_id is not null then
    perform public.recalcular_ocupado(e.repartidor_id);
  end if;

  update public.ofertas set respuesta = 'expirada', respondida_en = now()
   where envio_id = p_envio and respuesta is null;

  -- Igual que en 0061: un pedido sin envío no llega a ningún lado.
  if e.pedido_id is not null then
    select * into ped from public.pedidos where id = e.pedido_id;
    if ped.id is not null and ped.estado not in ('cancelado', 'entregado', 'rechazado') then
      perform public.cancelar_pedido(ped.id, coalesce(p_motivo, 'Se cancelo el envio'));
    end if;
  end if;

  return e;
end;
$$;

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
  select * into ped from public.pedidos where id = p_pedido;

  -- Mismo coalesce que en `cancelar_envio`: para un cliente
  -- `mi_comercio_id()` es null y sin él pasaba cualquiera.
  if ped.id is null
     or not coalesce(ped.cliente_id = public.mi_cliente_id()
                     or ped.comercio_id = public.mi_comercio_id()
                     or public.es_admin(), false) then
    raise exception 'El pedido no existe o no podes cancelarlo' using errcode = '42501';
  end if;

  -- El cliente cancela mientras el local no lo tomó. Después ya hay comida
  -- hecha: lo que corresponde es hablar con el local o abrir un reclamo.
  if coalesce(ped.cliente_id = public.mi_cliente_id(), false)
     and not public.es_admin()
     and ped.comercio_id is distinct from public.mi_comercio_id()
     and ped.estado not in ('carrito', 'pendiente_pago', 'pagado') then
    raise exception 'El local ya lo acepto: no se puede cancelar. Si hubo un problema, abri un reclamo.'
      using errcode = 'MY001';
  end if;

  update public.pedidos
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_pedido
  returning * into ped;

  -- Si ya se habia cobrado, se devuelve entero (0061).
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
