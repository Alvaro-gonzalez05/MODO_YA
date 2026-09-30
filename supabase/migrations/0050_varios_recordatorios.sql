-- 0050 - El carrito abandonado puede insistir mas de una vez
--
-- Antes salia un solo aviso, a los N minutos. Ahora se configura una lista de
-- momentos ("a los 5, a los 12 y a los 22"), porque el primero se lo pierde
-- mucha gente.
--
-- **El techo es duro y conviene tenerlo presente:** `cerrar_pagos_vencidos()`
-- cancela el pedido sin pagar a los 30 minutos. Un recordatorio despues de eso
-- avisaria por algo que ya no existe, asi que los momentos se limitan a 25.
-- Para recordar mas tarde hay que decidir antes cuanto tiempo se le guarda un
-- pedido sin pagar, que es una decision de negocio, no de codigo.
--
-- Si el cron estuvo caido y un pedido quedo viejo, **no se mandan todos los
-- atrasados de golpe**: se manda solo el ultimo que corresponde. Recibir tres
-- mensajes juntos es peor que no recibir ninguno.

alter table public.notificaciones
  add column recordatorios smallint[] not null default '{10}'
    constraint notificaciones_recordatorios_validos check (
      array_length(recordatorios, 1) between 1 and 4
      -- Todos entre 1 y 25: tienen que entrar antes de que el pedido se cancele.
      and recordatorios <@ array[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
                                 16,17,18,19,20,21,22,23,24,25]::smallint[]
    );

comment on column public.notificaciones.recordatorios is
  'Minutos despues de crear el pedido en que sale cada recordatorio. Todos menores a 30: a esa altura el pedido ya se cancelo.';

-- Lo que ya estaba configurado se conserva.
update public.notificaciones
   set recordatorios = array[minutos_espera]::smallint[]
 where disparador = 'carrito_abandonado';

-- La vista expone `n.*`, asi que hay que sacarla antes de tocar las columnas.
-- Se rearma al final.
drop view if exists public.v_notificaciones_admin;

alter table public.notificaciones drop column minutos_espera;

-- ---------------------------------------------------------------------------
-- El envio recuerda a cual de los recordatorios corresponde
-- ---------------------------------------------------------------------------

alter table public.notificacion_envios add column minuto smallint;

comment on column public.notificacion_envios.minuto is
  'Cual de los recordatorios de la automatica es este. Sin esto, el segundo aviso del mismo pedido se veria como repetido.';

drop index if exists public.notificacion_envios_un_pedido;

-- Antes: uno por pedido. Ahora: uno por pedido y por momento.
create unique index notificacion_envios_un_recordatorio
  on public.notificacion_envios (notificacion_id, pedido_id, minuto)
  where pedido_id is not null;

-- ---------------------------------------------------------------------------
-- Avisar, una vez por momento
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

  insert into public.notificacion_envios (notificacion_id, perfil_id, pedido_id, minuto)
  select n.id, c.perfil_id, p.id, d.minuto
    from public.pedidos p
    join public.clientes c on c.id = p.cliente_id
    join lateral (
      -- De los recordatorios que ya vencieron para este pedido, el ultimo que
      -- todavia no se mando. Uno solo por corrida: si el cron estuvo caido, se
      -- pone al dia con un mensaje, no con tres.
      select max(r.minuto)::smallint as minuto
        from unnest(n.recordatorios) as r(minuto)
       where p.creado_en <= now() - make_interval(mins => r.minuto)
         and not exists (
           select 1 from public.notificacion_envios e
            where e.notificacion_id = n.id
              and e.pedido_id = p.id
              and e.minuto = r.minuto
         )
    ) d on d.minuto is not null
   where p.estado = 'pendiente_pago'
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

-- La vista del panel, con las columnas nuevas.
create view public.v_notificaciones_admin
with (security_invoker = true)
as
select
  n.*,
  (select count(*) from public.notificacion_envios e
    where e.notificacion_id = n.id and e.leida_en is not null)::integer as leidas
from public.notificaciones n;
