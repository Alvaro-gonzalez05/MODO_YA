-- El usuario (email) con el que entra cada local o rider, para mostrarlo en el
-- panel de administracion. Desde la version 1.1 esos emails los genera el
-- servidor (nombre@modoya.com), asi que la administracion necesita verlos
-- para pasarselos a quien corresponda.
--
-- auth.users no es legible desde la app: la funcion es security definer y
-- controla adentro que quien pregunta sea admin.

create or replace function public.admin_usuario_de(
  p_comercio uuid default null,
  p_repartidor uuid default null
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_perfil uuid;
begin
  if not exists (select 1 from perfiles where id = (select auth.uid()) and rol = 'admin') then
    raise exception 'Solo la administracion puede ver los usuarios'
      using errcode = '42501';
  end if;

  if p_comercio is not null then
    select perfil_id into v_perfil from comercios where id = p_comercio;
  elsif p_repartidor is not null then
    select perfil_id into v_perfil from repartidores where id = p_repartidor;
  end if;

  return (select email from auth.users where id = v_perfil);
end;
$$;

revoke all on function public.admin_usuario_de(uuid, uuid) from public, anon;
grant execute on function public.admin_usuario_de(uuid, uuid) to authenticated;
