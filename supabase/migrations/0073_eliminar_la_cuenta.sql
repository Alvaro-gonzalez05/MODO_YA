-- 0073 - El cliente puede eliminar su cuenta
--
-- Apple no publica una app que deja crear una cuenta y no deja borrarla desde
-- adentro (guía 5.1.1(v)), y Google Play lo controla. La página
-- /eliminar-cuenta de la web ya decía "Entrá a Mi cuenta y elegí Eliminar mi
-- cuenta", pero la app no lo tenía.
--
-- Qué quiere decir "eliminar" acá, que es lo que promete esa página:
--
--   * se borra el usuario (email y contraseña) y con él lo que cuelga del
--     perfil: el dispositivo para notificaciones, las notificaciones;
--   * se borran sus direcciones, favoritos, tarjetas guardadas y Plus;
--   * **los pedidos se quedan**, porque son la plata de los locales y el
--     respaldo de sus liquidaciones (y la ley pide guardarlos diez años), pero
--     sin nombre, teléfono, dirección ni nota: quedan montos, fechas y lo que
--     se pidió. La ubicación de entrega se redondea a una cuadrícula de 1 km,
--     así sirve para estadísticas por zona y no señala ninguna casa.
--
-- Para que el usuario se pueda borrar sin llevarse los pedidos, el cliente
-- deja de colgar del perfil con `on delete cascade`: queda la fila anónima,
-- con `perfil_id` en null. Lo mismo con quien abrió un reclamo.
--
-- Hay dos puertas, con la misma lógica: el cliente desde la app
-- (`eliminar_mi_cuenta`) y la administración cuando lo piden por la web
-- (`admin_eliminar_cliente`, por email). Locales y riders no se dan de baja
-- solos: tienen liquidaciones abiertas y se resuelve hablando.

-- ---------------------------------------------------------------------------
-- El cliente sobrevive a su usuario
-- ---------------------------------------------------------------------------

alter table public.clientes alter column perfil_id drop not null;
alter table public.clientes drop constraint clientes_perfil_id_fkey;
alter table public.clientes
  add constraint clientes_perfil_id_fkey
  foreign key (perfil_id) references public.perfiles(id) on delete set null;

alter table public.reclamos alter column abierto_por drop not null;
alter table public.reclamos drop constraint reclamos_abierto_por_fkey;
alter table public.reclamos
  add constraint reclamos_abierto_por_fkey
  foreign key (abierto_por) references public.perfiles(id) on delete set null;

-- ---------------------------------------------------------------------------
-- La baja
-- ---------------------------------------------------------------------------

create or replace function public.borrar_cliente(p_cliente uuid)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
  cli public.clientes;
begin
  select * into cli from public.clientes where id = p_cliente for update;
  if cli.id is null then
    raise exception 'No existe esa cuenta' using errcode = 'MY004';
  end if;
  -- Ya se eliminó: no hay nada más que hacer, y repetirlo no tiene que fallar.
  if cli.perfil_id is null then
    return;
  end if;

  -- Con un pedido andando no: el local lo está cocinando, el rider lo está
  -- llevando, y los dos necesitan el nombre, el teléfono y la dirección.
  if exists (select 1 from public.pedidos
              where cliente_id = cli.id
                and estado in ('pagado', 'aceptado', 'en_preparacion', 'listo', 'en_camino'))
     or exists (select 1 from public.envios
                 where cliente_id = cli.id and pedido_id is null
                   and estado not in ('entregado', 'cancelado')) then
    raise exception 'Tenés un pedido en curso. Cuando llegue vas a poder eliminar la cuenta.'
      using errcode = 'MY009';
  end if;

  -- Lo que esperaba el pago se cancela. Si había un cobro en revisión y el
  -- banco lo aprueba después, 0068 lo devuelve.
  update public.pedidos
     set estado = 'cancelado', cancelado_en = now(),
         motivo_cancelacion = 'El cliente eliminó su cuenta'
   where cliente_id = cli.id and estado = 'pendiente_pago';

  -- Las copias que guardan los pedidos y los envíos al momento de pedir.
  update public.pedidos
     set cliente_nombre = 'Cuenta eliminada',
         cliente_telefono = null,
         nota_cliente = null,
         entrega_calle = 'Dirección eliminada',
         entrega_referencia = null,
         entrega_ubicacion = extensions.ST_SnapToGrid(entrega_ubicacion::extensions.geometry, 0.01)::extensions.geography
   where cliente_id = cli.id;

  update public.envios
     set cliente_nombre = 'Cuenta eliminada',
         cliente_telefono = null,
         destino_calle = 'Dirección eliminada',
         destino_referencia = null,
         destino_ubicacion = extensions.ST_SnapToGrid(destino_ubicacion::extensions.geometry, 0.01)::extensions.geography
   where cliente_id = cli.id
      or pedido_id in (select id from public.pedidos where cliente_id = cli.id);

  -- En un mandado el retiro también lo eligió el cliente (su casa, a veces).
  update public.envios
     set origen_calle = 'Dirección eliminada',
         origen_referencia = null,
         origen_ubicacion = extensions.ST_SnapToGrid(origen_ubicacion::extensions.geometry, 0.01)::extensions.geography
   where cliente_id = cli.id and pedido_id is null;

  delete from public.direcciones_cliente where cliente_id = cli.id;
  delete from public.favoritos where cliente_id = cli.id;
  delete from public.tarjetas_guardadas where cliente_id = cli.id;
  -- Plus se da de baja y no se vuelve a cobrar. Los pagos de Plus quedan en
  -- `pagos`: son facturación.
  delete from public.suscripciones_plus where cliente_id = cli.id;

  update public.clientes
     set nombre = 'Cuenta eliminada', telefono = null, foto_url = null, mp_customer_id = null
   where id = cli.id;

  -- El usuario al final: arrastra el perfil, el dispositivo y las
  -- notificaciones, y deja `clientes.perfil_id` en null.
  delete from auth.users where id = cli.perfil_id;
end;
$$;

revoke execute on function public.borrar_cliente(uuid) from public, anon, authenticated;

create or replace function public.eliminar_mi_cuenta()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  cli uuid := public.mi_cliente_id();
begin
  if cli is null then
    raise exception 'Las cuentas de locales y riders las da de baja la administración: escribinos y la damos de baja.'
      using errcode = '42501';
  end if;
  perform public.borrar_cliente(cli);
end;
$$;

revoke execute on function public.eliminar_mi_cuenta() from public, anon;
grant execute on function public.eliminar_mi_cuenta() to authenticated;

-- Para los pedidos que llegan por el formulario de /eliminar-cuenta: la
-- persona escribe desde su correo y la administración la da de baja por email.
create or replace function public.admin_eliminar_cliente(p_email text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  cli uuid;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion' using errcode = '42501';
  end if;

  select c.id into cli
    from public.clientes c
    join auth.users u on u.id = c.perfil_id
   where lower(u.email) = lower(trim(p_email));

  if cli is null then
    raise exception 'No hay ningún cliente con ese email' using errcode = 'MY004';
  end if;
  perform public.borrar_cliente(cli);
end;
$$;

revoke execute on function public.admin_eliminar_cliente(text) from public, anon;
grant execute on function public.admin_eliminar_cliente(text) to authenticated;
