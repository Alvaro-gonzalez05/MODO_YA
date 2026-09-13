-- 0009 - Codigos de error propios
--
-- En 0005 use SQLSTATE de la clase P00xx para los errores de negocio. Fue un
-- error: esos codigos ya estan tomados por PL/pgSQL.
--
--   P0002 = no_data_found
--   P0003 = too_many_rows
--   P0004 = assert_failure   <-- y este NO lo atrapa `exception when others`
--
-- O sea que "el codigo de entrega no es correcto" era un error imposible de
-- capturar desde otra funcion PL/pgSQL. Se cambia por una clase propia:
--
--   MY001  transicion de estado invalida
--   MY002  codigo de entrega incorrecto
--   MY003  la oferta ya no esta disponible (vencida o tomada)
--   MY004  no existe el recurso pedido
--   42501  sin permiso / cuenta no aprobada  (estandar, PostgREST lo mapea a 403)
--
-- Estos codigos viajan en la respuesta de PostgREST, asi que la app puede
-- distinguirlos sin leer el texto del mensaje.

create or replace function public.registrar_cambio_estado()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.estado is distinct from old.estado then
    if not public.transicion_valida(old.estado, new.estado) then
      raise exception 'Transicion invalida: % -> %', old.estado, new.estado
        using errcode = 'MY001';
    end if;

    new.asignado_en  := coalesce(new.asignado_en,
                          case when new.estado = 'asignado'  then now() end);
    new.en_local_en  := coalesce(new.en_local_en,
                          case when new.estado = 'en_local'  then now() end);
    new.retirado_en  := coalesce(new.retirado_en,
                          case when new.estado = 'retirado'  then now() end);
    new.entregado_en := coalesce(new.entregado_en,
                          case when new.estado = 'entregado' then now() end);
    new.cancelado_en := coalesce(new.cancelado_en,
                          case when new.estado = 'cancelado' then now() end);
    new.confirmado_en := coalesce(new.confirmado_en,
                          case when new.estado = 'buscando_repartidor' then now() end);

    insert into public.envio_eventos (
      envio_id, estado_anterior, estado_nuevo, actor_id, actor_rol
    ) values (
      new.id, old.estado, new.estado, auth.uid(), public.mi_rol()
    );
  end if;
  return new;
end;
$$;

create or replace function public.cotizar(
  p_ciudad   uuid,
  p_origen   extensions.geography,
  p_destino  extensions.geography,
  p_servicio tipo_servicio default 'delivery'
)
returns table (
  tarifario_id        uuid,
  distancia_km        numeric,
  km_adicionales      numeric,
  ganancia_repartidor integer,
  comision            integer,
  total               integer,
  minutos_estimados   integer
)
language plpgsql stable set search_path = public, extensions
as $$
declare
  t public.tarifarios;
  d numeric;
  extra numeric;
begin
  t := public.tarifario_vigente(p_ciudad, p_servicio);
  if t.id is null then
    raise exception 'No hay tarifario vigente para la ciudad %', p_ciudad
      using errcode = 'MY004';
  end if;

  d := public.distancia_ruta_km(p_origen, p_destino);
  extra := greatest(d - t.km_incluidos, 0);

  tarifario_id        := t.id;
  distancia_km        := d;
  km_adicionales      := extra;
  ganancia_repartidor := t.ganancia_repartidor_base
                         + round(extra * t.precio_km_adicional);
  comision            := t.comision_modo_ya;
  total               := ganancia_repartidor + comision;
  minutos_estimados   := 4 + round(d / 22 * 60);
  return next;
end;
$$;

create or replace function public.crear_envio(
  p_destino_calle      text,
  p_destino_lat        double precision,
  p_destino_lng        double precision,
  p_cliente_nombre     text,
  p_cliente_telefono   text,
  p_paga               quien_paga,
  p_destino_referencia text default null,
  p_cliente_indicaciones text default null
)
returns public.envios
language plpgsql security definer set search_path = public, extensions
as $$
declare
  c       public.comercios;
  destino extensions.geography;
  cot     record;
  nuevo   public.envios;
begin
  select * into c from public.comercios where id = public.mi_comercio_id();
  if c.id is null then
    raise exception 'Solo un comercio puede crear envios' using errcode = '42501';
  end if;
  if c.estado_aprobacion <> 'aprobado' then
    raise exception 'Tu cuenta todavia no esta aprobada' using errcode = '42501';
  end if;
  if c.ubicacion is null then
    raise exception 'El comercio no tiene marcado el punto de retiro'
      using errcode = 'MY004';
  end if;

  destino := extensions.ST_SetSRID(
    extensions.ST_MakePoint(p_destino_lng, p_destino_lat), 4326
  )::extensions.geography;

  select * into cot from public.cotizar(c.ciudad_id, c.ubicacion, destino);

  insert into public.envios (
    ciudad_id, comercio_id,
    origen_calle, origen_referencia, origen_ubicacion,
    destino_calle, destino_referencia, destino_ubicacion,
    cliente_nombre, cliente_telefono, cliente_indicaciones,
    tarifario_id, distancia_km, km_adicionales,
    ganancia_repartidor, comision, minutos_estimados,
    paga, estado
  ) values (
    c.ciudad_id, c.id,
    c.calle, c.referencia, c.ubicacion,
    p_destino_calle, p_destino_referencia, destino,
    p_cliente_nombre, p_cliente_telefono, p_cliente_indicaciones,
    cot.tarifario_id, cot.distancia_km, cot.km_adicionales,
    cot.ganancia_repartidor, cot.comision, cot.minutos_estimados,
    p_paga, 'cotizado'
  ) returning * into nuevo;

  insert into public.envio_eventos (envio_id, estado_nuevo, actor_id, actor_rol)
  values (nuevo.id, 'cotizado', auth.uid(), 'comercio');

  return nuevo;
end;
$$;

create or replace function public.confirmar_envio(p_envio uuid)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare e public.envios;
begin
  update public.envios
     set estado = 'buscando_repartidor'
   where id = p_envio
     and comercio_id = public.mi_comercio_id()
     and estado = 'cotizado'
  returning * into e;

  if e.id is null then
    raise exception 'El envio no existe o no esta en estado cotizado'
      using errcode = 'MY004';
  end if;

  perform public.ofrecer_al_siguiente(p_envio);
  return e;
end;
$$;

create or replace function public.responder_oferta(
  p_oferta uuid,
  p_acepta boolean
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare
  o   public.ofertas;
  e   public.envios;
  rep uuid;
begin
  rep := public.mi_repartidor_id();

  select * into o from public.ofertas
   where id = p_oferta and repartidor_id = rep and respuesta is null
   for update;

  if o.id is null then
    raise exception 'La oferta no existe o ya fue respondida' using errcode = 'MY003';
  end if;

  if o.expira_en <= now() then
    update public.ofertas set respuesta = 'expirada', respondida_en = now()
     where id = o.id;
    perform public.ofrecer_al_siguiente(o.envio_id);
    raise exception 'La oferta vencio' using errcode = 'MY003';
  end if;

  if not p_acepta then
    update public.ofertas set respuesta = 'rechazada', respondida_en = now()
     where id = o.id;
    perform public.ofrecer_al_siguiente(o.envio_id);
    return null;
  end if;

  update public.ofertas set respuesta = 'aceptada', respondida_en = now()
   where id = o.id;

  update public.envios
     set estado = 'asignado',
         repartidor_id = rep,
         codigo_entrega = lpad((floor(random() * 10000))::int::text, 4, '0')
   where id = o.envio_id
     and estado = 'buscando_repartidor'
  returning * into e;

  if e.id is null then
    raise exception 'El envio ya no estaba disponible' using errcode = 'MY003';
  end if;

  update public.repartidores set ocupado = true where id = rep;
  return e;
end;
$$;

create or replace function public.avanzar_estado(
  p_envio uuid,
  p_nuevo estado_envio
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare e public.envios;
begin
  if p_nuevo = 'entregado' then
    raise exception 'Usa confirmar_entrega() para cerrar el envio'
      using errcode = '42501';
  end if;

  update public.envios set estado = p_nuevo
   where id = p_envio
     and repartidor_id = public.mi_repartidor_id()
  returning * into e;

  if e.id is null then
    raise exception 'El envio no existe o no es tuyo' using errcode = 'MY004';
  end if;
  return e;
end;
$$;

create or replace function public.confirmar_entrega(
  p_envio  uuid,
  p_codigo text
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare
  e   public.envios;
  rep uuid;
begin
  rep := public.mi_repartidor_id();

  select * into e from public.envios
   where id = p_envio and repartidor_id = rep for update;

  if e.id is null then
    raise exception 'El envio no existe o no es tuyo' using errcode = 'MY004';
  end if;
  if e.codigo_entrega is distinct from p_codigo then
    raise exception 'El codigo de entrega no es correcto' using errcode = 'MY002';
  end if;

  update public.envios set estado = 'entregado'
   where id = p_envio returning * into e;

  update public.repartidores
     set ocupado = false,
         viajes_completados = viajes_completados + 1
   where id = rep;

  return e;
end;
$$;

create or replace function public.cancelar_envio(
  p_envio  uuid,
  p_motivo text
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare e public.envios;
begin
  update public.envios
     set estado = 'cancelado',
         motivo_cancelacion = p_motivo,
         cancelado_por = auth.uid()
   where id = p_envio
     and (comercio_id = public.mi_comercio_id()
          or repartidor_id = public.mi_repartidor_id()
          or public.es_admin())
  returning * into e;

  if e.id is null then
    raise exception 'El envio no existe o no podes cancelarlo' using errcode = '42501';
  end if;

  if e.repartidor_id is not null then
    update public.repartidores set ocupado = false where id = e.repartidor_id;
  end if;

  update public.ofertas set respuesta = 'expirada', respondida_en = now()
   where envio_id = p_envio and respuesta is null;

  return e;
end;
$$;

-- Los grants se pierden al reemplazar una funcion con distinta firma, pero no
-- al usar create or replace sobre la misma. Se reafirman por las dudas.
revoke execute on all functions in schema public from public, anon;

grant execute on function
  public.crear_envio(text, double precision, double precision, text, text,
                     quien_paga, text, text),
  public.confirmar_envio(uuid),
  public.cancelar_envio(uuid, text),
  public.responder_oferta(uuid, boolean),
  public.avanzar_estado(uuid, estado_envio),
  public.confirmar_entrega(uuid, text),
  public.set_conectado(boolean),
  public.actualizar_ubicacion(double precision, double precision),
  public.cotizar(uuid, extensions.geography, extensions.geography, tipo_servicio),
  public.tarifario_vigente(uuid, tipo_servicio),
  public.distancia_ruta_km(extensions.geography, extensions.geography),
  public.transicion_valida(estado_envio, estado_envio),
  public.mi_rol(),
  public.es_admin(),
  public.mi_comercio_id(),
  public.mi_repartidor_id()
to authenticated;
