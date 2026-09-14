-- 0016 - Escalada de privilegios por edicion de la propia fila  [CRITICO]
--
-- Las politicas de RLS deciden QUE FILAS puede tocar cada uno, no QUE COLUMNAS.
-- `perfiles_editar` dejaba a cada usuario actualizar su propia fila, y eso
-- incluia la columna `rol`:
--
--     update perfiles set rol = 'admin' where id = auth.uid();   -- funcionaba
--
-- Lo mismo con `comercios.estado_aprobacion` (un local pendiente se aprobaba
-- solo), `repartidores.reputacion` / `ocupado` y `documentos_repartidor.estado`.
-- Verificado con una sonda antes de corregir: las dos primeras eran explotables.
--
-- La correccion es en dos partes:
--   1. Permisos por columna: `authenticated` solo puede escribir los datos que
--      de verdad le pertenecen (nombre, telefono, foto...).
--   2. Todo lo que cambia estado, aprobacion o privilegios pasa por funciones
--      `security definer` que verifican el rol por dentro.
--
-- service_role no se toca: la Edge Function que da de alta cuentas lo necesita.

-- ---------------------------------------------------------------------------
-- 1. Permisos por columna
-- ---------------------------------------------------------------------------

-- Perfiles: el rol no lo cambia nadie desde la app.
revoke insert, update on public.perfiles from authenticated, anon;
grant update (nombre, telefono) on public.perfiles to authenticated;

-- Comercios: el local edita su vidriera; la aprobacion es de la administracion.
-- Las altas las hace la Edge Function admin-crear-usuario con service_role.
revoke insert, update on public.comercios from authenticated, anon;
grant update (
  nombre, rubro, rubro_id, telefono, calle, referencia, ubicacion,
  logo_url, acepta_pedidos, demora_estimada_min
) on public.comercios to authenticated;

-- Repartidores: conectarse y la ubicacion van por RPC (set_conectado,
-- actualizar_ubicacion); reputacion, viajes y ocupado los mueve el sistema.
revoke insert, update on public.repartidores from authenticated, anon;
grant update (telefono, foto_url) on public.repartidores to authenticated;

-- Documentacion: el cadete sube el archivo; validarlo es de la administracion.
revoke insert, update on public.documentos_repartidor from authenticated, anon;
grant insert (repartidor_id, tipo, archivo_url, vence_en)
  on public.documentos_repartidor to authenticated;
grant update (archivo_url, vence_en)
  on public.documentos_repartidor to authenticated;

-- Clientes: la fila la crea el alta de usuario (trigger en 0017), no la app.
revoke insert, update on public.clientes from authenticated, anon;
grant update (nombre, telefono, foto_url) on public.clientes to authenticated;
drop policy if exists clientes_alta on public.clientes;

-- Reclamos: quien lo abre y con que rol lo completa el servidor, no el cliente.
revoke insert, update on public.reclamos from authenticated, anon;
grant insert (envio_id, motivo, detalle) on public.reclamos to authenticated;

create or replace function public.completar_reclamo()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.abierto_por := auth.uid();
  new.rol_origen  := public.mi_rol();
  new.estado      := 'abierto';
  return new;
end;
$$;

create trigger reclamos_completar
  before insert on public.reclamos
  for each row execute function public.completar_reclamo();

-- ---------------------------------------------------------------------------
-- 2. Acciones de administracion
-- ---------------------------------------------------------------------------

create or replace function public.exigir_admin()
returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion puede hacer esto' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.admin_aprobacion_comercio(
  p_comercio uuid,
  p_estado   estado_aprobacion,
  p_motivo   text default null
)
returns public.comercios
language plpgsql security definer set search_path = public
as $$
declare c public.comercios;
begin
  perform public.exigir_admin();
  update public.comercios
     set estado_aprobacion = p_estado,
         motivo_rechazo = case when p_estado in ('rechazado','suspendido') then p_motivo end,
         aprobado_en  = case when p_estado = 'aprobado' then now() else aprobado_en end,
         aprobado_por = case when p_estado = 'aprobado' then auth.uid() else aprobado_por end
   where id = p_comercio
  returning * into c;
  if c.id is null then
    raise exception 'El comercio no existe' using errcode = 'MY004';
  end if;
  return c;
end;
$$;

create or replace function public.admin_aprobacion_repartidor(
  p_repartidor uuid,
  p_estado     estado_aprobacion,
  p_motivo     text default null
)
returns public.repartidores
language plpgsql security definer set search_path = public
as $$
declare r public.repartidores;
begin
  perform public.exigir_admin();
  update public.repartidores
     set estado_aprobacion = p_estado,
         motivo_rechazo = case when p_estado in ('rechazado','suspendido') then p_motivo end,
         aprobado_en  = case when p_estado = 'aprobado' then now() else aprobado_en end,
         aprobado_por = case when p_estado = 'aprobado' then auth.uid() else aprobado_por end,
         -- Un cadete suspendido no puede quedar conectado recibiendo ofertas.
         conectado = case when p_estado = 'aprobado' then conectado else false end
   where id = p_repartidor
  returning * into r;
  if r.id is null then
    raise exception 'El cadete no existe' using errcode = 'MY004';
  end if;
  return r;
end;
$$;

create or replace function public.admin_validar_documento(
  p_documento   uuid,
  p_estado      estado_aprobacion,
  p_observacion text default null
)
returns public.documentos_repartidor
language plpgsql security definer set search_path = public
as $$
declare d public.documentos_repartidor;
begin
  perform public.exigir_admin();
  update public.documentos_repartidor
     set estado = p_estado, observacion = p_observacion,
         validado_por = auth.uid(), validado_en = now()
   where id = p_documento
  returning * into d;
  if d.id is null then
    raise exception 'El documento no existe' using errcode = 'MY004';
  end if;
  return d;
end;
$$;

create or replace function public.admin_resolver_reclamo(
  p_reclamo    uuid,
  p_estado     text,
  p_resolucion text
)
returns public.reclamos
language plpgsql security definer set search_path = public
as $$
declare r public.reclamos;
begin
  perform public.exigir_admin();
  update public.reclamos
     set estado = p_estado, resolucion = p_resolucion,
         resuelto_por = case when p_estado in ('resuelto','desestimado') then auth.uid() end,
         resuelto_en  = case when p_estado in ('resuelto','desestimado') then now() end
   where id = p_reclamo
  returning * into r;
  if r.id is null then
    raise exception 'El reclamo no existe' using errcode = 'MY004';
  end if;
  return r;
end;
$$;

-- Cambia el tarifario de forma atomica: cierra el vigente y abre uno nuevo.
-- Hacerlo en dos pasos desde la app dejaria una ventana sin tarifario (y
-- crear_envio fallaria) o con dos abiertos (y el indice unico lo rechazaria).
create or replace function public.admin_nuevo_tarifario(
  p_ciudad                   uuid,
  p_ganancia_repartidor_base integer,
  p_comision_modo_ya         integer,
  p_precio_km_adicional      integer,
  p_km_incluidos             numeric,
  p_radio_busqueda_km        numeric,
  p_segundos_para_aceptar    integer,
  p_precio_suscripcion_mensual integer default null,
  p_servicio                 tipo_servicio default 'delivery'
)
returns public.tarifarios
language plpgsql security definer set search_path = public
as $$
declare t public.tarifarios;
begin
  perform public.exigir_admin();

  update public.tarifarios set vigente_hasta = now()
   where ciudad_id = p_ciudad and servicio = p_servicio and vigente_hasta is null;

  insert into public.tarifarios (
    ciudad_id, servicio, ganancia_repartidor_base, comision_modo_ya,
    precio_km_adicional, km_incluidos, radio_busqueda_km, segundos_para_aceptar,
    precio_suscripcion_mensual, creado_por
  ) values (
    p_ciudad, p_servicio, p_ganancia_repartidor_base, p_comision_modo_ya,
    p_precio_km_adicional, p_km_incluidos, p_radio_busqueda_km, p_segundos_para_aceptar,
    p_precio_suscripcion_mensual, auth.uid()
  ) returning * into t;

  return t;
end;
$$;

-- El local marca su punto de retiro en el mapa. Va por RPC para no obligar a
-- la app a armar geografia en formato EWKT.
create or replace function public.set_ubicacion_comercio(
  p_lat double precision,
  p_lng double precision
)
returns public.comercios
language plpgsql security definer set search_path = public, extensions
as $$
declare c public.comercios;
begin
  update public.comercios
     set ubicacion = extensions.ST_SetSRID(
           extensions.ST_MakePoint(p_lng, p_lat), 4326)::extensions.geography
   where id = public.mi_comercio_id()
  returning * into c;
  if c.id is null then
    raise exception 'Solo un comercio puede marcar su ubicacion' using errcode = '42501';
  end if;
  return c;
end;
$$;

revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.admin_aprobacion_comercio(uuid, estado_aprobacion, text),
  public.admin_aprobacion_repartidor(uuid, estado_aprobacion, text),
  public.admin_validar_documento(uuid, estado_aprobacion, text),
  public.admin_resolver_reclamo(uuid, text, text),
  public.admin_nuevo_tarifario(uuid, integer, integer, integer, numeric, numeric,
                               integer, integer, tipo_servicio),
  public.set_ubicacion_comercio(double precision, double precision)
to authenticated;
