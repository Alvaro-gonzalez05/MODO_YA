-- 0066 - Lo que faltaba para que reclamos y documentacion tengan pantalla
--
-- Los hallazgos 6 y 7 de docs/hallazgos-de-la-revision.md decian lo mismo de
-- dos cosas distintas: backend entero, cero pantallas. Al construirlas
-- aparecieron cuatro huecos del modelo que no se podian tapar desde Dart.
--
-- Todo lo de este archivo es aditivo: no se borra ni se cambia nada de lo que
-- ya existia. `completar_reclamo` y `admin_validar_documento` siguen tal cual.

-- ---------------------------------------------------------------------------
-- 1. Un reclamo tambien es sobre un pedido, no solo sobre un envio
-- ---------------------------------------------------------------------------
--
-- `reclamos.envio_id` (0004:122) era el unico vinculo, y el envio del pedido
-- recien existe cuando el local lo acepta (0013:458). Justo los reclamos mas
-- probables son de pedidos que nunca llegaron a tener envio: el local los
-- rechazo, el cliente los cancelo o quedaron esperando el pago. Sin esta
-- columna el cliente abria un reclamo que la administracion no podia atar a
-- nada y tenia que adivinar de que pedido hablaba.

alter table public.reclamos
  add column pedido_id uuid references public.pedidos(id) on delete set null;

comment on column public.reclamos.pedido_id is
  'El pedido del que se reclama. Nulo si el reclamo es de un envio suelto (un mandado) o no es sobre ninguno en particular.';

create index reclamos_pedido_idx on public.reclamos (pedido_id);

-- 0016:56 dejo a `authenticated` escribir solo envio_id, motivo y detalle al
-- insertar; el resto lo pone el trigger. La columna nueva va en esa lista.
grant insert (pedido_id) on public.reclamos to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Un reclamo se abre sobre algo propio
-- ---------------------------------------------------------------------------
--
-- `reclamos_crear` (0008:169) solo controla que `abierto_por` sea el que
-- inserta, y de eso ya se encargaba el trigger. Nadie miraba a QUE apunta el
-- reclamo: con el pedido_id de arriba, cualquiera con cuenta podria abrir uno
-- sobre el pedido de otro y ensuciarle la ficha a un local que no lo atendio.
--
-- Va en un trigger nuevo y no modificando `completar_reclamo`, que sigue
-- siendo el que completa. Los triggers del mismo evento se disparan por orden
-- alfabetico de nombre, asi que `reclamos_completar` corre antes que
-- `reclamos_de_lo_mio` y este ya ve el rol_origen puesto.

create or replace function public.reclamo_sobre_algo_mio()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  -- La administracion abre reclamos en nombre de la operacion (los que entran
  -- por telefono), asi que no se le exige que el pedido sea suyo.
  if public.es_admin() then
    return new;
  end if;

  if new.pedido_id is not null and not exists (
    select 1 from public.pedidos p
     where p.id = new.pedido_id
       and (p.cliente_id  = public.mi_cliente_id()
         or p.comercio_id = public.mi_comercio_id())
  ) then
    raise exception 'Ese pedido no es tuyo' using errcode = '42501';
  end if;

  if new.envio_id is not null and not exists (
    select 1 from public.envios e
     where e.id = new.envio_id
       and (e.cliente_id    = public.mi_cliente_id()
         or e.comercio_id   = public.mi_comercio_id()
         or e.repartidor_id = public.mi_repartidor_id())
  ) then
    raise exception 'Ese envio no es tuyo' using errcode = '42501';
  end if;

  if coalesce(trim(new.motivo), '') = '' then
    raise exception 'Contanos que paso' using errcode = 'MY006';
  end if;

  return new;
end;
$$;

create trigger reclamos_de_lo_mio
  before insert on public.reclamos
  for each row execute function public.reclamo_sobre_algo_mio();

-- ---------------------------------------------------------------------------
-- 3. Un documento que se vuelve a subir vuelve a la cola
-- ---------------------------------------------------------------------------
--
-- 0016:46 le dejo al rider escribir `archivo_url` y `vence_en`, y nada mas:
-- `estado` es de la administracion. Bien pensado para que no se autoapruebe,
-- pero dejaba el caso del rechazo sin salida: el rider sacaba la foto de nuevo,
-- la subia, y el documento seguia diciendo "Rechazado" con la observacion
-- vieja. La administracion no tenia como enterarse de que habia algo nuevo que
-- mirar y el rider no tenia como pedir que lo miraran.
--
-- Cambiar el archivo ahora lo devuelve a 'pendiente' y limpia la observacion.
-- `admin_validar_documento` no toca `archivo_url`, asi que aprobar o rechazar
-- sigue funcionando igual.

create or replace function public.documento_vuelve_a_revision()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.archivo_url is distinct from old.archivo_url then
    new.estado       := 'pendiente';
    new.observacion  := null;
    new.validado_por := null;
    new.validado_en  := null;
  end if;
  return new;
end;
$$;

create trigger documentos_repartidor_a_revision
  before update on public.documentos_repartidor
  for each row execute function public.documento_vuelve_a_revision();

-- El bucket `documentos` es privado (0017:370), asi que lo que se guarda no es
-- una URL que se pueda abrir: es la ruta del objeto. Queda escrito para que la
-- proxima pantalla no intente mostrarla en un Image.network.
comment on column public.documentos_repartidor.archivo_url is
  'Ruta del archivo dentro del bucket privado `documentos` (<repartidor_id>/<Tipo>.jpg). No es una URL publica: la app pide un link firmado que vence.';

-- ---------------------------------------------------------------------------
-- 4. Las dos tablas avisan sus cambios
-- ---------------------------------------------------------------------------
--
-- Sin esto la administracion no ve entrar un reclamo hasta recargar, y el
-- rider no ve que le aprobaron el DNI aunque tenga la pantalla abierta.

do $$
declare t text;
begin
  foreach t in array array['reclamos', 'documentos_repartidor']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
