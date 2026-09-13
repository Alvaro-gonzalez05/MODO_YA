-- 0011 - Politicas de admin acotadas a escritura
--
-- Una politica `for all` tambien aplica a SELECT. Como cada una de estas tablas
-- ya tiene su politica de lectura, Postgres terminaba evaluando dos politicas
-- permisivas en cada consulta y haciendo el OR entre ambas.
--
-- Se reemplaza cada `for all` de administracion por tres politicas explicitas
-- (insert / update / delete). El permiso efectivo es identico; lo que cambia es
-- que SELECT vuelve a tener una sola politica.

do $$
declare
  t text;
  politica text;
begin
  foreach t in array array[
    'ciudades', 'zonas', 'documentos_exigidos', 'tarifarios',
    'envios', 'ofertas', 'pagos', 'suscripciones',
    'liquidaciones', 'liquidacion_items'
  ]
  loop
    -- Los nombres quedaron de dos formas en migraciones anteriores.
    foreach politica in array array[t || '_escribir', t || '_admin_escribir']
    loop
      execute format('drop policy if exists %I on public.%I', politica, t);
    end loop;

    execute format(
      'create policy %I on public.%I for insert to authenticated
         with check ((select public.es_admin()))',
      t || '_admin_insert', t);

    execute format(
      'create policy %I on public.%I for update to authenticated
         using ((select public.es_admin()))
         with check ((select public.es_admin()))',
      t || '_admin_update', t);

    execute format(
      'create policy %I on public.%I for delete to authenticated
         using ((select public.es_admin()))',
      t || '_admin_delete', t);
  end loop;
end $$;
