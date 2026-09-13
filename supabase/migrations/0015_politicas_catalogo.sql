-- 0015 - Politicas del catalogo acotadas a escritura
--
-- Mismo arreglo que 0011, ahora sobre las tablas del marketplace: una politica
-- `for all` tambien cubre SELECT, y como cada tabla ya tiene su politica de
-- lectura publica, quedaban dos permisivas evaluandose en cada consulta.
--
-- Cambia solo cuantas politicas se evaluan; el permiso efectivo es el mismo.

-- Tablas cuyo dueno se resuelve con una columna comercio_id directa.
do $$
declare t text;
begin
  foreach t in array array['horarios_comercio', 'secciones_menu', 'productos']
  loop
    execute format('drop policy if exists %I on public.%I',
                   case t when 'horarios_comercio' then 'horarios_escribir'
                          when 'secciones_menu'    then 'secciones_escribir'
                          else 'productos_escribir' end, t);

    execute format(
      'create policy %I on public.%I for insert to authenticated
         with check (comercio_id = (select public.mi_comercio_id())
                     or (select public.es_admin()))',
      t || '_insert', t);

    execute format(
      'create policy %I on public.%I for update to authenticated
         using (comercio_id = (select public.mi_comercio_id())
                or (select public.es_admin()))
         with check (comercio_id = (select public.mi_comercio_id())
                     or (select public.es_admin()))',
      t || '_update', t);

    execute format(
      'create policy %I on public.%I for delete to authenticated
         using (comercio_id = (select public.mi_comercio_id())
                or (select public.es_admin()))',
      t || '_delete', t);
  end loop;
end $$;

-- Opciones: el dueno se alcanza a traves del producto.
drop policy if exists opciones_escribir on public.opciones_producto;

create policy opciones_insert on public.opciones_producto
  for insert to authenticated
  with check (
    exists (
      select 1 from public.productos p
      where p.id = opciones_producto.producto_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

create policy opciones_update on public.opciones_producto
  for update to authenticated
  using (
    exists (
      select 1 from public.productos p
      where p.id = opciones_producto.producto_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  )
  with check (
    exists (
      select 1 from public.productos p
      where p.id = opciones_producto.producto_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

create policy opciones_delete on public.opciones_producto
  for delete to authenticated
  using (
    exists (
      select 1 from public.productos p
      where p.id = opciones_producto.producto_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

-- Items de opcion: dos saltos hasta el comercio.
drop policy if exists opcion_items_escribir on public.opcion_items;

create policy opcion_items_insert on public.opcion_items
  for insert to authenticated
  with check (
    exists (
      select 1 from public.opciones_producto o
      join public.productos p on p.id = o.producto_id
      where o.id = opcion_items.opcion_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

create policy opcion_items_update on public.opcion_items
  for update to authenticated
  using (
    exists (
      select 1 from public.opciones_producto o
      join public.productos p on p.id = o.producto_id
      where o.id = opcion_items.opcion_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  )
  with check (
    exists (
      select 1 from public.opciones_producto o
      join public.productos p on p.id = o.producto_id
      where o.id = opcion_items.opcion_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

create policy opcion_items_delete on public.opcion_items
  for delete to authenticated
  using (
    exists (
      select 1 from public.opciones_producto o
      join public.productos p on p.id = o.producto_id
      where o.id = opcion_items.opcion_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

-- Claves foraneas del marketplace que quedaron sin indice.
create index if not exists comercios_rubro_idx on public.comercios (rubro_id);
create index if not exists favoritos_comercio_idx on public.favoritos (comercio_id);
