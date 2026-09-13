-- 0005 - Logica de negocio en el servidor
--
-- Todo lo que no puede depender de la app vive aca: el precio, las transiciones
-- de estado y la asignacion. Una app comprometida o desactualizada no tiene que
-- poder cobrar de menos ni saltear pasos.

-- ---------------------------------------------------------------------------
-- Identidad
-- ---------------------------------------------------------------------------

-- security definer para que las politicas de RLS puedan preguntar por el rol
-- sin entrar en recursion infinita al leer `perfiles`.

create or replace function public.mi_rol()
returns rol_usuario
language sql stable security definer set search_path = public
as $$ select rol from public.perfiles where id = auth.uid() $$;

create or replace function public.es_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (
  select 1 from public.perfiles where id = auth.uid() and rol = 'admin'
) $$;

create or replace function public.mi_comercio_id()
returns uuid
language sql stable security definer set search_path = public
as $$ select id from public.comercios where perfil_id = auth.uid() $$;

create or replace function public.mi_repartidor_id()
returns uuid
language sql stable security definer set search_path = public
as $$ select id from public.repartidores where perfil_id = auth.uid() $$;

-- ---------------------------------------------------------------------------
-- Distancia y cotizacion
-- ---------------------------------------------------------------------------

-- Distancia de recorrido estimada.
--
-- ST_Distance sobre geography da la linea recta. Una ruta urbana real siempre
-- es mas larga, asi que se aplica un factor de correccion. 1.3 es el valor de
-- arranque habitual para una traza de damero como la de Malargue; hay que
-- calibrarlo con los datos del piloto. Cuando integremos OSRM o Valhalla, esta
-- funcion pasa a consultar la ruta real y nadie mas se entera.
create or replace function public.distancia_ruta_km(
  p_origen  extensions.geography,
  p_destino extensions.geography
)
returns numeric
language sql immutable set search_path = public, extensions
as $$
  select round((extensions.ST_Distance(p_origen, p_destino) / 1000 * 1.3)::numeric, 2)
$$;

comment on function public.distancia_ruta_km is
  'Estimacion por linea recta x 1.3. Provisoria hasta integrar ruteo real.';

create or replace function public.tarifario_vigente(
  p_ciudad   uuid,
  p_servicio tipo_servicio default 'delivery'
)
returns public.tarifarios
language sql stable set search_path = public
as $$
  select * from public.tarifarios
  where ciudad_id = p_ciudad
    and servicio = p_servicio
    and vigente_hasta is null
  limit 1
$$;

-- Cotiza un envio. Es la unica fuente de verdad del precio.
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
      using errcode = 'P0002';
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
  -- 22 km/h promedio en zona urbana + 4 minutos fijos de retiro.
  minutos_estimados   := 4 + round(d / 22 * 60);
  return next;
end;
$$;

-- ---------------------------------------------------------------------------
-- Maquina de estados
-- ---------------------------------------------------------------------------

-- Espeja EstadoEnvio.transiciones de Dart. Las dos tienen que cambiar juntas,
-- pero la que manda es esta: la app solo la usa para no ofrecer botones
-- imposibles.
create or replace function public.transicion_valida(
  p_desde estado_envio,
  p_hacia estado_envio
)
returns boolean
language sql immutable
as $$
  select case p_desde
    when 'borrador'            then p_hacia in ('cotizado','cancelado')
    when 'cotizado'            then p_hacia in ('buscando_repartidor','cancelado')
    when 'buscando_repartidor' then p_hacia in ('asignado','sin_repartidor','cancelado')
    when 'asignado'            then p_hacia in ('en_local','cancelado')
    when 'en_local'            then p_hacia in ('retirado','cancelado')
    when 'retirado'            then p_hacia in ('en_camino','cancelado')
    when 'en_camino'           then p_hacia in ('entregado','cancelado')
    when 'sin_repartidor'      then p_hacia in ('buscando_repartidor','cancelado')
    else false
  end
$$;

-- Registra cada cambio de estado y sella la marca de tiempo que corresponda.
create or replace function public.registrar_cambio_estado()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.estado is distinct from old.estado then
    if not public.transicion_valida(old.estado, new.estado) then
      raise exception 'Transicion invalida: % -> %', old.estado, new.estado
        using errcode = 'P0001';
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

create trigger envios_registrar_estado
  before update of estado on public.envios
  for each row execute function public.registrar_cambio_estado();

-- ---------------------------------------------------------------------------
-- Operaciones del comercio
-- ---------------------------------------------------------------------------

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
      using errcode = 'P0002';
  end if;

  destino := extensions.ST_SetSRID(
    extensions.ST_MakePoint(p_destino_lng, p_destino_lat), 4326
  )::extensions.geography;

  -- El precio se calcula aca. La app manda direcciones, nunca importes.
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

-- Confirma la cotizacion y arranca la busqueda de cadetes.
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
      using errcode = 'P0002';
  end if;

  perform public.ofrecer_al_siguiente(p_envio);
  return e;
end;
$$;

-- ---------------------------------------------------------------------------
-- Motor de asignacion
-- ---------------------------------------------------------------------------

-- Cadetes elegibles ordenados por cercania al punto de retiro, salteando a los
-- que ya rechazaron o dejaron vencer una oferta de este mismo envio.
create or replace function public.repartidores_cercanos(p_envio uuid)
returns table (repartidor_id uuid, distancia_km numeric)
language sql stable security definer set search_path = public, extensions
as $$
  select r.id,
         round((extensions.ST_Distance(r.ultima_ubicacion, e.origen_ubicacion)
                / 1000)::numeric, 2)
  from public.envios e
  join public.tarifarios t on t.id = e.tarifario_id
  join public.repartidores r
    on r.ciudad_id = e.ciudad_id
   and r.estado_aprobacion = 'aprobado'
   and r.conectado
   and not r.ocupado
   and r.ultima_ubicacion is not null
   and extensions.ST_DWithin(
         r.ultima_ubicacion, e.origen_ubicacion, t.radio_busqueda_km * 1000
       )
  where e.id = p_envio
    and not exists (
      select 1 from public.ofertas o
      where o.envio_id = e.id and o.repartidor_id = r.id
    )
  order by 2
$$;

-- Ofrece el envio al cadete elegible mas cercano. Si no queda ninguno, el envio
-- pasa a `sin_repartidor` y el comercio decide si reintenta.
create or replace function public.ofrecer_al_siguiente(p_envio uuid)
returns public.ofertas
language plpgsql security definer set search_path = public
as $$
declare
  cand  record;
  segs  integer;
  nueva public.ofertas;
begin
  -- Si ya hay una oferta abierta y todavia no vencio, no hacemos nada.
  if exists (
    select 1 from public.ofertas
    where envio_id = p_envio and respuesta is null and expira_en > now()
  ) then
    return null;
  end if;

  select t.segundos_para_aceptar into segs
  from public.envios e join public.tarifarios t on t.id = e.tarifario_id
  where e.id = p_envio;

  select * into cand from public.repartidores_cercanos(p_envio) limit 1;

  if cand.repartidor_id is null then
    update public.envios set estado = 'sin_repartidor'
     where id = p_envio and estado = 'buscando_repartidor';
    return null;
  end if;

  insert into public.ofertas (
    envio_id, repartidor_id, distancia_al_retiro_km, expira_en
  ) values (
    p_envio, cand.repartidor_id, cand.distancia_km,
    now() + make_interval(secs => segs)
  ) returning * into nueva;

  return nueva;
end;
$$;

-- El cadete acepta o rechaza. Aceptar toma el envio de forma atomica: el
-- `where estado = 'buscando_repartidor'` es lo que evita que dos cadetes se
-- queden con el mismo pedido.
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
    raise exception 'La oferta no existe o ya fue respondida' using errcode = 'P0002';
  end if;

  if o.expira_en <= now() then
    update public.ofertas set respuesta = 'expirada', respondida_en = now()
     where id = o.id;
    perform public.ofrecer_al_siguiente(o.envio_id);
    raise exception 'La oferta vencio' using errcode = 'P0003';
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
    raise exception 'El envio ya no estaba disponible' using errcode = 'P0003';
  end if;

  update public.repartidores set ocupado = true where id = rep;
  return e;
end;
$$;

-- Cierra las ofertas vencidas y reintenta. Pensada para pg_cron cada 10 s.
create or replace function public.vencer_ofertas()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  o public.ofertas;
  n integer := 0;
begin
  for o in
    select * from public.ofertas
     where respuesta is null and expira_en <= now()
  loop
    update public.ofertas set respuesta = 'expirada', respondida_en = now()
     where id = o.id;
    perform public.ofrecer_al_siguiente(o.envio_id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Operaciones del cadete
-- ---------------------------------------------------------------------------

create or replace function public.avanzar_estado(
  p_envio uuid,
  p_nuevo estado_envio
)
returns public.envios
language plpgsql security definer set search_path = public
as $$
declare e public.envios;
begin
  -- La entrega no pasa por aca: exige el codigo del cliente.
  if p_nuevo = 'entregado' then
    raise exception 'Usa confirmar_entrega() para cerrar el envio'
      using errcode = '42501';
  end if;

  update public.envios set estado = p_nuevo
   where id = p_envio
     and repartidor_id = public.mi_repartidor_id()
  returning * into e;

  if e.id is null then
    raise exception 'El envio no existe o no es tuyo' using errcode = 'P0002';
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
    raise exception 'El envio no existe o no es tuyo' using errcode = 'P0002';
  end if;
  if e.codigo_entrega is distinct from p_codigo then
    raise exception 'El codigo de entrega no es correcto' using errcode = 'P0004';
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

create or replace function public.set_conectado(p_conectado boolean)
returns public.repartidores
language plpgsql security definer set search_path = public
as $$
declare r public.repartidores;
begin
  update public.repartidores
     set conectado = p_conectado,
         conectado_en = case when p_conectado then now() else conectado_en end
   where id = public.mi_repartidor_id()
     and estado_aprobacion = 'aprobado'
  returning * into r;

  if r.id is null then
    raise exception 'Tu cuenta todavia no esta aprobada' using errcode = '42501';
  end if;
  return r;
end;
$$;

-- Upsert de la ultima posicion. Se llama cada 10-15 s desde la app del cadete.
-- A proposito no guarda historico: el seguimiento en vivo va por Realtime
-- Broadcast y una tabla de pings crece sin control.
create or replace function public.actualizar_ubicacion(
  p_lat double precision,
  p_lng double precision
)
returns void
language sql security definer set search_path = public, extensions
as $$
  update public.repartidores
     set ultima_ubicacion = extensions.ST_SetSRID(
           extensions.ST_MakePoint(p_lng, p_lat), 4326
         )::extensions.geography,
         ultima_ubicacion_en = now()
   where id = public.mi_repartidor_id()
$$;

-- ---------------------------------------------------------------------------
-- Cancelacion
-- ---------------------------------------------------------------------------

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
