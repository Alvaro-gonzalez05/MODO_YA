-- 0014 - Row Level Security del marketplace

alter table public.clientes             enable row level security;
alter table public.direcciones_cliente  enable row level security;
alter table public.horarios_comercio    enable row level security;
alter table public.rubros               enable row level security;
alter table public.secciones_menu       enable row level security;
alter table public.productos            enable row level security;
alter table public.opciones_producto    enable row level security;
alter table public.opcion_items         enable row level security;
alter table public.favoritos            enable row level security;
alter table public.pedidos              enable row level security;
alter table public.pedido_items         enable row level security;
alter table public.pedido_item_opciones enable row level security;
alter table public.pedido_eventos       enable row level security;

-- ---------------------------------------------------------------------------
-- Clientes y sus direcciones
--
-- La libreta de direcciones es del cliente y de nadie mas. Ni el comercio ni el
-- cadete la ven: a ellos les llega copiada, en el pedido y en el envio, solo la
-- direccion de esa entrega.
-- ---------------------------------------------------------------------------

create policy clientes_leer on public.clientes
  for select to authenticated
  using (perfil_id = (select auth.uid()) or (select public.es_admin()));

create policy clientes_editar on public.clientes
  for update to authenticated
  using (perfil_id = (select auth.uid()) or (select public.es_admin()))
  with check (perfil_id = (select auth.uid()) or (select public.es_admin()));

create policy clientes_alta on public.clientes
  for insert to authenticated
  with check (perfil_id = (select auth.uid()) or (select public.es_admin()));

create policy clientes_admin_borrar on public.clientes
  for delete to authenticated using ((select public.es_admin()));

create policy direcciones_cliente_propias on public.direcciones_cliente
  for all to authenticated
  using (cliente_id = (select public.mi_cliente_id()) or (select public.es_admin()))
  with check (cliente_id = (select public.mi_cliente_id()) or (select public.es_admin()));

create policy favoritos_propios on public.favoritos
  for all to authenticated
  using (cliente_id = (select public.mi_cliente_id()))
  with check (cliente_id = (select public.mi_cliente_id()));

-- ---------------------------------------------------------------------------
-- Vidriera: catalogo publico para cualquier usuario logueado
--
-- Un cliente tiene que poder navegar comercios y menus antes de comprar. Se
-- abre solo lo de comercios aprobados: un comercio pendiente o suspendido no
-- aparece en el listado.
-- ---------------------------------------------------------------------------

create policy rubros_leer on public.rubros
  for select to authenticated using (true);
create policy rubros_admin_insert on public.rubros
  for insert to authenticated with check ((select public.es_admin()));
create policy rubros_admin_update on public.rubros
  for update to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy rubros_admin_delete on public.rubros
  for delete to authenticated using ((select public.es_admin()));

-- Los comercios aprobados pasan a ser visibles para todos. Se reemplaza la
-- politica de lectura anterior, que solo dejaba al dueno, al admin y al cadete
-- asignado.
drop policy if exists comercios_leer on public.comercios;

create policy comercios_leer on public.comercios
  for select to authenticated
  using (
    estado_aprobacion = 'aprobado'
    or perfil_id = (select auth.uid())
    or (select public.es_admin())
  );

-- Helper: el comercio dueno de una fila del catalogo, o la administracion.
-- Se repite la expresion en cada tabla porque RLS no admite funciones de
-- politica reutilizables con parametros de fila.

create policy horarios_leer on public.horarios_comercio
  for select to authenticated using (true);
create policy horarios_escribir on public.horarios_comercio
  for all to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()))
  with check (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy secciones_leer on public.secciones_menu
  for select to authenticated using (true);
create policy secciones_escribir on public.secciones_menu
  for all to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()))
  with check (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy productos_leer on public.productos
  for select to authenticated using (true);
create policy productos_escribir on public.productos
  for all to authenticated
  using (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()))
  with check (comercio_id = (select public.mi_comercio_id()) or (select public.es_admin()));

create policy opciones_leer on public.opciones_producto
  for select to authenticated using (true);
create policy opciones_escribir on public.opciones_producto
  for all to authenticated
  using (
    exists (
      select 1 from public.productos p
      where p.id = opciones_producto.producto_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  )
  with check (
    exists (
      select 1 from public.productos p
      where p.id = opciones_producto.producto_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

create policy opcion_items_leer on public.opcion_items
  for select to authenticated using (true);
create policy opcion_items_escribir on public.opcion_items
  for all to authenticated
  using (
    exists (
      select 1 from public.opciones_producto o
      join public.productos p on p.id = o.producto_id
      where o.id = opcion_items.opcion_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  )
  with check (
    exists (
      select 1 from public.opciones_producto o
      join public.productos p on p.id = o.producto_id
      where o.id = opcion_items.opcion_id
        and (p.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

-- ---------------------------------------------------------------------------
-- Pedidos
--
-- Lo ven el cliente que lo hizo, el comercio que lo prepara y la
-- administracion. El cadete NO: a el le corresponde el envio, que ya trae la
-- direccion de entrega y el telefono de contacto. Que productos pidio el
-- cliente y cuanto pago no es asunto suyo.
--
-- Se escriben solo por RPC (crear_pedido, aceptar_pedido, avanzar_pedido...):
-- no hay politica de insert ni de update directo para cliente ni comercio, para
-- que nadie pueda armarse un pedido con el precio que quiera.
-- ---------------------------------------------------------------------------

create policy pedidos_leer on public.pedidos
  for select to authenticated
  using (
    cliente_id = (select public.mi_cliente_id())
    or comercio_id = (select public.mi_comercio_id())
    or (select public.es_admin())
  );

create policy pedidos_admin_insert on public.pedidos
  for insert to authenticated with check ((select public.es_admin()));
create policy pedidos_admin_update on public.pedidos
  for update to authenticated
  using ((select public.es_admin())) with check ((select public.es_admin()));
create policy pedidos_admin_delete on public.pedidos
  for delete to authenticated using ((select public.es_admin()));

create policy pedido_items_leer on public.pedido_items
  for select to authenticated
  using (
    exists (
      select 1 from public.pedidos pe
      where pe.id = pedido_items.pedido_id
        and (pe.cliente_id = (select public.mi_cliente_id())
             or pe.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

create policy pedido_item_opciones_leer on public.pedido_item_opciones
  for select to authenticated
  using (
    exists (
      select 1 from public.pedido_items pi
      join public.pedidos pe on pe.id = pi.pedido_id
      where pi.id = pedido_item_opciones.pedido_item_id
        and (pe.cliente_id = (select public.mi_cliente_id())
             or pe.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

create policy pedido_eventos_leer on public.pedido_eventos
  for select to authenticated
  using (
    exists (
      select 1 from public.pedidos pe
      where pe.id = pedido_eventos.pedido_id
        and (pe.cliente_id = (select public.mi_cliente_id())
             or pe.comercio_id = (select public.mi_comercio_id())
             or (select public.es_admin()))
    )
  );

-- ---------------------------------------------------------------------------
-- Permisos de ejecucion de las funciones nuevas
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon;

grant execute on function
  -- cadeteria (0006/0009)
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
  public.mi_repartidor_id(),
  -- marketplace (0013)
  public.mi_cliente_id(),
  public.comercio_abierto(uuid),
  public.crear_pedido(uuid, uuid, jsonb, text),
  public.aceptar_pedido(uuid),
  public.rechazar_pedido(uuid, text),
  public.avanzar_pedido(uuid, estado_pedido),
  public.cancelar_pedido(uuid, text),
  public.transicion_pedido_valida(estado_pedido, estado_pedido)
to authenticated;

-- marcar_pedido_pagado queda sin grant a proposito: hoy valida por dentro que
-- quien llama sea admin, y cuando entre la pasarela la va a invocar una Edge
-- Function con service_role, no la app.
