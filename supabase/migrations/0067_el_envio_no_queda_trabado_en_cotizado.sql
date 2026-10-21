-- 0067 - Un envío de cadetería no queda trabado en `cotizado`
--
-- La app pedía un envío con dos RPC seguidas y sin transacción: `crear_envio`
-- (que nace en `cotizado`) y `confirmar_envio` (que lo pone a buscar rider).
-- Si la segunda no llegaba — se cortó el wifi justo ahí, la app se cerró — el
-- envío quedaba en `cotizado` para siempre: ninguna acción lo confirmaba, el
-- seguimiento no decía nada y el filtro "En curso" lo escondía. Y el local,
-- que vio un error, casi seguro volvió a pedirlo: el que quedó es basura que
-- igual le aparece en la lista.
--
-- Tres cosas, en este orden:
--
-- **Uno, que no vuelva a pasar.** `pedir_envio` hace las dos cosas en una sola
-- llamada, así que o se crea y sale a buscar, o no se crea nada. Es lo que ya
-- hacía `crear_mandado` (0052) por la misma razón. Las dos funciones viejas
-- quedan como están: una app instalada sin actualizar las sigue llamando.
--
-- **Dos, limpiar lo que ya quedó trabado.** Un cron cada 5 minutos cancela los
-- envíos de cadetería que llevan más de 15 minutos en `cotizado`. Se cancelan
-- y no se confirman solos a propósito: confirmar sería mandarle un rider al
-- local por un viaje que el local no sabe que existe (vio un error) y que
-- alguien va a tener que pagar. Cancelar no le cuesta nada a nadie, y si el
-- viaje todavía hace falta el local lo pide de nuevo en diez segundos.
--
-- **Tres, que el local tenga la salida a mano** mientras el cron no corrió:
-- eso es la pantalla de seguimiento, que ahora ofrece "Buscar rider ahora".
--
-- Ojo con el envío de un pedido de la app: ese espera en `cotizado` **a
-- propósito** desde que el local acepta el pedido hasta que lo marca listo
-- (`avanzar_pedido`, 0013), y pueden ser cuarenta minutos de cocina. Por eso el
-- cron mira solo los de cadetería (`pedido_id is null`): cancelar los otros
-- sería matar pedidos pagos que están en el horno.

-- ---------------------------------------------------------------------------
-- Uno: pedirlo en una sola llamada
-- ---------------------------------------------------------------------------
--
-- No duplica nada de la lógica: llama a las dos que ya estaban. Al ser una
-- sola función es una sola transacción, y si `confirmar_envio` falla no queda
-- la fila a medio confirmar.

create or replace function public.pedir_envio(
  p_destino_calle        text,
  p_destino_lat          double precision,
  p_destino_lng          double precision,
  p_cliente_nombre       text,
  p_cliente_telefono     text,
  p_paga                 quien_paga,
  p_destino_referencia   text default null,
  p_cliente_indicaciones text default null
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare nuevo public.envios;
begin
  nuevo := public.crear_envio(
    p_destino_calle, p_destino_lat, p_destino_lng,
    p_cliente_nombre, p_cliente_telefono, p_paga,
    p_destino_referencia, p_cliente_indicaciones
  );
  return public.confirmar_envio(nuevo.id);
end;
$$;

comment on function public.pedir_envio(text, double precision, double precision, text, text, quien_paga, text, text) is
  'Crea el envio de cadeteria y arranca la busqueda de rider en una sola transaccion, para que no pueda quedar en cotizado.';

revoke execute on function public.pedir_envio(
  text, double precision, double precision, text, text, quien_paga, text, text
) from public, anon;
grant execute on function public.pedir_envio(
  text, double precision, double precision, text, text, quien_paga, text, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- Dos: vencer los que ya quedaron trabados
-- ---------------------------------------------------------------------------

create or replace function public.vencer_envios_cotizados()
returns integer
language plpgsql security definer set search_path = public
as $$
declare n integer;
begin
  with vencidos as (
    update public.envios
       set estado = 'cancelado',
           motivo_cancelacion = 'No se llegó a confirmar la búsqueda de rider'
     where estado = 'cotizado'
       -- Solo cadeteria. El envio de un pedido de la app espera en `cotizado`
       -- mientras la cocina prepara, y lo saca a buscar `avanzar_pedido`
       -- cuando el pedido queda listo: cancelarlo aca seria matar un pedido
       -- pago que esta en el horno.
       and pedido_id is null
       and comercio_id is not null
       -- `crear_envio` y `confirmar_envio` pasan en el mismo segundo: 15
       -- minutos es tiempo de sobra para no competir con nada.
       and creado_en < now() - interval '15 minutes'
    returning id
  )
  select count(*) into n from vencidos;
  return n;
end;
$$;

comment on function public.vencer_envios_cotizados() is
  'Cancela los envios de cadeteria que quedaron en cotizado porque no llego la confirmacion. Corre cada 5 minutos.';

-- La llama el cron, nadie mas: cancela envios de cualquier local.
revoke execute on function public.vencer_envios_cotizados() from public, anon, authenticated;

select cron.schedule('vencer-cotizados', '*/5 * * * *', $$select public.vencer_envios_cotizados()$$)
 where not exists (select 1 from cron.job where jobname = 'vencer-cotizados');
