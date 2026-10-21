-- 0065 - Cada uno ve su propia liquidación
--
-- Hasta acá la liquidación era un documento interno: `pendiente_de_liquidar_*`
-- y `detalle_de_liquidar_*` arrancan con `where public.es_admin()`, así que el
-- rider y el local podían leer el *resultado* (el RLS de `liquidaciones`,
-- `liquidaciones_comercio`, `cargos_comercio` y `cargos_repartidor` ya los
-- habilitaba) pero no podían ver **de qué se compone lo que están por cobrar**.
-- Para el que vive de eso es lo primero que quiere saber.
--
-- **Se abren las funciones que ya existen en vez de escribir unas nuevas.** El
-- comentario de 0063 explica por qué: el resumen y el detalle tienen que salir
-- del mismo filtro, o el día que uno cambie van a decir cosas distintas. Si
-- además hubiera una copia "para el rider", serían tres números que se pelean.
-- Por eso acá solo se amplía el `where`: `es_admin()` **o** el dueño de esos
-- datos. Un rider sigue sin poder pedir el detalle de otro, y un local el de
-- otro local: `mi_repartidor_id()` / `mi_comercio_id()` salen del JWT, no de un
-- parámetro.
--
-- Todo es aditivo: `create or replace` conservando la firma (nada de `drop`,
-- que rompería los grants y cualquier función que las llame).

-- ---------------------------------------------------------------------------
-- 1. El resumen del período: la administración ve a todos, cada uno se ve a sí
-- ---------------------------------------------------------------------------
--
-- Ojo con un detalle de forma: la condición `(t.envios is not null or
-- c.cargos is not null)` se mantiene tal cual porque es la que hace que la
-- bandeja de la administración liste solo a quien tiene algo para liquidar. La
-- consecuencia para las pantallas nuevas es que **un rider sin movimiento en el
-- período no recibe ninguna fila** (no una fila en cero), así que la pantalla
-- tiene que saber mostrar "todavía no hiciste nada" cuando no viene nada.

create or replace function public.pendiente_de_liquidar_riders(
  p_desde date,
  p_hasta date
)
returns table (
  repartidor_id uuid,
  rider         text,
  envios        integer,
  ganancias     integer,
  efectivo      integer,
  cargos        integer,
  total         integer
)
language sql stable security definer set search_path = public
as $$
  with trabajo as (
    select r.id as repartidor_id, r.nombre,
           count(e.id)::integer as envios,
           coalesce(sum(e.ganancia_repartidor), 0)::integer as ganancias,
           coalesce(sum(e.cobrar_al_entregar) filter (where e.cobro_metodo = 'efectivo'), 0)::integer as efectivo
      from public.repartidores r
      join public.envios e on e.repartidor_id = r.id
     where e.estado = 'entregado'
       and public.dia(e.entregado_en) between p_desde and p_hasta
       and not exists (select 1 from public.liquidacion_items li where li.envio_id = e.id)
     group by r.id, r.nombre
  ), cargos as (
    select c.repartidor_id, coalesce(sum(c.monto), 0)::integer as cargos
      from public.cargos_repartidor c
     where c.liquidacion_id is null and c.fecha between p_desde and p_hasta
     group by c.repartidor_id
  )
  select r.id, r.nombre,
         coalesce(t.envios, 0), coalesce(t.ganancias, 0),
         coalesce(t.efectivo, 0), coalesce(c.cargos, 0),
         coalesce(t.ganancias, 0) - coalesce(t.efectivo, 0) - coalesce(c.cargos, 0)
    from public.repartidores r
    left join trabajo t on t.repartidor_id = r.id
    left join cargos c on c.repartidor_id = r.id
   where ((select public.es_admin()) or r.id = (select public.mi_repartidor_id()))
     and (t.envios is not null or c.cargos is not null)
   order by r.nombre;
$$;

create or replace function public.pendiente_de_liquidar_comercios(
  p_desde date,
  p_hasta date
)
returns table (
  comercio_id uuid,
  comercio    text,
  pedidos     integer,
  ventas      integer,
  cargos      integer,
  total       integer
)
language sql stable security definer set search_path = public
as $$
  with ventas as (
    select p.comercio_id, count(*)::integer as pedidos, coalesce(sum(p.subtotal), 0)::integer as ventas
      from public.pedidos p
     where p.estado = 'entregado'
       and p.liquidacion_id is null
       and public.dia(p.entregado_en) between p_desde and p_hasta
     group by p.comercio_id
  ), cargos as (
    select x.comercio_id, sum(x.monto)::integer as cargos from (
      select c.comercio_id, c.monto
        from public.cargos_comercio c
       where c.liquidacion_id is null and c.fecha between p_desde and p_hasta
      union all
      -- Publicidad y envios regalados con Plus.
      select g.comercio_id, g.monto
        from public.campania_gastos g
       where g.liquidacion_id is null and g.fecha between p_desde and p_hasta
    ) x group by x.comercio_id
  )
  select co.id, co.nombre,
         coalesce(v.pedidos, 0), coalesce(v.ventas, 0), coalesce(c.cargos, 0),
         coalesce(v.ventas, 0) - coalesce(c.cargos, 0)
    from public.comercios co
    left join ventas v on v.comercio_id = co.id
    left join cargos c on c.comercio_id = co.id
   where ((select public.es_admin()) or co.id = (select public.mi_comercio_id()))
     and (v.pedidos is not null or c.cargos is not null)
   order by co.nombre;
$$;

-- ---------------------------------------------------------------------------
-- 2. El renglón por renglón del período en curso
-- ---------------------------------------------------------------------------
--
-- Mismo cuerpo que 0063; lo único que cambia es quién puede llamarlas.

create or replace function public.detalle_de_liquidar_rider(
  p_rider uuid,
  p_desde date,
  p_hasta date
)
returns table (
  envio_id    uuid,
  codigo      text,
  entregado   timestamptz,
  comercio    text,
  destino     text,
  ganancia    integer,
  efectivo    integer
)
language sql stable security definer set search_path = public
as $$
  select e.id, e.codigo, e.entregado_en,
         -- Un mandado no tiene local: lo pidió el cliente.
         coalesce(c.nombre, 'Mandado'),
         e.destino_calle,
         e.ganancia_repartidor,
         case when e.cobro_metodo = 'efectivo' then e.cobrar_al_entregar else 0 end
    from public.envios e
    left join public.comercios c on c.id = e.comercio_id
   where ((select public.es_admin()) or p_rider = (select public.mi_repartidor_id()))
     and e.repartidor_id = p_rider
     and e.estado = 'entregado'
     and public.dia(e.entregado_en) between p_desde and p_hasta
     and not exists (select 1 from public.liquidacion_items li where li.envio_id = e.id)
   order by e.entregado_en;
$$;

create or replace function public.detalle_de_liquidar_comercio(
  p_comercio uuid,
  p_desde    date,
  p_hasta    date
)
returns table (
  pedido_id  uuid,
  codigo     text,
  entregado  timestamptz,
  cliente    text,
  productos  integer
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.codigo, p.entregado_en, p.cliente_nombre, p.subtotal
    from public.pedidos p
   where ((select public.es_admin()) or p_comercio = (select public.mi_comercio_id()))
     and p.comercio_id = p_comercio
     and p.estado = 'entregado'
     and p.liquidacion_id is null
     and public.dia(p.entregado_en) between p_desde and p_hasta
   order by p.entregado_en;
$$;

-- ---------------------------------------------------------------------------
-- 3. Los descuentos del período, con el mismo filtro que el resumen
-- ---------------------------------------------------------------------------
--
-- Antes la hoja de la administración leía `cargos_repartidor` derecho y
-- filtraba por fecha en la app. Eso dejaba entrar cargos de ese período que ya
-- se habían liquidado en un cierre anterior: el renglón aparecía pero el
-- resumen no lo contaba, y la resta no cerraba. Acá el filtro es exactamente el
-- del resumen (`liquidacion_id is null` y la fecha dentro del período), que es
-- lo que hace que los dos números sean el mismo número.

create or replace function public.cargos_a_liquidar_rider(
  p_rider uuid,
  p_desde date,
  p_hasta date
)
returns table (
  fecha    date,
  concepto text,
  detalle  text,
  monto    integer
)
language sql stable security definer set search_path = public
as $$
  select c.fecha, c.concepto::text, c.detalle, c.monto
    from public.cargos_repartidor c
   where ((select public.es_admin()) or p_rider = (select public.mi_repartidor_id()))
     and c.repartidor_id = p_rider
     and c.liquidacion_id is null
     and c.fecha between p_desde and p_hasta
   order by c.fecha, c.creado_en;
$$;

-- Al local se le descuentan dos cosas que viven en tablas distintas: los cargos
-- que le carga la administración (mensualidad, publicidad contratada y la
-- penalidad por rechazar un pedido ya cobrado, que entra como `ajuste`) y lo
-- que gastaron sus campañas (la publicidad diaria y los envíos que regaló con
-- Plus). El resumen suma las dos; si la pantalla mostrara solo una, el local
-- iba a reclamar la diferencia con razón.
create or replace function public.cargos_a_liquidar_comercio(
  p_comercio uuid,
  p_desde    date,
  p_hasta    date
)
returns table (
  fecha    date,
  concepto text,
  detalle  text,
  monto    integer
)
language sql stable security definer set search_path = public
as $$
  select x.fecha, x.concepto, x.detalle, x.monto
    from (
      select c.fecha, c.concepto::text as concepto, c.detalle, c.monto, c.creado_en
        from public.cargos_comercio c
       where c.comercio_id = p_comercio
         and c.liquidacion_id is null
         and c.fecha between p_desde and p_hasta
      union all
      select g.fecha, 'campania'::text, g.detalle, g.monto, g.creado_en
        from public.campania_gastos g
       where g.comercio_id = p_comercio
         and g.liquidacion_id is null
         and g.fecha between p_desde and p_hasta
    ) x
   where ((select public.es_admin()) or p_comercio = (select public.mi_comercio_id()))
   order by x.fecha, x.creado_en;
$$;

-- ---------------------------------------------------------------------------
-- 4. El detalle de una liquidación ya cerrada
-- ---------------------------------------------------------------------------
--
-- El historial sin detalle es un número suelto: tres semanas después nadie se
-- acuerda qué entró en "$84.500 del 1 al 7". Va en una sola función por rol y
-- con los renglones de las dos secciones juntos (`seccion` los separa) porque
-- es un comprobante de algo que ya pasó: se lee y se imprime completo, no se
-- consulta una parte sin la otra.
--
-- El permiso no se chequea contra el parámetro sino contra la liquidación: el
-- que la pide tiene que ser su dueño.

create or replace function public.renglones_de_liquidacion_rider(p_liquidacion uuid)
returns table (
  seccion text,
  titulo  text,
  cuando  timestamptz,
  detalle text,
  monto   integer
)
language sql stable security definer set search_path = public
as $$
  with mia as (
    select l.id
      from public.liquidaciones l
     where l.id = p_liquidacion
       and ((select public.es_admin()) or l.repartidor_id = (select public.mi_repartidor_id()))
  )
  select 'envios'::text,
         e.codigo || ' · ' || coalesce(c.nombre, 'Mandado'),
         e.entregado_en,
         e.destino_calle,
         i.monto
    from public.liquidacion_items i
    join public.envios e on e.id = i.envio_id
    left join public.comercios c on c.id = e.comercio_id
   where i.liquidacion_id in (select id from mia)
  union all
  select 'cargos'::text, ca.concepto::text, ca.fecha::timestamptz, ca.detalle, ca.monto
    from public.cargos_repartidor ca
   where ca.liquidacion_id in (select id from mia)
  order by 1 desc, 3;
$$;

create or replace function public.renglones_de_liquidacion_comercio(p_liquidacion uuid)
returns table (
  seccion text,
  titulo  text,
  cuando  timestamptz,
  detalle text,
  monto   integer
)
language sql stable security definer set search_path = public
as $$
  with mia as (
    select l.id
      from public.liquidaciones_comercio l
     where l.id = p_liquidacion
       and ((select public.es_admin()) or l.comercio_id = (select public.mi_comercio_id()))
  )
  select 'pedidos'::text, p.codigo, p.entregado_en, p.cliente_nombre, p.subtotal
    from public.pedidos p
   where p.liquidacion_id in (select id from mia)
  union all
  select 'cargos'::text, c.concepto::text, c.fecha::timestamptz, c.detalle, c.monto
    from public.cargos_comercio c
   where c.liquidacion_id in (select id from mia)
  union all
  select 'cargos'::text, 'campania'::text, g.fecha::timestamptz, g.detalle, g.monto
    from public.campania_gastos g
   where g.liquidacion_id in (select id from mia)
  order by 1 desc, 3;
$$;

-- ---------------------------------------------------------------------------
-- 5. Permisos
-- ---------------------------------------------------------------------------
--
-- Las cuatro funciones de los puntos 1 y 2 ya tenían su grant (0035, 0062,
-- 0063) y `create or replace` no lo toca. Las nuevas nacen abiertas a PUBLIC si
-- no se les revoca (ver 0008).

revoke execute on function public.cargos_a_liquidar_rider(uuid, date, date) from public, anon;
revoke execute on function public.cargos_a_liquidar_comercio(uuid, date, date) from public, anon;
revoke execute on function public.renglones_de_liquidacion_rider(uuid) from public, anon;
revoke execute on function public.renglones_de_liquidacion_comercio(uuid) from public, anon;

grant execute on function public.cargos_a_liquidar_rider(uuid, date, date) to authenticated;
grant execute on function public.cargos_a_liquidar_comercio(uuid, date, date) to authenticated;
grant execute on function public.renglones_de_liquidacion_rider(uuid) to authenticated;
grant execute on function public.renglones_de_liquidacion_comercio(uuid) to authenticated;

comment on function public.cargos_a_liquidar_rider(uuid, date, date) is
  'Lo que se le descuenta a un rider en el periodo. Mismo filtro que pendiente_de_liquidar_riders.';
comment on function public.cargos_a_liquidar_comercio(uuid, date, date) is
  'Cargos y gastos de campania de un local en el periodo. Mismo filtro que pendiente_de_liquidar_comercios.';

-- ---------------------------------------------------------------------------
-- 6. En vivo
-- ---------------------------------------------------------------------------
--
-- `cargos_repartidor` (0062) quedó afuera de la publicación: la pantalla se
-- suscribía a una tabla que nunca emite, así que un cargo nuevo no aparecía
-- hasta volver a entrar. Ahora que el rider mira esa pantalla para saber cuánto
-- cobra, se nota.

do $$
declare t text;
begin
  foreach t in array array['cargos_repartidor']
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;
