-- 0055 - El local pide el alta de un rider nuevo
--
-- 0051 dejo al local elegir sus riders de confianza, pero solo entre los que ya
-- tienen cuenta. Si el cadete de siempre todavia no esta en MODO YA, el local
-- no tenia como traerlo: tenia que llamar a la administracion.
--
-- Ahora lo pide desde la app con los datos y la documentacion del cadete. La
-- administracion lo revisa y, si lo aprueba, se crea la cuenta del rider y
-- queda vinculado al local en el mismo paso (la Edge Function
-- `admin-crear-usuario` con `solicitud_id`). Si lo rechaza, el local ve por que.
--
-- La documentacion va al bucket privado `documentos`, en
-- `solicitudes/<solicitud_id>/<archivo>`: el rider todavia no existe, asi que
-- no puede ir en la carpeta de su id.

create type public.estado_solicitud_rider as enum ('pendiente', 'aprobada', 'rechazada');

create table public.solicitudes_rider (
  id          uuid primary key default gen_random_uuid(),
  comercio_id uuid not null references public.comercios(id) on delete cascade,

  nombre      text not null check (length(trim(nombre)) between 2 and 80),
  telefono    text not null check (length(trim(telefono)) between 6 and 30),
  vehiculo    public.vehiculo not null,

  -- La documentacion no va en una columna: son los archivos de la carpeta
  -- `documentos/solicitudes/<id>/`, uno por tipo ("DNI.jpg"). Asi el local la
  -- sube despues de crear la solicitud sin necesitar permiso de update.
  nota       text check (nota is null or length(nota) <= 300),

  estado      public.estado_solicitud_rider not null default 'pendiente',
  motivo_rechazo text,
  -- La cuenta que se creo al aprobarla.
  repartidor_id  uuid references public.repartidores(id) on delete set null,
  resuelta_por   uuid references public.perfiles(id),
  resuelta_en    timestamptz,

  creado_en   timestamptz not null default now()
);

comment on table public.solicitudes_rider is
  'Un local pide el alta de un rider nuevo con su documentacion. Al aprobarse se crea la cuenta y queda vinculado al local.';

create index solicitudes_rider_comercio_idx on public.solicitudes_rider (comercio_id, creado_en desc);
create index solicitudes_rider_pendientes_idx on public.solicitudes_rider (creado_en) where estado = 'pendiente';

alter table public.solicitudes_rider enable row level security;

-- El local ve las suyas; la administracion, todas.
create policy solicitudes_rider_leer on public.solicitudes_rider
  for select to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

-- El local la crea, siempre pendiente y a su nombre. Resolverla es de la
-- administracion y va por la funcion de abajo o la Edge Function.
create policy solicitudes_rider_crear on public.solicitudes_rider
  for insert to authenticated
  with check (comercio_id = (select public.mi_comercio_id()) and estado = 'pendiente'
              and repartidor_id is null and resuelta_por is null);

-- Mientras este pendiente el local la puede retirar.
create policy solicitudes_rider_retirar on public.solicitudes_rider
  for delete to authenticated
  using (comercio_id = (select public.mi_comercio_id()) and estado = 'pendiente');

revoke update on public.solicitudes_rider from authenticated, anon;

-- ---------------------------------------------------------------------------
-- Rechazar
-- ---------------------------------------------------------------------------

create or replace function public.admin_rechazar_solicitud_rider(
  p_solicitud uuid,
  p_motivo    text
)
returns public.solicitudes_rider
language plpgsql security definer set search_path = public
as $$
declare s public.solicitudes_rider;
begin
  if not public.es_admin() then
    raise exception 'Solo la administracion resuelve solicitudes' using errcode = '42501';
  end if;
  if coalesce(trim(p_motivo), '') = '' then
    raise exception 'Decile al local por que no' using errcode = 'MY006';
  end if;

  update public.solicitudes_rider
     set estado = 'rechazada', motivo_rechazo = trim(p_motivo),
         resuelta_por = auth.uid(), resuelta_en = now()
   where id = p_solicitud and estado = 'pendiente'
  returning * into s;

  if s.id is null then
    raise exception 'La solicitud no existe o ya se resolvio' using errcode = 'MY004';
  end if;
  return s;
end;
$$;

revoke execute on function public.admin_rechazar_solicitud_rider(uuid, text) from public, anon;
grant execute on function public.admin_rechazar_solicitud_rider(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- La documentacion
-- ---------------------------------------------------------------------------
--
-- La sube el local que hace la solicitud y la lee el mismo local y la
-- administracion. El nombre del objeto es solicitudes/<solicitud_id>/<archivo>.

create policy documentos_solicitud_subir on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = 'solicitudes'
    and exists (
      select 1 from public.solicitudes_rider s
       where s.id::text = (storage.foldername(name))[2]
         and s.comercio_id = (select public.mi_comercio_id())
         and s.estado = 'pendiente'
    )
  );

create policy documentos_solicitud_leer on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documentos'
    and (storage.foldername(name))[1] = 'solicitudes'
    and exists (
      select 1 from public.solicitudes_rider s
       where s.id::text = (storage.foldername(name))[2]
         and s.comercio_id = (select public.mi_comercio_id())
    )
  );

-- Que el local se entere en vivo cuando se la resuelven, y la administracion
-- cuando entra una.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'solicitudes_rider'
  ) then
    alter publication supabase_realtime add table public.solicitudes_rider;
  end if;
end $$;
