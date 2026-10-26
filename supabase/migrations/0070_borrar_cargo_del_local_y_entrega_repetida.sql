-- 0070 - Dos agujeros chicos: el cargo del local y la entrega repetida
--
-- Los dos son el mismo tipo de error: una regla que existe para los riders y
-- no para los locales, y una validación que se dio por hecha porque "la hace
-- el trigger". Ninguno hizo daño todavía; los dos dejan la plata o el historial
-- diciendo algo que no pasó.
--
-- Todo aditivo: la función de entrega se reemplaza conservando la firma
-- (`confirmar_entrega(uuid, text)`), así que los grants de 0006/0008/0014 y
-- quien la llame siguen igual.

-- ---------------------------------------------------------------------------
-- 1. Borrar un cargo de un local, con el mismo guard que el del rider
-- ---------------------------------------------------------------------------
--
-- `admin_borrar_cargo_rider` (0062) exige `liquidacion_id is null` **en la
-- base**. Para los locales el borrado iba derecho a la tabla desde la app y lo
-- único que lo frenaba era que la pantalla escondiera el botón. La lista es un
-- stream en vivo: si la liquidación se cierra desde otro dispositivo justo
-- antes de que llegue el evento, el botón sigue dibujado y el toque borra un
-- renglón que ya está adentro de una liquidación cerrada. Los totales
-- guardados (`liquidaciones_comercio.cargos`) no se recalculan, así que al
-- local le queda un descuento cobrado sin la línea que lo explica.
--
-- Para corregir un cargo ya liquidado está el camino que el esquema previó
-- desde 0035: cargar otro con monto negativo, que se lo devuelve sin borrar el
-- historial.

create or replace function public.admin_borrar_cargo_comercio(p_cargo uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion' using errcode = '42501';
  end if;

  delete from public.cargos_comercio
   where id = p_cargo and liquidacion_id is null;

  if not found then
    raise exception 'Ese cargo ya está liquidado: cargale uno negativo para devolvérselo'
      using errcode = 'MY004';
  end if;
end;
$$;

revoke execute on function public.admin_borrar_cargo_comercio(uuid) from public, anon;
grant execute on function public.admin_borrar_cargo_comercio(uuid) to authenticated;

comment on function public.admin_borrar_cargo_comercio(uuid) is
  'Borra un cargo de un local solo si todavia no entro en una liquidacion cerrada.';

-- ---------------------------------------------------------------------------
-- 2. Confirmar la entrega dos veces no suma dos viajes
-- ---------------------------------------------------------------------------
--
-- `confirmar_entrega` chequeaba dos cosas: que el envío sea del rider y que el
-- código de 4 dígitos coincida. El estado lo daba por validado el trigger
-- `registrar_cambio_estado`, pero ese trigger arranca con
-- `new.estado is distinct from old.estado`: si el envío **ya está**
-- `entregado`, el update de `entregado` a `entregado` no cambia nada, el
-- trigger no mira la transición, no asienta evento, y el `update
-- repartidores set viajes_completados = viajes_completados + 1` de abajo
-- corre igual. Dos toques del botón = dos viajes y un solo envío.
--
-- No hay nada que arreglar en el trigger: su condición es correcta (solo tiene
-- sentido auditar un cambio de estado). Lo que faltaba era que la función
-- mirara el estado antes de escribir.
--
-- El chequeo se hace contra `transicion_valida` y no contra `'en_camino'`
-- escrito a mano, para que el día que la máquina de estados cambie no queden
-- dos verdades. El `for update` de arriba ya serializaba dos llamadas
-- simultáneas: la segunda espera, lee `entregado` y ahora rebota.

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

  -- Antes del código: si ya lo entregó, el código es el correcto y decirle
  -- "código incorrecto" lo manda a buscar un problema que no existe.
  if e.estado = 'entregado' then
    raise exception 'Este envío ya estaba entregado' using errcode = 'MY006';
  end if;
  if not public.transicion_valida(e.estado, 'entregado') then
    raise exception 'El envío está en "%" y todavía no se puede cerrar', e.estado
      using errcode = 'MY001';
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
