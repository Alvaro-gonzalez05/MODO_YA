-- 0043 - Plus se renueva el mismo día de cada mes
--
-- Antes se sumaban 30 dias, que no es un mes: el que se suscribia un 25 de
-- enero pasaba a cobrarsele el 24 de febrero, el 26 de marzo, el 25 de abril.
-- Imposible de explicar y peor de reclamar.
--
-- Ahora se suma un mes: el que se suscribio un 25 se le cobra todos los 25.
-- Postgres ya resuelve los bordes (31 de enero + 1 mes = 28 de febrero) y, como
-- cada renovacion arranca donde termino la anterior, el dia no se corre nunca.
--
-- La suscripcion se renueva sola desde el dia uno: el cliente no tiene que
-- prender nada. Lo unico que tiene que poder hacer es darse de baja, y para eso
-- ya esta `cortar_renovacion_plus` (0041).

create or replace function public.activar_plus(
  p_cliente uuid,
  p_precio  integer,
  p_pago    uuid default null
)
returns public.suscripciones_plus
language plpgsql security definer set search_path = public
as $$
declare
  s public.suscripciones_plus;
  fin date;
begin
  -- Si ya tiene, se le suma un mes a lo que le quedaba.
  select max(hasta) into fin from public.suscripciones_plus
   where cliente_id = p_cliente and hasta >= current_date;

  insert into public.suscripciones_plus (cliente_id, desde, hasta, precio, pago_id)
  values (
    p_cliente,
    coalesce(fin, current_date),
    (coalesce(fin, current_date) + interval '1 month')::date,
    p_precio,
    p_pago
  )
  returning * into s;

  return s;
end;
$$;

revoke execute on function public.activar_plus(uuid, integer, uuid) from public, anon, authenticated;

-- Desde cuándo es Plus este cliente (la primera vez que lo pagó), para poder
-- decirle "se renueva todos los 25, como el día que te suscribiste".
create or replace function public.plus_desde()
returns date
language sql stable security definer set search_path = public
as $$
  select min(desde) from public.suscripciones_plus
   where cliente_id = public.mi_cliente_id();
$$;

revoke execute on function public.plus_desde() from public, anon;
grant execute on function public.plus_desde() to authenticated;
