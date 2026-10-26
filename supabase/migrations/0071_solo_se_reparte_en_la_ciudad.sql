-- 0071 - Solo se reparte dentro de la ciudad
--
-- `zonas` existe desde 0001 con el comentario "permiten rechazar un destino
-- fuera del área de reparto", y `ciudades.radio_km` desde el mismo día, pero
-- nada los miraba: el selector de la app arranca en el centro de Malargüe y
-- deja arrastrar el pin a cualquier lugar del mundo. Un cliente podía guardar
-- una dirección en Mendoza capital, cotizar un envío de 180 km y pagarlo, y el
-- motor le ofrecía ese viaje a un rider de Malargüe.
--
-- La regla tiene dos niveles, para no inventar un polígono que nadie dibujó:
--
--   * si la ciudad tiene **zonas activas**, el punto tiene que caer adentro de
--     alguna. Es lo que va a querer la administración cuando sepa exactamente
--     hasta dónde llegan los riders;
--   * si no tiene ninguna, alcanza con estar a menos de `radio_km` del centro
--     (15 km para Malargüe, el valor de la semilla). Deja afuera Las Leñas, El
--     Sosneado y cualquier pin mal puesto, y no corta ningún barrio.
--
-- Dónde se exige:
--
--   * en `cotizar()`, origen y destino. Es la única función por la que pasan
--     todas las cotizaciones —cadetería, pedido del marketplace, mandado—, así
--     que una dirección de afuera no puede llegar a convertirse en un envío
--     por ningún camino;
--   * al guardar una dirección del cliente y al ubicar un local, con triggers:
--     el cliente se entera cuando pone el pin, y no recién en el carrito.
--
-- Las filas que ya existen no se tocan: se revisó que ninguna dirección, local
-- ni envío de la base esté a más de 15 km del centro.

-- ---------------------------------------------------------------------------
-- La regla
-- ---------------------------------------------------------------------------

create or replace function public.dentro_de_la_zona(
  p_ciudad uuid,
  p_punto  extensions.geography
)
returns boolean
language sql stable security definer set search_path = public, extensions
as $$
  select case
           when exists (select 1 from public.zonas z
                         where z.ciudad_id = p_ciudad and z.activa)
             then exists (select 1 from public.zonas z
                           where z.ciudad_id = p_ciudad and z.activa
                             and extensions.ST_Covers(z.poligono, p_punto))
           else exists (select 1 from public.ciudades c
                         where c.id = p_ciudad
                           and extensions.ST_DWithin(c.centro, p_punto, c.radio_km * 1000))
         end;
$$;

comment on function public.dentro_de_la_zona(uuid, extensions.geography) is
  'Si la ciudad tiene zonas activas, el punto tiene que caer en alguna; si no, a menos de radio_km del centro.';

revoke execute on function public.dentro_de_la_zona(uuid, extensions.geography) from public, anon;

-- `p_que` es el sujeto del mensaje ("Esa dirección", "El punto de retiro"):
-- el cliente tiene que saber cuál de los dos pines está mal.
create or replace function public.exigir_zona(
  p_ciudad uuid,
  p_punto  extensions.geography,
  p_que    text
)
returns void
language plpgsql stable security definer set search_path = public, extensions
as $$
begin
  if p_punto is null or p_ciudad is null then
    return;
  end if;
  if not public.dentro_de_la_zona(p_ciudad, p_punto) then
    raise exception '% queda fuera de la zona de reparto. Por ahora MODO YA reparte solo dentro de la ciudad.', p_que
      using errcode = 'MY008';
  end if;
end;
$$;

revoke execute on function public.exigir_zona(uuid, extensions.geography, text) from public, anon;

-- ---------------------------------------------------------------------------
-- Toda cotización pasa por acá
-- ---------------------------------------------------------------------------

-- Igual que la de 0009 más los dos chequeos. Misma firma: los grants y quien la
-- llama no cambian.
create or replace function public.cotizar(
  p_ciudad   uuid,
  p_origen   extensions.geography,
  p_destino  extensions.geography,
  p_servicio tipo_servicio default 'delivery'
)
returns table (
  tarifario_id        uuid,
  distancia_km        numeric,
  km_adicionales      numeric,
  ganancia_repartidor integer,
  comision            integer,
  total               integer,
  minutos_estimados   integer
)
language plpgsql stable set search_path = public, extensions
as $$
declare
  t public.tarifarios;
  d numeric;
  extra numeric;
begin
  t := public.tarifario_vigente(p_ciudad, p_servicio);
  if t.id is null then
    raise exception 'No hay tarifario vigente para la ciudad %', p_ciudad
      using errcode = 'MY004';
  end if;

  -- El destino primero: es el pin que pone el cliente y el que más se equivoca.
  perform public.exigir_zona(p_ciudad, p_destino, 'Esa dirección');
  perform public.exigir_zona(p_ciudad, p_origen, 'El punto de retiro');

  d := public.distancia_ruta_km(p_origen, p_destino);
  extra := greatest(d - t.km_incluidos, 0);

  tarifario_id        := t.id;
  distancia_km        := d;
  km_adicionales      := extra;
  ganancia_repartidor := t.ganancia_repartidor_base
                         + round(extra * t.precio_km_adicional);
  comision            := t.comision_modo_ya;
  total               := ganancia_repartidor + comision;
  minutos_estimados   := 4 + round(d / 22 * 60);
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- Al guardar la dirección y al ubicar el local
-- ---------------------------------------------------------------------------

-- Trigger y no un chequeo dentro de `agregar_direccion` / `set_ubicacion_comercio`
-- para que valga por cualquier camino, incluido el alta que hace la
-- administración y los updates directos que permiten los grants por columna.
create or replace function public.direccion_dentro_de_la_zona()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public.exigir_zona(
    (select ciudad_id from public.clientes where id = new.cliente_id),
    new.ubicacion,
    'Esa dirección'
  );
  return new;
end;
$$;

drop trigger if exists direcciones_cliente_en_la_zona on public.direcciones_cliente;
create trigger direcciones_cliente_en_la_zona
  before insert or update of ubicacion on public.direcciones_cliente
  for each row execute function public.direccion_dentro_de_la_zona();

create or replace function public.local_dentro_de_la_zona()
returns trigger
language plpgsql security definer set search_path = public, extensions
as $$
begin
  perform public.exigir_zona(new.ciudad_id, new.ubicacion, 'La ubicación del local');
  return new;
end;
$$;

drop trigger if exists comercios_en_la_zona on public.comercios;
create trigger comercios_en_la_zona
  before insert or update of ubicacion, ciudad_id on public.comercios
  for each row execute function public.local_dentro_de_la_zona();

revoke execute on function public.direccion_dentro_de_la_zona() from public, anon, authenticated;
revoke execute on function public.local_dentro_de_la_zona() from public, anon, authenticated;
