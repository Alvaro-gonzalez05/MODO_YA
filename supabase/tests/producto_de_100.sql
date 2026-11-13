-- Le carga un producto de $100 al local de pizzeria de prueba, para el primer
-- cobro real (docs/probar-mercado-pago.md). El pedido sale $100 mas el envio.
--
--   powershell -NoProfile -Command "& './supabase/scripts/sql.ps1' -Archivo 'supabase/tests/producto_de_100.sql'"
--
-- Busca el local por nombre ("pizz" y "prueba" o "test") y se niega si
-- encuentra cero o mas de uno: en produccion no se adivina a que local se le
-- carga algo. Se puede correr dos veces sin duplicar el producto.
--
-- El producto se borra solo con el local cuando se limpie lo de prueba
-- (productos cae en cascada con comercios).

do $$
declare
  v_locales  text[];
  v_local    uuid;
  v_seccion  uuid;
begin
  select array_agg(nombre order by nombre), min(id::text)::uuid
    into v_locales, v_local
    from public.comercios
   where nombre ilike '%pizz%'
     and (nombre ilike '%prueba%' or nombre ilike '%test%');

  if coalesce(cardinality(v_locales), 0) = 0 then
    raise exception 'No hay ningun local de pizzeria de prueba. No cargue nada.';
  end if;
  if cardinality(v_locales) > 1 then
    raise exception 'Hay mas de un local que parece de prueba: %. No cargue nada.', v_locales;
  end if;

  if exists (select 1 from public.productos
              where comercio_id = v_local and nombre = 'Producto de prueba') then
    update public.productos set precio = 100, disponible = true
     where comercio_id = v_local and nombre = 'Producto de prueba';
    return;
  end if;

  -- La seccion que ya tenga el local, o una nueva: un producto sin seccion
  -- puede no mostrarse en el menu del cliente.
  select id into v_seccion from public.secciones_menu
   where comercio_id = v_local and activa
   order by orden limit 1;
  if v_seccion is null then
    insert into public.secciones_menu (comercio_id, nombre)
    values (v_local, 'Prueba') returning id into v_seccion;
  end if;

  insert into public.productos (comercio_id, seccion_id, nombre, descripcion, precio)
  values (v_local, v_seccion, 'Producto de prueba',
          'Para probar el cobro con tarjeta. No se entrega.', 100);
end $$;

-- Lo que hace falta para que el pedido se pueda hacer ahora mismo.
select c.nombre as local,
       p.nombre as producto,
       p.precio,
       c.acepta_pedidos,
       public.comercio_abierto(c.id) as abierto_ahora,
       u.email as usuario_del_local
  from public.productos p
  join public.comercios c on c.id = p.comercio_id
  join auth.users u on u.id = c.perfil_id
 where p.nombre = 'Producto de prueba'
   and c.nombre ilike '%pizz%'
   and (c.nombre ilike '%prueba%' or c.nombre ilike '%test%');
