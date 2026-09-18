-- 0024 - Carteles del inicio del cliente
--
-- El banner negro del home ("El mejor sabor, en tu casa / Delivery rapido,
-- simple y local") estaba escrito en la app. La administracion lo edita
-- desde el panel y el cambio se ve en todos los celulares sin publicar una
-- version nueva. Puede haber varios: el cliente los pasa deslizando.

create table public.carteles (
  id        uuid primary key default gen_random_uuid(),
  titulo    text not null check (length(titulo) between 1 and 80),
  subtitulo text not null default '' check (length(subtitulo) <= 120),
  activo    boolean not null default true,
  orden     smallint not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

comment on table public.carteles is
  'Carteles del inicio del cliente. Los edita la administracion; el cliente ve solo los activos, por orden.';

create trigger carteles_tocar
  before update on public.carteles
  for each row execute function public.tocar_actualizado_en();

alter table public.carteles enable row level security;

-- Todos los que entran a la app los ven; solo la administracion los toca.
create policy carteles_leer on public.carteles
  for select to authenticated using (true);
create policy carteles_admin_insert on public.carteles
  for insert to authenticated with check ((select public.es_admin()));
create policy carteles_admin_update on public.carteles
  for update to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy carteles_admin_delete on public.carteles
  for delete to authenticated using ((select public.es_admin()));

-- El home del cliente se actualiza en vivo cuando la administracion edita.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'carteles'
  ) then
    alter publication supabase_realtime add table public.carteles;
  end if;
end $$;

-- El cartel que la app traia escrito, para que el home no quede vacio.
insert into public.carteles (titulo, subtitulo, orden)
values ('El mejor sabor,
en tu casa', 'Delivery rápido, simple y local', 0);
