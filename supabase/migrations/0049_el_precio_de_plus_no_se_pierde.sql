-- 0049 - Guardar las tarifas dejaba de cobrar el precio real de Plus
--
-- `admin_nuevo_tarifario` cierra el tarifario vigente y abre uno nuevo con las
-- columnas nombradas una por una. `precio_plus_mensual` se agrego despues
-- (0036) y nunca se sumo a ese insert, asi que el tarifario nuevo nacia con el
-- default de la columna: 2500.
--
-- O sea: se ponia Plus a $4.000, el cliente lo veia a $4.000, y la primera vez
-- que la administracion tocaba cualquier otra tarifa y guardaba, Plus volvia a
-- $2.500 sin que nadie lo pidiera ni se enterara. `precio_plus()` lee ese
-- campo del tarifario vigente, y es lo que el cliente paga.
--
-- Ahora el parametro existe, y **si no viene se conserva el que estaba**. Esa
-- es la parte que importa: el bug no fue mandar un valor equivocado, fue no
-- mandar ninguno. Con un `coalesce` contra el tarifario que se cierra, una app
-- vieja que no conozca el parametro deja de romperlo.
--
-- Encontrado leyendo el codigo, en docs/hallazgos-de-la-revision.md (hallazgo 4).

create or replace function public.admin_nuevo_tarifario(
  p_ciudad                   uuid,
  p_ganancia_repartidor_base integer,
  p_comision_modo_ya         integer,
  p_precio_km_adicional      integer,
  p_km_incluidos             numeric,
  p_radio_busqueda_km        numeric,
  p_segundos_para_aceptar    integer,
  p_precio_suscripcion_mensual integer default null,
  p_servicio                 tipo_servicio default 'delivery',
  p_precio_plus_mensual      integer default null
)
returns public.tarifarios
language plpgsql security definer set search_path = public
as $$
declare
  t      public.tarifarios;
  previo public.tarifarios;
begin
  perform public.exigir_admin();

  -- Se lee antes de cerrarlo: de ahi sale lo que no vino por parametro.
  select * into previo from public.tarifarios
   where ciudad_id = p_ciudad and servicio = p_servicio and vigente_hasta is null;

  update public.tarifarios set vigente_hasta = now()
   where ciudad_id = p_ciudad and servicio = p_servicio and vigente_hasta is null;

  insert into public.tarifarios (
    ciudad_id, servicio, ganancia_repartidor_base, comision_modo_ya,
    precio_km_adicional, km_incluidos, radio_busqueda_km, segundos_para_aceptar,
    precio_suscripcion_mensual, precio_plus_mensual, creado_por
  ) values (
    p_ciudad, p_servicio, p_ganancia_repartidor_base, p_comision_modo_ya,
    p_precio_km_adicional, p_km_incluidos, p_radio_busqueda_km, p_segundos_para_aceptar,
    p_precio_suscripcion_mensual,
    coalesce(p_precio_plus_mensual, previo.precio_plus_mensual, 2500),
    auth.uid()
  ) returning * into t;

  return t;
end;
$$;

-- La firma cambio (un parametro mas al final), asi que hay que repetir los
-- permisos: la version vieja sigue existiendo hasta que se la borre.
drop function if exists public.admin_nuevo_tarifario(
  uuid, integer, integer, integer, numeric, numeric, integer, integer, tipo_servicio);

revoke execute on function public.admin_nuevo_tarifario(
  uuid, integer, integer, integer, numeric, numeric, integer, integer, tipo_servicio, integer)
  from public, anon;
grant execute on function public.admin_nuevo_tarifario(
  uuid, integer, integer, integer, numeric, numeric, integer, integer, tipo_servicio, integer)
  to authenticated;
