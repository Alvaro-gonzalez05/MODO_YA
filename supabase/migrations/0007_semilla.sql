-- 0007 - Datos iniciales
--
-- Solo lo que el sistema necesita para funcionar: la ciudad, el tarifario
-- vigente y la documentacion exigida por vehiculo. Nada de comercios ni cadetes
-- de prueba: esos se dan de alta desde la app de administracion.

-- Malargue, Mendoza. Centro aproximado de la plaza San Martin.
insert into public.ciudades (nombre, provincia, centro, radio_km)
values (
  'Malargue', 'Mendoza',
  extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5847, -35.4756), 4326)::extensions.geography,
  15
)
on conflict (nombre, provincia) do nothing;

-- Tarifario de la etapa de prueba, con los valores del documento MVP:
-- $3.000 para el cadete + $500 de comision = $3.500 hasta 2 km.
--
-- precio_km_adicional queda en 0 a proposito: todavia no esta definido y
-- preferimos no cobrar de mas antes que inventar un numero.
insert into public.tarifarios (
  ciudad_id, servicio,
  ganancia_repartidor_base, comision_modo_ya, precio_km_adicional,
  km_incluidos, radio_busqueda_km, segundos_para_aceptar
)
select
  c.id, 'delivery',
  3000, 500, 0,
  2, 3, 30
from public.ciudades c
where c.nombre = 'Malargue'
  and not exists (
    select 1 from public.tarifarios t
    where t.ciudad_id = c.id and t.servicio = 'delivery' and t.vigente_hasta is null
  );

-- Documentacion exigida por tipo de vehiculo.
--
-- Supuesto de trabajo: la lista exacta sigue pendiente de definicion con la
-- clienta (seccion 15 del documento). Se cambia con un insert o un delete, no
-- con una migracion.
insert into public.documentos_exigidos (vehiculo, tipo, obligatorio) values
  ('moto',      'DNI',                    true),
  ('moto',      'Licencia de conducir',   true),
  ('moto',      'Cedula verde',           true),
  ('moto',      'Seguro del vehiculo',    true),
  ('auto',      'DNI',                    true),
  ('auto',      'Licencia de conducir',   true),
  ('auto',      'Cedula verde',           true),
  ('auto',      'Seguro del vehiculo',    true),
  ('bicicleta', 'DNI',                    true),
  ('a_pie',     'DNI',                    true)
on conflict (vehiculo, tipo) do nothing;
