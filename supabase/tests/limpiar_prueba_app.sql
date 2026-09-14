-- Borra los datos que dejaron las cuentas de prueba *@modoya.test, y SOLO esos.
--
-- Orden: pedidos y envios no se borran en cascada con el local (a proposito,
-- para no perder historial real), asi que se sacan primero. Despues el script
-- borra los usuarios de Auth y el resto (perfiles, locales, riders, clientes,
-- direcciones, menu) cae en cascada.
--
-- Las fotos de Storage no se borran desde aca: Supabase no permite tocar
-- storage.objects por SQL. El test borra su producto (y con eso su foto) al
-- terminar.

do $$
declare
  -- Prefijo v_: sin el, "pedidos" choca con la tabla del mismo nombre.
  v_usuarios uuid[];
  v_locales  uuid[];
  v_riders   uuid[];
  v_clientes uuid[];
  v_pedidos  uuid[];
  v_pagos    uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_usuarios
    from auth.users where email like '%@modoya.test';
  if cardinality(v_usuarios) = 0 then return; end if;

  select coalesce(array_agg(id), '{}') into v_locales  from public.comercios    where perfil_id = any(v_usuarios);
  select coalesce(array_agg(id), '{}') into v_riders   from public.repartidores where perfil_id = any(v_usuarios);
  select coalesce(array_agg(id), '{}') into v_clientes from public.clientes     where perfil_id = any(v_usuarios);

  select coalesce(array_agg(id), '{}') into v_pedidos
    from public.pedidos where comercio_id = any(v_locales) or cliente_id = any(v_clientes);

  -- Solo los pagos de estos pedidos, nunca "todos los huerfanos".
  select coalesce(array_agg(pago_id), '{}') into v_pagos
    from public.pedidos where id = any(v_pedidos) and pago_id is not null;

  update public.pedidos set envio_id = null where id = any(v_pedidos);

  delete from public.envios
   where comercio_id = any(v_locales)
      or repartidor_id = any(v_riders)
      or pedido_id = any(v_pedidos);

  delete from public.pedidos where id = any(v_pedidos);
  delete from public.pagos where id = any(v_pagos);
end $$;

select 'datos de prueba borrados' as estado;
