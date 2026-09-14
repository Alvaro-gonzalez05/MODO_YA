-- 0018 - El rol tambien se toma cuando Auth lo escribe en un UPDATE
--
-- Encontrado probando contra la API real de Auth (no en SQL): una cuenta creada
-- con auth.admin.createUser({ app_metadata: { rol: 'admin' } }) quedaba como
-- CLIENTE.
--
-- GoTrue no inserta el usuario con el app_metadata completo. Primero hace el
-- INSERT con {provider, providers} y recien despues un UPDATE con los datos
-- propios. El trigger de 0017 corre AFTER INSERT, asi que nunca veia el rol y
-- caia en el valor por defecto.
--
-- Los tests SQL no lo detectaban porque ahi el usuario se insertaba con todo
-- el app_metadata de una. Queda cubierto por supabase/tests/cuentas.ps1, que va
-- contra la API real.
--
-- Seguridad: escuchar el UPDATE no abre nada nuevo. raw_app_meta_data solo lo
-- puede escribir service_role; un usuario comun cambia raw_user_meta_data con
-- updateUser(), y eso no dispara este trigger.

create or replace function public.sincronizar_rol_usuario()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_rol    rol_usuario;
  v_ciudad uuid;
begin
  if (new.raw_app_meta_data->>'rol') is not distinct from (old.raw_app_meta_data->>'rol') then
    return new;
  end if;

  -- Si le sacaron el rol o pusieron un valor invalido, no se toca nada: bajar
  -- de categoria una cuenta tiene que ser una decision explicita, no un efecto
  -- secundario de un metadata mal cargado.
  begin
    v_rol := (new.raw_app_meta_data->>'rol')::rol_usuario;
  exception when invalid_text_representation then
    return new;
  end;
  if v_rol is null then
    return new;
  end if;

  insert into public.perfiles (id, rol, nombre)
  values (new.id, v_rol, coalesce(new.raw_user_meta_data->>'nombre', split_part(new.email, '@', 1), ''))
  on conflict (id) do update set rol = excluded.rol;

  if v_rol = 'cliente' then
    select id into v_ciudad from public.ciudades where activa order by creado_en limit 1;
    insert into public.clientes (perfil_id, ciudad_id, nombre, telefono)
    select new.id, v_ciudad, p.nombre, p.telefono from public.perfiles p where p.id = new.id
    on conflict (perfil_id) do nothing;
  else
    -- El INSERT previo lo dio de alta como cliente por defecto. Esa fila sobra.
    -- Solo se borra si no tiene pedidos: si la cuenta ya compro algo, el
    -- historial no se pierde.
    delete from public.clientes c
     where c.perfil_id = new.id
       and not exists (select 1 from public.pedidos p where p.cliente_id = c.id);
  end if;

  return new;
end;
$$;

drop trigger if exists sincronizar_rol_usuario on auth.users;
create trigger sincronizar_rol_usuario
  after update of raw_app_meta_data on auth.users
  for each row execute function public.sincronizar_rol_usuario();

revoke execute on function public.sincronizar_rol_usuario() from public, anon, authenticated;
