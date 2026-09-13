-- 0008 - Correcciones de seguridad y rendimiento
--
-- Salidas del advisor de Supabase sobre las migraciones anteriores. Se aplican
-- ahora, con la base vacia, que es cuando sale gratis.

-- ---------------------------------------------------------------------------
-- 1. La vista saltaba RLS  [ERROR]
--
-- En Postgres una vista corre por defecto con los permisos de quien la creo
-- (postgres), no de quien la consulta: eso le permite leer filas que RLS deberia
-- ocultar. `ofertas_abiertas` ya se habia creado con security_invoker, pero a
-- esta se me paso.
-- ---------------------------------------------------------------------------

alter view public.comercios_con_suscripcion set (security_invoker = true);

-- ---------------------------------------------------------------------------
-- 2. Ejecucion publica de funciones SECURITY DEFINER  [WARN, pero real]
--
-- Postgres le da EXECUTE a PUBLIC por defecto sobre toda funcion nueva.
-- Revocarselo solo a `anon` no sirve de nada, porque `anon` hereda de PUBLIC.
-- Hay que revocarle a PUBLIC y recien despues otorgar a `authenticated` lo que
-- corresponde.
--
-- Sin esto, cualquiera sin loguearse podia llamar `vencer_ofertas()` o
-- `repartidores_cercanos()`, que corren como postgres.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;

-- Que las funciones que se creen de aca en mas no vuelvan a nacer abiertas.
alter default privileges in schema public revoke execute on functions from public;

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

-- El motor de asignacion y el vencimiento de ofertas no los dispara nadie desde
-- afuera: los llaman las funciones internas y pg_cron.
--   ofrecer_al_siguiente, repartidores_cercanos, vencer_ofertas,
--   registrar_cambio_estado, tocar_actualizado_en
-- quedan sin grant a proposito.

-- ---------------------------------------------------------------------------
-- 3. search_path mutable  [WARN]
--
-- Una funcion sin search_path fijo puede ser secuestrada por un esquema puesto
-- adelante por el que la llama.
-- ---------------------------------------------------------------------------

alter function public.tocar_actualizado_en() set search_path = public;
alter function public.transicion_valida(estado_envio, estado_envio) set search_path = public;

-- ---------------------------------------------------------------------------
-- 4. auth.uid() por fila  [WARN de rendimiento]
--
-- Dentro de una politica, `auth.uid()` se evalua una vez POR FILA. Envuelto en
-- un subselect, el planner lo trata como constante y lo resuelve una sola vez.
-- Con pocos registros da igual; con un historial de envios de un ano, no.
--
-- De paso se unifican las politicas duplicadas: tener `X_admin FOR ALL` y
-- `X_propio FOR SELECT` al mismo tiempo obliga a Postgres a evaluar las dos en
-- cada consulta. Se fusionan en una de lectura y una de escritura.
-- ---------------------------------------------------------------------------

-- Perfiles
drop policy if exists perfiles_ver_propio    on public.perfiles;
drop policy if exists perfiles_editar_propio on public.perfiles;
drop policy if exists perfiles_admin_todo    on public.perfiles;

create policy perfiles_leer on public.perfiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.es_admin()));

create policy perfiles_editar on public.perfiles
  for update to authenticated
  using (id = (select auth.uid()) or (select public.es_admin()))
  with check (id = (select auth.uid()) or (select public.es_admin()));

create policy perfiles_admin_escribir on public.perfiles
  for insert to authenticated
  with check ((select public.es_admin()));

create policy perfiles_admin_borrar on public.perfiles
  for delete to authenticated
  using ((select public.es_admin()));

-- Comercios
drop policy if exists comercios_ver_propio    on public.comercios;
drop policy if exists comercios_editar_propio on public.comercios;
drop policy if exists comercios_admin         on public.comercios;

create policy comercios_leer on public.comercios
  for select to authenticated
  using (
    perfil_id = (select auth.uid())
    or (select public.es_admin())
    or exists (
      select 1 from public.envios e
      where e.comercio_id = comercios.id
        and e.repartidor_id = (select public.mi_repartidor_id())
        and e.estado not in ('entregado','cancelado','sin_repartidor')
    )
  );

create policy comercios_editar on public.comercios
  for update to authenticated
  using (perfil_id = (select auth.uid()) or (select public.es_admin()))
  with check (perfil_id = (select auth.uid()) or (select public.es_admin()));

create policy comercios_admin_escribir on public.comercios
  for insert to authenticated with check ((select public.es_admin()));
create policy comercios_admin_borrar on public.comercios
  for delete to authenticated using ((select public.es_admin()));

-- Repartidores
drop policy if exists repartidores_ver_propio    on public.repartidores;
drop policy if exists repartidores_editar_propio on public.repartidores;
drop policy if exists repartidores_admin         on public.repartidores;

create policy repartidores_leer on public.repartidores
  for select to authenticated
  using (
    perfil_id = (select auth.uid())
    or (select public.es_admin())
    or exists (
      select 1 from public.envios e
      where e.repartidor_id = repartidores.id
        and e.comercio_id = (select public.mi_comercio_id())
        and e.estado not in ('entregado','cancelado','sin_repartidor')
    )
  );

create policy repartidores_editar on public.repartidores
  for update to authenticated
  using (perfil_id = (select auth.uid()) or (select public.es_admin()))
  with check (perfil_id = (select auth.uid()) or (select public.es_admin()));

create policy repartidores_admin_escribir on public.repartidores
  for insert to authenticated with check ((select public.es_admin()));
create policy repartidores_admin_borrar on public.repartidores
  for delete to authenticated using ((select public.es_admin()));

-- Reclamos
drop policy if exists reclamos_propios on public.reclamos;
drop policy if exists reclamos_crear   on public.reclamos;
drop policy if exists reclamos_admin   on public.reclamos;

create policy reclamos_leer on public.reclamos
  for select to authenticated
  using (abierto_por = (select auth.uid()) or (select public.es_admin()));

create policy reclamos_crear on public.reclamos
  for insert to authenticated
  with check (abierto_por = (select auth.uid()) or (select public.es_admin()));

create policy reclamos_admin_editar on public.reclamos
  for update to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy reclamos_admin_borrar on public.reclamos
  for delete to authenticated using ((select public.es_admin()));

-- Catalogos: se unifica lectura + escritura admin en una sola politica de cada
-- tipo para no evaluar dos veces.
drop policy if exists ciudades_leer  on public.ciudades;
drop policy if exists ciudades_admin on public.ciudades;
create policy ciudades_leer on public.ciudades
  for select to authenticated using (true);
create policy ciudades_escribir on public.ciudades
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

drop policy if exists zonas_leer  on public.zonas;
drop policy if exists zonas_admin on public.zonas;
create policy zonas_leer on public.zonas
  for select to authenticated using (true);
create policy zonas_escribir on public.zonas
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

drop policy if exists documentos_exigidos_leer  on public.documentos_exigidos;
drop policy if exists documentos_exigidos_admin on public.documentos_exigidos;
create policy documentos_exigidos_leer on public.documentos_exigidos
  for select to authenticated using (true);
create policy documentos_exigidos_escribir on public.documentos_exigidos
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

drop policy if exists tarifarios_leer  on public.tarifarios;
drop policy if exists tarifarios_admin on public.tarifarios;
create policy tarifarios_leer on public.tarifarios
  for select to authenticated using (true);
create policy tarifarios_escribir on public.tarifarios
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- Envios: cuatro politicas de SELECT se fusionan en una.
drop policy if exists envios_del_comercio   on public.envios;
drop policy if exists envios_del_repartidor on public.envios;
drop policy if exists envios_ofrecidos      on public.envios;
drop policy if exists envios_admin          on public.envios;

create policy envios_leer on public.envios
  for select to authenticated
  using (
    comercio_id = (select public.mi_comercio_id())
    or repartidor_id = (select public.mi_repartidor_id())
    or (select public.es_admin())
    -- Un envio que se le esta ofreciendo ahora mismo a este cadete.
    or exists (
      select 1 from public.ofertas o
      where o.envio_id = envios.id
        and o.repartidor_id = (select public.mi_repartidor_id())
        and o.respuesta is null
        and o.expira_en > now()
    )
  );

create policy envios_admin_escribir on public.envios
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- Resto de tablas
drop policy if exists documentos_repartidor_propios on public.documentos_repartidor;
create policy documentos_repartidor_propios on public.documentos_repartidor
  for all to authenticated
  using (repartidor_id = (select public.mi_repartidor_id()) or (select public.es_admin()))
  with check (repartidor_id = (select public.mi_repartidor_id()) or (select public.es_admin()));

drop policy if exists envio_eventos_leer on public.envio_eventos;
create policy envio_eventos_leer on public.envio_eventos
  for select to authenticated
  using (
    (select public.es_admin())
    or exists (
      select 1 from public.envios e
      where e.id = envio_eventos.envio_id
        and (e.comercio_id = (select public.mi_comercio_id())
             or e.repartidor_id = (select public.mi_repartidor_id()))
    )
  );

drop policy if exists ofertas_propias on public.ofertas;
drop policy if exists ofertas_admin   on public.ofertas;
create policy ofertas_leer on public.ofertas
  for select to authenticated
  using (repartidor_id = (select public.mi_repartidor_id()) or (select public.es_admin()));
create policy ofertas_admin_escribir on public.ofertas
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

drop policy if exists pagos_leer  on public.pagos;
drop policy if exists pagos_admin on public.pagos;
create policy pagos_leer on public.pagos
  for select to authenticated
  using (
    (select public.es_admin())
    or exists (
      select 1 from public.envios e
      where e.id = pagos.envio_id and e.comercio_id = (select public.mi_comercio_id())
    )
  );
create policy pagos_admin_escribir on public.pagos
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

drop policy if exists suscripciones_propias on public.suscripciones;
drop policy if exists suscripciones_admin   on public.suscripciones;
create policy suscripciones_leer on public.suscripciones
  for select to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));
create policy suscripciones_admin_escribir on public.suscripciones
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

drop policy if exists liquidaciones_propias on public.liquidaciones;
drop policy if exists liquidaciones_admin   on public.liquidaciones;
create policy liquidaciones_leer on public.liquidaciones
  for select to authenticated
  using (repartidor_id = (select public.mi_repartidor_id()) or (select public.es_admin()));
create policy liquidaciones_admin_escribir on public.liquidaciones
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

drop policy if exists liquidacion_items_leer  on public.liquidacion_items;
drop policy if exists liquidacion_items_admin on public.liquidacion_items;
create policy liquidacion_items_leer on public.liquidacion_items
  for select to authenticated
  using (
    (select public.es_admin())
    or exists (
      select 1 from public.liquidaciones l
      where l.id = liquidacion_items.liquidacion_id
        and l.repartidor_id = (select public.mi_repartidor_id())
    )
  );
create policy liquidacion_items_admin_escribir on public.liquidacion_items
  for all to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));

-- ---------------------------------------------------------------------------
-- 5. Claves foraneas sin indice  [INFO]
--
-- Sin indice, cada borrado o actualizacion en la tabla referenciada obliga a un
-- scan completo de la que referencia.
-- ---------------------------------------------------------------------------

create index if not exists comercios_aprobado_por_idx
  on public.comercios (aprobado_por);
create index if not exists repartidores_aprobado_por_idx
  on public.repartidores (aprobado_por);
create index if not exists documentos_repartidor_validado_por_idx
  on public.documentos_repartidor (validado_por);
create index if not exists envio_eventos_actor_idx
  on public.envio_eventos (actor_id);
create index if not exists envios_cancelado_por_idx
  on public.envios (cancelado_por);
create index if not exists envios_tarifario_idx
  on public.envios (tarifario_id);
create index if not exists liquidaciones_pago_idx
  on public.liquidaciones (pago_id);
create index if not exists suscripciones_pago_idx
  on public.suscripciones (pago_id);
create index if not exists reclamos_abierto_por_idx
  on public.reclamos (abierto_por);
create index if not exists reclamos_resuelto_por_idx
  on public.reclamos (resuelto_por);
create index if not exists tarifarios_creado_por_idx
  on public.tarifarios (creado_por);
