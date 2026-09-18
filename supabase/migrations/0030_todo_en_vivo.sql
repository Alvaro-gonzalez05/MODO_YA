-- 0030 - Todo en tiempo real
--
-- Hasta ahora solo pedidos, envios, ofertas, riders, carteles y pagos avisaban
-- sus cambios. El resto (la vidriera, el logo o la portada de un local, el
-- menu, los horarios) se veia recien al recargar la pagina.
--
-- La app escucha estas tablas con enVivo() (packages/my_core/lib/src/backend.dart)
-- y vuelve a leer cuando cambian. Realtime respeta el RLS de quien escucha:
-- a cada uno le llegan solo los cambios de filas que puede leer.

do $$
declare
  t text;
begin
  foreach t in array array[
    'comercios', 'horarios_comercio',
    'secciones_menu', 'productos', 'opciones_producto', 'opcion_items',
    'rubros', 'direcciones_cliente', 'tarifarios'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
