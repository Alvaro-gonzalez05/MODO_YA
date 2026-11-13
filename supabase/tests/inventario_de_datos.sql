-- Lista lo que hay en la base de produccion para separar lo de prueba de lo
-- real ANTES de borrar nada. Solo lee: no cambia una fila.
--
--   powershell -NoProfile -Command "& './supabase/scripts/sql.ps1' -Archivo 'supabase/tests/inventario_de_datos.sql'"
--
-- Todo va en una sola consulta (union all) porque la Management API, que es
-- la que usa sql.ps1, devuelve solo el resultado de la ultima sentencia.
--
-- Los pagos simulados se reconocen por la referencia: pagar-pedido les pone
-- "simulado-…" cuando no se llamo a Mercado Pago.

select * from (
  -- Cada cuenta, con su rol y cuando entro por ultima vez.
  select 1 as orden,
         'cuenta'::text as que,
         coalesce(p.rol::text, 'sin perfil') as tipo,
         coalesce(nullif(p.nombre, ''), '-') as nombre,
         u.email::text as email,
         'ultimo ingreso ' || coalesce(to_char(u.last_sign_in_at at time zone 'America/Argentina/Mendoza', 'DD/MM HH24:MI'), 'nunca') as detalle,
         to_char(u.created_at at time zone 'America/Argentina/Mendoza', 'DD/MM/YYYY') as creado
    from auth.users u
    left join public.perfiles p on p.id = u.id

  union all
  -- Cada local, con cuanto movimiento tiene.
  select 2, 'local', 'local', c.nombre, u.email::text,
         (select count(*) from public.pedidos x where x.comercio_id = c.id) || ' pedidos, '
           || (select count(*) from public.envios x where x.comercio_id = c.id) || ' envios, '
           || (select count(*) from public.productos x where x.comercio_id = c.id) || ' productos',
         to_char(c.creado_en at time zone 'America/Argentina/Mendoza', 'DD/MM/YYYY')
    from public.comercios c
    join auth.users u on u.id = c.perfil_id

  union all
  -- Cada rider.
  select 3, 'rider', 'rider', r.nombre, u.email::text,
         (select count(*) from public.envios x where x.repartidor_id = r.id) || ' envios',
         to_char(r.creado_en at time zone 'America/Argentina/Mendoza', 'DD/MM/YYYY')
    from public.repartidores r
    join auth.users u on u.id = r.perfil_id

  union all
  -- Los pagos agrupados: lo que importa es si hubo plata de verdad.
  select 4, 'pagos',
         case when coalesce(referencia_externa, '') like 'simulado-%' then 'simulado'
              when referencia_externa is null then 'sin pasarela'
              else 'mercado pago' end,
         metodo::text || ' / ' || estado::text,
         null,
         count(*) || ' pagos, $' || sum(monto),
         to_char(min(creado_en) at time zone 'America/Argentina/Mendoza', 'DD/MM') || ' a '
           || to_char(max(creado_en) at time zone 'America/Argentina/Mendoza', 'DD/MM/YYYY')
    from public.pagos
   group by 3, 4

  union all
  select 5, 'pedidos', estado::text, null, null, count(*) || ' pedidos, $' || sum(total), null
    from public.pedidos
   group by estado
) t
order by orden, tipo, nombre;
