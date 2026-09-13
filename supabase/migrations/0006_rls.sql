-- 0006 - Row Level Security
--
-- Regla de oro del documento (seccion 12): "la app debera limitar la exposicion
-- de datos personales a lo estrictamente necesario para completar el envio" y
-- "no mostrar datos completos del cliente a repartidores no asignados".
--
-- Todo arranca denegado. Cada politica abre lo minimo.

alter table public.perfiles              enable row level security;
alter table public.ciudades              enable row level security;
alter table public.zonas                 enable row level security;
alter table public.comercios             enable row level security;
alter table public.repartidores          enable row level security;
alter table public.documentos_exigidos   enable row level security;
alter table public.documentos_repartidor enable row level security;
alter table public.tarifarios            enable row level security;
alter table public.envios                enable row level security;
alter table public.envio_eventos         enable row level security;
alter table public.ofertas               enable row level security;
alter table public.pagos                 enable row level security;
alter table public.suscripciones         enable row level security;
alter table public.liquidaciones         enable row level security;
alter table public.liquidacion_items     enable row level security;
alter table public.reclamos              enable row level security;

-- ---------------------------------------------------------------------------
-- Perfiles
-- ---------------------------------------------------------------------------

create policy perfiles_ver_propio on public.perfiles
  for select to authenticated
  using (id = auth.uid() or public.es_admin());

create policy perfiles_editar_propio on public.perfiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy perfiles_admin_todo on public.perfiles
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------------------------------------------------------------------------
-- Catalogos: los lee cualquiera logueado, los escribe solo la administracion
-- ---------------------------------------------------------------------------

create policy ciudades_leer on public.ciudades
  for select to authenticated using (true);
create policy ciudades_admin on public.ciudades
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

create policy zonas_leer on public.zonas
  for select to authenticated using (true);
create policy zonas_admin on public.zonas
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

create policy documentos_exigidos_leer on public.documentos_exigidos
  for select to authenticated using (true);
create policy documentos_exigidos_admin on public.documentos_exigidos
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- El tarifario vigente lo necesitan las dos apps para mostrar el precio base.
create policy tarifarios_leer on public.tarifarios
  for select to authenticated using (true);
create policy tarifarios_admin on public.tarifarios
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------------------------------------------------------------------------
-- Comercios
-- ---------------------------------------------------------------------------

create policy comercios_ver_propio on public.comercios
  for select to authenticated
  using (
    perfil_id = auth.uid()
    or public.es_admin()
    -- El cadete con un envio activo de ese comercio necesita saber a donde va.
    or exists (
      select 1 from public.envios e
      where e.comercio_id = comercios.id
        and e.repartidor_id = public.mi_repartidor_id()
        and e.estado not in ('entregado','cancelado','sin_repartidor')
    )
  );

create policy comercios_editar_propio on public.comercios
  for update to authenticated
  using (perfil_id = auth.uid()) with check (perfil_id = auth.uid());

create policy comercios_admin on public.comercios
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------------------------------------------------------------------------
-- Repartidores
-- ---------------------------------------------------------------------------

create policy repartidores_ver_propio on public.repartidores
  for select to authenticated
  using (
    perfil_id = auth.uid()
    or public.es_admin()
    -- El comercio ve al cadete que tiene asignado su envio, y solo mientras
    -- ese envio esta en curso.
    or exists (
      select 1 from public.envios e
      where e.repartidor_id = repartidores.id
        and e.comercio_id = public.mi_comercio_id()
        and e.estado not in ('entregado','cancelado','sin_repartidor')
    )
  );

create policy repartidores_editar_propio on public.repartidores
  for update to authenticated
  using (perfil_id = auth.uid()) with check (perfil_id = auth.uid());

create policy repartidores_admin on public.repartidores
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

create policy documentos_repartidor_propios on public.documentos_repartidor
  for all to authenticated
  using (
    repartidor_id = public.mi_repartidor_id() or public.es_admin()
  )
  with check (
    repartidor_id = public.mi_repartidor_id() or public.es_admin()
  );

-- ---------------------------------------------------------------------------
-- Envios
--
-- El comercio ve los suyos. El cadete ve solo los que tiene asignados: hasta
-- que acepta, la oferta le llega por la vista `ofertas_abiertas`, que no expone
-- los datos personales del cliente.
-- ---------------------------------------------------------------------------

create policy envios_del_comercio on public.envios
  for select to authenticated
  using (comercio_id = public.mi_comercio_id());

create policy envios_del_repartidor on public.envios
  for select to authenticated
  using (repartidor_id = public.mi_repartidor_id());

create policy envios_admin on public.envios
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- Se escriben solo por RPC (crear_envio, avanzar_estado, confirmar_entrega...).
-- No hay politica de insert ni de update directo para comercio ni cadete a
-- proposito: asi nadie puede fijarse su propio precio ni saltear un estado.

create policy envio_eventos_leer on public.envio_eventos
  for select to authenticated
  using (
    public.es_admin()
    or exists (
      select 1 from public.envios e
      where e.id = envio_eventos.envio_id
        and (e.comercio_id = public.mi_comercio_id()
             or e.repartidor_id = public.mi_repartidor_id())
    )
  );

-- ---------------------------------------------------------------------------
-- Ofertas
-- ---------------------------------------------------------------------------

create policy ofertas_propias on public.ofertas
  for select to authenticated
  using (repartidor_id = public.mi_repartidor_id() or public.es_admin());

create policy ofertas_admin on public.ofertas
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- Lo que el cadete ve mientras decide si acepta.
--
-- Deliberadamente NO trae cliente_nombre, cliente_telefono ni
-- cliente_indicaciones: un cadete que todavia no acepto no tiene por que
-- conocer al destinatario. Esos datos aparecen recien cuando el envio queda
-- asignado y puede leer la fila de `envios`.
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
  e.origen_calle,
  e.origen_referencia,
  e.origen_ubicacion,
  e.destino_calle,
  e.destino_ubicacion,
  e.distancia_km,
  e.minutos_estimados,
  e.ganancia_repartidor,
  e.estado
from public.ofertas o
join public.envios e on e.id = o.envio_id
where o.respuesta is null
  and o.expira_en > now();

comment on view public.ofertas_abiertas is
  'Oferta sin datos personales del cliente: el cadete todavia no acepto.';

-- La vista es security_invoker, pero la politica de `envios` no le deja ver
-- filas que aun no son suyas. Esta politica extra abre exactamente esas filas
-- y nada mas: un envio que se le esta ofreciendo, y solo mientras dura.
create policy envios_ofrecidos on public.envios
  for select to authenticated
  using (
    exists (
      select 1 from public.ofertas o
      where o.envio_id = envios.id
        and o.repartidor_id = public.mi_repartidor_id()
        and o.respuesta is null
        and o.expira_en > now()
    )
  );

-- ---------------------------------------------------------------------------
-- Dinero
-- ---------------------------------------------------------------------------

create policy pagos_leer on public.pagos
  for select to authenticated
  using (
    public.es_admin()
    or exists (
      select 1 from public.envios e
      where e.id = pagos.envio_id and e.comercio_id = public.mi_comercio_id()
    )
  );

create policy pagos_admin on public.pagos
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

create policy suscripciones_propias on public.suscripciones
  for select to authenticated
  using (comercio_id = public.mi_comercio_id() or public.es_admin());

create policy suscripciones_admin on public.suscripciones
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

create policy liquidaciones_propias on public.liquidaciones
  for select to authenticated
  using (repartidor_id = public.mi_repartidor_id() or public.es_admin());

create policy liquidaciones_admin on public.liquidaciones
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

create policy liquidacion_items_leer on public.liquidacion_items
  for select to authenticated
  using (
    public.es_admin()
    or exists (
      select 1 from public.liquidaciones l
      where l.id = liquidacion_items.liquidacion_id
        and l.repartidor_id = public.mi_repartidor_id()
    )
  );

create policy liquidacion_items_admin on public.liquidacion_items
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------------------------------------------------------------------------
-- Reclamos
-- ---------------------------------------------------------------------------

create policy reclamos_propios on public.reclamos
  for select to authenticated
  using (abierto_por = auth.uid() or public.es_admin());

create policy reclamos_crear on public.reclamos
  for insert to authenticated
  with check (abierto_por = auth.uid());

create policy reclamos_admin on public.reclamos
  for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------------------------------------------------------------------------
-- Permisos de ejecucion
-- ---------------------------------------------------------------------------

-- Nada de esto tiene sentido sin sesion: se lo sacamos a anon explicitamente.
revoke execute on all functions in schema public from anon;

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
  public.mi_rol(),
  public.es_admin(),
  public.mi_comercio_id(),
  public.mi_repartidor_id()
to authenticated;

-- El motor de asignacion no lo dispara el cliente: lo llaman las funciones
-- internas y pg_cron.
revoke execute on function
  public.ofrecer_al_siguiente(uuid),
  public.vencer_ofertas(),
  public.repartidores_cercanos(uuid)
from authenticated;
