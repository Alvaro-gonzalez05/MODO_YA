-- Los nombres de los rubros se ven tal cual en la app del cliente y en el
-- panel. La semilla (0017) los cargo sin acentos.
--
-- comercios.rubro guarda una copia del nombre al dar de alta el local: se
-- actualiza tambien, solo donde coincide con el nombre viejo.

with cambios(viejo, nuevo) as (
  values
    ('Pizzeria',  'Pizzería'),
    ('Rotiseria', 'Rotisería'),
    ('Heladeria', 'Heladería'),
    ('Cafeteria', 'Cafetería'),
    ('Almacen',   'Almacén')
),
rubros_actualizados as (
  update public.rubros r
     set nombre = c.nuevo
    from cambios c
   where r.nombre = c.viejo
  returning r.id
)
update public.comercios co
   set rubro = c.nuevo
  from cambios c
 where co.rubro = c.viejo;
