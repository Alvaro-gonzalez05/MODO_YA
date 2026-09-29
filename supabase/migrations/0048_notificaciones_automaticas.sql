-- 0048 - Notificaciones automaticas: carrito abandonado y clientes dormidos
--
-- 0047 dejo a la administracion escribir y mandar a mano. Dos mensajes no
-- conviene mandarlos a mano, porque llegan tarde o no llegan:
--
--   * **Carrito abandonado.** El cliente armo el pedido, eligio tarjeta y se
--     fue de la pantalla de pago. El pedido queda en `pendiente_pago` y a los
--     30 minutos lo cierra `cerrar_pagos_vencidos()`. O sea que la ventana para
--     recuperarlo es corta: el aviso tiene que salir **mientras todavia se
--     puede pagar**, y por eso lleva derecho a la pantalla de pago de ese
--     pedido. Hoy esa pantalla no tiene ningun otro camino de vuelta.
--
--   * **Cliente dormido.** Hace N dias que no pide. Aca no hay apuro, pero si
--     riesgo de cansarlo: no se le vuelve a escribir hasta pasados
--     `repetir_cada_dias`.
--
-- Una automatizacion **es** una notificacion (misma tabla): se escribe una vez
-- y se le van colgando envios. Asi la administracion ve una sola fila que dice
-- "Carrito abandonado - automatica - llego a 137, la abrieron 41" en vez de una
-- fila nueva por cada vez que el cron la dispara.

create type public.disparador_notificacion as enum (
  'carrito_abandonado',
  'cliente_inactivo'
);

alter table public.notificaciones
  -- Nulo = la escribio y la mando alguien. No nulo = la manda el reloj.
  add column disparador public.disparador_notificacion,
  add column activa boolean not null default true,
  -- Carrito abandonado: cuanto se espera antes de escribirle. Tiene que ser
  -- menos que los 30 minutos que tarda en cancelarse el pedido.
  add column minutos_espera smallint not null default 10
    check (minutos_espera between 1 and 25),
  -- Cliente dormido: cada cuanto, como mucho, se le puede volver a escribir.
  add column repetir_cada_dias smallint not null default 30
    check (repetir_cada_dias between 1 and 365);

comment on column public.notificaciones.disparador is
  'Nulo: la manda una persona. Si no, la dispara el cron cuando se cumple la condicion.';

-- Una sola automatizacion prendida por disparador: si hubiera dos, el cliente
-- recibiria dos mensajes por el mismo motivo.
create unique index notificaciones_un_disparador_activo
  on public.notificaciones (disparador)
  where disparador is not null and activa;

-- ---------------------------------------------------------------------------
-- 1. El envio recuerda por que se mando
-- ---------------------------------------------------------------------------

alter table public.notificacion_envios
  add column pedido_id uuid references public.pedidos(id) on delete cascade;

comment on column public.notificacion_envios.pedido_id is
  'El pedido que motivo el aviso (carrito abandonado). Sirve para no repetirlo y para abrir el pago de ese pedido.';

-- La condicion de "no repetir" ya no es una sola: el mensaje a mano se manda
-- una vez por persona, el de carrito abandonado una vez por pedido, y el del
-- cliente dormido puede repetirse cada tanto a la misma persona. Con una regla
-- sola no entran los tres, asi que cada funcion que manda hace su propio
-- control y aca queda solo lo que es siempre cierto.
alter table public.notificacion_envios
  drop constraint notificacion_envios_notificacion_id_perfil_id_key;

create unique index notificacion_envios_un_pedido
  on public.notificacion_envios (notificacion_id, pedido_id)
  where pedido_id is not null;

-- ---------------------------------------------------------------------------
-- 2. El segmento, sin el candado de administracion
-- ---------------------------------------------------------------------------
--
-- `destinatarios()` exige es_admin(), que es lo correcto cuando la llama una
-- pantalla. El cron no es nadie: corre sin sesion, asi que esa verificacion le
-- daria siempre falso y no encontraria a nadie. Se separa la cuenta (quien
-- entra en el segmento) del permiso (quien puede preguntarlo), para no tener
-- dos copias de la misma regla que despues se separan.

create or replace function public.perfiles_del_segmento(
  p_segmento public.segmento_notificacion,
  p_dias     integer default 30
)
returns table (perfil_id uuid)
language sql stable security definer set search_path = public
as $$
  select p.id
    from public.perfiles p
   where case p_segmento
           when 'todos' then
             exists (select 1 from public.clientes c where c.perfil_id = p.id)
             or exists (select 1 from public.comercios co
                         where co.perfil_id = p.id and co.estado_aprobacion = 'aprobado')
             or exists (select 1 from public.repartidores r
                         where r.perfil_id = p.id and r.estado_aprobacion = 'aprobado')

           when 'clientes' then
             exists (select 1 from public.clientes c where c.perfil_id = p.id)

           when 'clientes_plus' then
             exists (select 1 from public.clientes c
                      where c.perfil_id = p.id and public.tiene_plus(c.id))

           when 'clientes_inactivos' then
             exists (
               select 1 from public.clientes c
                where c.perfil_id = p.id
                  and coalesce(
                        (select max(pe.creado_en) from public.pedidos pe where pe.cliente_id = c.id),
                        c.creado_en
                      ) < now() - make_interval(days => p_dias)
             )

           when 'comercios' then
             exists (select 1 from public.comercios co
                      where co.perfil_id = p.id and co.estado_aprobacion = 'aprobado')

           when 'riders' then
             exists (select 1 from public.repartidores r
                      where r.perfil_id = p.id and r.estado_aprobacion = 'aprobado')
         end;
$$;

-- Ahora `destinatarios` es el permiso, y la cuenta esta en un solo lugar.
create or replace function public.destinatarios(
  p_segmento public.segmento_notificacion,
  p_dias     integer default 30
)
returns table (perfil_id uuid)
language sql stable security definer set search_path = public
as $$
  select s.perfil_id from public.perfiles_del_segmento(p_segmento, p_dias) s
   where public.es_admin();
$$;

-- ---------------------------------------------------------------------------
-- 3. Carrito abandonado
-- ---------------------------------------------------------------------------

create or replace function public.avisar_carritos_abandonados()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n public.notificaciones;
  cuantos integer := 0;
begin
  select * into n from public.notificaciones
   where disparador = 'carrito_abandonado' and activa
   limit 1;
  if n.id is null then return 0; end if;

  insert into public.notificacion_envios (notificacion_id, perfil_id, pedido_id)
  select n.id, c.perfil_id, p.id
    from public.pedidos p
    join public.clientes c on c.id = p.cliente_id
   where p.estado = 'pendiente_pago'
     and p.creado_en < now() - make_interval(mins => n.minutos_espera)
  -- El indice unico por (notificacion, pedido) tapa la carrera si el cron se
  -- superpone consigo mismo.
  on conflict do nothing;

  get diagnostics cuantos = row_count;

  if cuantos > 0 then
    update public.notificaciones
       set alcance = alcance + cuantos, enviada_en = now()
     where id = n.id;
  end if;

  return cuantos;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Clientes dormidos
-- ---------------------------------------------------------------------------

create or replace function public.avisar_clientes_inactivos()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n public.notificaciones;
  cuantos integer := 0;
begin
  select * into n from public.notificaciones
   where disparador = 'cliente_inactivo' and activa
   limit 1;
  if n.id is null then return 0; end if;

  insert into public.notificacion_envios (notificacion_id, perfil_id)
  select n.id, s.perfil_id
    from public.perfiles_del_segmento('clientes_inactivos', n.dias_inactividad) s
   -- A este ya le escribimos hace poco: se lo deja tranquilo.
   where not exists (
     select 1 from public.notificacion_envios e
      where e.notificacion_id = n.id
        and e.perfil_id = s.perfil_id
        and e.creado_en > now() - make_interval(days => n.repetir_cada_dias)
   );

  get diagnostics cuantos = row_count;

  if cuantos > 0 then
    update public.notificaciones
       set alcance = alcance + cuantos, enviada_en = now()
     where id = n.id;
  end if;

  return cuantos;
end;
$$;

create or replace function public.notificaciones_automaticas()
returns integer
language sql security definer set search_path = public
as $$
  select public.avisar_carritos_abandonados() + public.avisar_clientes_inactivos();
$$;

revoke execute on function public.perfiles_del_segmento(public.segmento_notificacion, integer)
  from public, anon, authenticated;
revoke execute on function public.avisar_carritos_abandonados() from public, anon, authenticated;
revoke execute on function public.avisar_clientes_inactivos() from public, anon, authenticated;
revoke execute on function public.notificaciones_automaticas() from public, anon, authenticated;

-- Cada 5 minutos: con 10 de espera y 30 de vida del pedido, el aviso de carrito
-- abandonado sale con tiempo de sobra para que todavia se pueda pagar.
select cron.schedule('notificaciones-automaticas', '*/5 * * * *',
                     $$select public.notificaciones_automaticas()$$)
 where not exists (select 1 from cron.job where jobname = 'notificaciones-automaticas');

-- ---------------------------------------------------------------------------
-- 5. El mensaje habla con el nombre de cada uno
-- ---------------------------------------------------------------------------
--
-- `{nombre}` se reemplaza al leer, no al mandar: si la persona despues corrige
-- como se llama, el mensaje que todavia no abrio ya la trata bien. Cuando no
-- hay nombre cargado queda un saludo generico en vez de un hueco.

-- Se borran y se vuelven a crear en vez de `create or replace`: las dos suman
-- columnas en el medio, y reemplazar una vista solo deja agregarlas al final.
drop view if exists public.v_notificaciones;
drop view if exists public.v_notificaciones_admin;

create view public.v_notificaciones
with (security_invoker = true)
as
select
  e.id            as envio_id,
  e.perfil_id,
  e.leida_en,
  e.creado_en,
  e.pedido_id,
  n.id            as notificacion_id,
  replace(n.titulo, '{nombre}', coalesce(nullif(p.nombre, ''), 'Hola')) as titulo,
  replace(n.cuerpo, '{nombre}', coalesce(nullif(p.nombre, ''), 'Hola')) as cuerpo,
  n.destino,
  n.destino_id
from public.notificacion_envios e
join public.notificaciones n on n.id = e.notificacion_id
join public.perfiles p on p.id = e.perfil_id
where n.estado = 'enviada' or n.disparador is not null;

-- El panel cuenta lo mismo que antes, mas si es automatica.
create view public.v_notificaciones_admin
with (security_invoker = true)
as
select
  n.*,
  (select count(*) from public.notificacion_envios e
    where e.notificacion_id = n.id and e.leida_en is not null)::integer as leidas
from public.notificaciones n;
