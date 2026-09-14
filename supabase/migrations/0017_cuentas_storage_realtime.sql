-- 0017 - Cuentas, sesion, fotos, tiempo real y vistas para la app
--
-- Modelo de cuentas acordado el 13/09/2026:
--   * Clientes     -> se registran solos desde la app.
--   * Locales      -> los da de alta la administracion.
--   * Cadetes      -> los da de alta la administracion.
--   * Administracion -> una cuenta creada a mano.

-- ---------------------------------------------------------------------------
-- Alta automatica de perfil
--
-- REGLA DE SEGURIDAD: el rol se lee SOLO de `raw_app_meta_data`. Esa columna la
-- escribe unicamente el servidor (service_role). `raw_user_meta_data`, en
-- cambio, la manda el propio usuario al registrarse: si el rol saliera de ahi,
-- cualquiera podria hacer signUp(data: {rol: 'admin'}) y quedarse con el panel.
--
-- Un registro comun desde la app no trae rol en app_metadata, asi que cae en
-- 'cliente'. Locales y cadetes los crea la Edge Function admin-crear-usuario,
-- que si pone el rol en app_metadata.
-- ---------------------------------------------------------------------------

create or replace function public.alta_usuario()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_rol    rol_usuario;
  v_nombre text;
  v_tel    text;
  v_ciudad uuid;
begin
  begin
    v_rol := coalesce((new.raw_app_meta_data->>'rol')::rol_usuario, 'cliente');
  exception when invalid_text_representation then
    v_rol := 'cliente';
  end;

  v_nombre := coalesce(nullif(trim(new.raw_user_meta_data->>'nombre'), ''),
                       split_part(new.email, '@', 1), '');
  v_tel    := nullif(trim(new.raw_user_meta_data->>'telefono'), '');

  insert into public.perfiles (id, rol, nombre, telefono)
  values (new.id, v_rol, v_nombre, v_tel)
  on conflict (id) do nothing;

  if v_rol = 'cliente' then
    select id into v_ciudad from public.ciudades
     where activa order by creado_en limit 1;

    insert into public.clientes (perfil_id, ciudad_id, nombre, telefono)
    values (new.id, v_ciudad, v_nombre, v_tel)
    on conflict (perfil_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists alta_usuario on auth.users;
create trigger alta_usuario
  after insert on auth.users
  for each row execute function public.alta_usuario();

-- ---------------------------------------------------------------------------
-- Sesion: todo lo que la app necesita saber de quien entro, en una llamada
-- ---------------------------------------------------------------------------

create or replace function public.mi_sesion()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'usuario_id',    p.id,
    'rol',           p.rol,
    'nombre',        p.nombre,
    'telefono',      p.telefono,
    'comercio_id',   c.id,
    'repartidor_id', r.id,
    'cliente_id',    cl.id,
    'ciudad_id',     coalesce(c.ciudad_id, r.ciudad_id, cl.ciudad_id),
    'estado_aprobacion', coalesce(c.estado_aprobacion, r.estado_aprobacion)
  )
  from public.perfiles p
  left join public.comercios    c  on c.perfil_id  = p.id
  left join public.repartidores r  on r.perfil_id  = p.id
  left join public.clientes     cl on cl.perfil_id = p.id
  where p.id = auth.uid()
$$;

-- Solo el nombre de un cadete. Lo usan las vistas para que el comprobante de un
-- envio viejo siga diciendo quien lo llevo, sin abrirle al comercio el resto
-- de la ficha del cadete una vez terminado el viaje.
create or replace function public.nombre_repartidor(p_repartidor uuid)
returns text
language sql stable security definer set search_path = public
as $$ select nombre from public.repartidores where id = p_repartidor $$;

-- ---------------------------------------------------------------------------
-- El pedido guarda nombre y telefono del cliente
--
-- El comercio necesita saber a quien le prepara el pedido, pero no puede leer
-- la tabla `clientes` (y no debe). Se copian al crear el pedido, con el mismo
-- criterio que la direccion de entrega.
-- ---------------------------------------------------------------------------

alter table public.pedidos
  add column if not exists cliente_nombre   text,
  add column if not exists cliente_telefono text;

create or replace function public.completar_pedido()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  select nombre, telefono into new.cliente_nombre, new.cliente_telefono
    from public.clientes where id = new.cliente_id;
  return new;
end;
$$;

drop trigger if exists pedidos_completar on public.pedidos;
create trigger pedidos_completar
  before insert on public.pedidos
  for each row execute function public.completar_pedido();

-- ---------------------------------------------------------------------------
-- Vistas para la app
--
-- PostgREST devuelve las columnas geography como EWKB en hexadecimal, que en
-- Flutter no sirve para nada. Estas vistas exponen lat/lng como numeros y traen
-- ya resueltos los nombres que cada pantalla necesita.
--
-- Todas son security_invoker: respetan el RLS de quien consulta. Sin eso, una
-- vista corre con los permisos de su dueno y saltea RLS (ver 0008).
-- ---------------------------------------------------------------------------

create or replace view public.v_comercios
with (security_invoker = true)
as
select
  c.id, c.perfil_id, c.ciudad_id,
  c.nombre, c.rubro, c.rubro_id, r.nombre as rubro_nombre,
  c.telefono, c.calle, c.referencia,
  extensions.ST_Y(c.ubicacion::extensions.geometry) as lat,
  extensions.ST_X(c.ubicacion::extensions.geometry) as lng,
  c.logo_url, c.acepta_pedidos, c.demora_estimada_min,
  c.estado_aprobacion, c.creado_en,
  public.comercio_abierto(c.id) as abierto
from public.comercios c
left join public.rubros r on r.id = c.rubro_id;

create or replace view public.v_repartidores
with (security_invoker = true)
as
select
  rp.id, rp.perfil_id, rp.ciudad_id, rp.nombre, rp.telefono, rp.vehiculo,
  rp.foto_url, rp.estado_aprobacion, rp.conectado, rp.ocupado,
  extensions.ST_Y(rp.ultima_ubicacion::extensions.geometry) as lat,
  extensions.ST_X(rp.ultima_ubicacion::extensions.geometry) as lng,
  rp.ultima_ubicacion_en, rp.reputacion, rp.viajes_completados, rp.creado_en
from public.repartidores rp;

create or replace view public.v_envios
with (security_invoker = true)
as
select
  e.id, e.codigo, e.ciudad_id, e.servicio, e.pedido_id,
  e.comercio_id, c.nombre as comercio_nombre,
  e.repartidor_id, public.nombre_repartidor(e.repartidor_id) as repartidor_nombre,
  e.origen_calle, e.origen_referencia,
  extensions.ST_Y(e.origen_ubicacion::extensions.geometry)  as origen_lat,
  extensions.ST_X(e.origen_ubicacion::extensions.geometry)  as origen_lng,
  e.destino_calle, e.destino_referencia,
  extensions.ST_Y(e.destino_ubicacion::extensions.geometry) as destino_lat,
  extensions.ST_X(e.destino_ubicacion::extensions.geometry) as destino_lng,
  e.cliente_nombre, e.cliente_telefono, e.cliente_indicaciones,
  e.distancia_km, e.km_adicionales, e.ganancia_repartidor, e.comision, e.total,
  e.minutos_estimados, e.paga, e.estado, e.codigo_entrega,
  e.creado_en, e.confirmado_en, e.asignado_en, e.en_local_en,
  e.retirado_en, e.entregado_en, e.cancelado_en, e.motivo_cancelacion
from public.envios e
left join public.comercios c on c.id = e.comercio_id;

create or replace view public.v_pedidos
with (security_invoker = true)
as
select
  p.id, p.codigo, p.ciudad_id, p.estado,
  p.cliente_id, p.cliente_nombre, p.cliente_telefono,
  p.comercio_id, c.nombre as comercio_nombre, c.logo_url as comercio_logo_url,
  p.entrega_calle, p.entrega_referencia,
  extensions.ST_Y(p.entrega_ubicacion::extensions.geometry) as entrega_lat,
  extensions.ST_X(p.entrega_ubicacion::extensions.geometry) as entrega_lng,
  p.subtotal, p.costo_envio, p.total, p.metodo_pago, p.envio_id,
  p.envio_minutos_estimados, p.nota_cliente, p.motivo_rechazo, p.motivo_cancelacion,
  p.creado_en, p.pagado_en, p.aceptado_en, p.listo_en, p.entregado_en, p.cancelado_en
from public.pedidos p
left join public.comercios c on c.id = p.comercio_id;

create or replace view public.v_direcciones
with (security_invoker = true)
as
select
  d.id, d.cliente_id, d.alias, d.calle, d.referencia, d.predeterminada,
  extensions.ST_Y(d.ubicacion::extensions.geometry) as lat,
  extensions.ST_X(d.ubicacion::extensions.geometry) as lng,
  d.creado_en
from public.direcciones_cliente d;

-- La oferta que ve el cadete, ahora con lat/lng y el nombre del local.
-- Sigue SIN datos personales del cliente (ver 0006).
drop view if exists public.ofertas_abiertas;
create view public.ofertas_abiertas
with (security_invoker = true)
as
select
  o.id            as oferta_id,
  o.envio_id,
  o.repartidor_id,
  o.distancia_al_retiro_km,
  o.ofrecida_en,
  o.expira_en,
  e.codigo,
  e.comercio_id,
  c.nombre        as comercio_nombre,
  e.origen_calle,
  e.origen_referencia,
  extensions.ST_Y(e.origen_ubicacion::extensions.geometry)  as origen_lat,
  extensions.ST_X(e.origen_ubicacion::extensions.geometry)  as origen_lng,
  e.destino_calle,
  extensions.ST_Y(e.destino_ubicacion::extensions.geometry) as destino_lat,
  extensions.ST_X(e.destino_ubicacion::extensions.geometry) as destino_lng,
  e.distancia_km,
  e.minutos_estimados,
  e.ganancia_repartidor,
  e.estado
from public.ofertas o
join public.envios e on e.id = o.envio_id
left join public.comercios c on c.id = e.comercio_id
where o.respuesta is null
  and o.expira_en > now();

-- ---------------------------------------------------------------------------
-- RPCs de apoyo para la app
-- ---------------------------------------------------------------------------

-- El cliente guarda una direccion marcando el pin en el mapa.
create or replace function public.agregar_direccion(
  p_alias      text,
  p_calle      text,
  p_lat        double precision,
  p_lng        double precision,
  p_referencia text default null,
  p_predeterminada boolean default false
)
returns uuid
language plpgsql security definer set search_path = public, extensions
as $$
declare
  cli uuid := public.mi_cliente_id();
  nueva uuid;
begin
  if cli is null then
    raise exception 'Solo un cliente puede guardar direcciones' using errcode = '42501';
  end if;

  -- La primera direccion siempre queda como predeterminada.
  if p_predeterminada or not exists (
    select 1 from public.direcciones_cliente where cliente_id = cli
  ) then
    update public.direcciones_cliente set predeterminada = false where cliente_id = cli;
    p_predeterminada := true;
  end if;

  insert into public.direcciones_cliente (cliente_id, alias, calle, referencia, ubicacion, predeterminada)
  values (cli, p_alias, p_calle, p_referencia,
          extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography,
          p_predeterminada)
  returning id into nueva;

  return nueva;
end;
$$;

-- Cuanto sale el envio de un pedido, antes de confirmarlo.
create or replace function public.cotizar_para_cliente(
  p_comercio  uuid,
  p_direccion uuid
)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  com public.comercios;
  dir public.direcciones_cliente;
  cot record;
begin
  select * into dir from public.direcciones_cliente
   where id = p_direccion and cliente_id = public.mi_cliente_id();
  if dir.id is null then
    raise exception 'La direccion no existe' using errcode = 'MY004';
  end if;

  select * into com from public.comercios where id = p_comercio and estado_aprobacion = 'aprobado';
  if com.id is null or com.ubicacion is null then
    raise exception 'El comercio no esta disponible' using errcode = 'MY004';
  end if;

  select * into cot from public.cotizar(com.ciudad_id, com.ubicacion, dir.ubicacion);
  return jsonb_build_object(
    'distancia_km', cot.distancia_km,
    'costo_envio', cot.total,
    'minutos_estimados', cot.minutos_estimados + com.demora_estimada_min
  );
end;
$$;

-- Cotizacion de cadeteria para el local, antes de crear el envio.
create or replace function public.cotizar_desde_mi_comercio(
  p_lat double precision,
  p_lng double precision
)
returns jsonb
language plpgsql stable security definer set search_path = public, extensions
as $$
declare
  com public.comercios;
  cot record;
begin
  select * into com from public.comercios where id = public.mi_comercio_id();
  if com.id is null then
    raise exception 'Solo un comercio puede cotizar envios' using errcode = '42501';
  end if;
  if com.ubicacion is null then
    raise exception 'Primero marca el punto de retiro de tu local' using errcode = 'MY004';
  end if;

  select * into cot from public.cotizar(
    com.ciudad_id, com.ubicacion,
    extensions.ST_SetSRID(extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography
  );
  return jsonb_build_object(
    'distancia_km', cot.distancia_km,
    'km_adicionales', cot.km_adicionales,
    'ganancia_repartidor', cot.ganancia_repartidor,
    'comision', cot.comision,
    'total', cot.total,
    'minutos_estimados', cot.minutos_estimados
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Storage
--
-- `catalogo` es publico: logos y fotos de productos se ven sin loguearse y se
-- sirven por CDN. Cada local escribe solo dentro de su carpeta, que es su id:
--     catalogo/<comercio_id>/logo.jpg
--     catalogo/<comercio_id>/productos/<producto_id>.jpg
--
-- `documentos` es privado: la documentacion de los cadetes la ven el propio
-- cadete y la administracion, nadie mas.
--     documentos/<repartidor_id>/<tipo>.jpg
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('catalogo',   'catalogo',   true,  5 * 1024 * 1024,
   array['image/jpeg','image/png','image/webp']),
  ('documentos', 'documentos', false, 10 * 1024 * 1024,
   array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do nothing;

create policy catalogo_leer on storage.objects
  for select to public
  using (bucket_id = 'catalogo');

create policy catalogo_subir on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'catalogo'
    and ((storage.foldername(name))[1] = (select public.mi_comercio_id())::text
         or (select public.es_admin()))
  );

create policy catalogo_reemplazar on storage.objects
  for update to authenticated
  using (
    bucket_id = 'catalogo'
    and ((storage.foldername(name))[1] = (select public.mi_comercio_id())::text
         or (select public.es_admin()))
  );

create policy catalogo_borrar on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'catalogo'
    and ((storage.foldername(name))[1] = (select public.mi_comercio_id())::text
         or (select public.es_admin()))
  );

create policy documentos_leer on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos'
    and ((storage.foldername(name))[1] = (select public.mi_repartidor_id())::text
         or (select public.es_admin()))
  );

create policy documentos_subir on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = (select public.mi_repartidor_id())::text
  );

create policy documentos_reemplazar on storage.objects
  for update to authenticated
  using (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = (select public.mi_repartidor_id())::text
  );

-- ---------------------------------------------------------------------------
-- Realtime
--
-- Postgres Changes respeta RLS: cada suscriptor recibe solo los cambios de las
-- filas que puede leer. El local ve sus pedidos entrar, el cadete ve sus
-- ofertas, el cliente ve avanzar su pedido.
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach t in array array['envios','ofertas','pedidos','repartidores']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Rubros iniciales (chips del home del cliente)
-- ---------------------------------------------------------------------------

insert into public.rubros (nombre, icono, orden) values
  ('Pizzeria',     'local_pizza',     1),
  ('Hamburguesas', 'lunch_dining',    2),
  ('Empanadas',    'bakery_dining',   3),
  ('Rotiseria',    'restaurant',      4),
  ('Parrilla',     'outdoor_grill',   5),
  ('Heladeria',    'icecream',        6),
  ('Cafeteria',    'local_cafe',      7),
  ('Farmacia',     'local_pharmacy',  8),
  ('Kiosco',       'storefront',      9),
  ('Almacen',      'local_grocery_store', 10)
on conflict (nombre) do nothing;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.mi_sesion(),
  public.nombre_repartidor(uuid),
  public.agregar_direccion(text, text, double precision, double precision, text, boolean),
  public.cotizar_para_cliente(uuid, uuid),
  public.cotizar_desde_mi_comercio(double precision, double precision)
to authenticated;

-- comercio_abierto se evalua dentro de v_comercios con los permisos de quien
-- consulta (security_invoker), asi que necesita EXECUTE propio.
grant execute on function public.comercio_abierto(uuid) to authenticated;

grant select on public.v_comercios, public.v_repartidores, public.v_envios,
               public.v_pedidos, public.v_direcciones, public.ofertas_abiertas
  to authenticated;
