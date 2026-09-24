-- 0038 - La publicidad se cobra una sola vez por día
--
-- `unique (campania_id, fecha, pedido_id)` no alcanzaba: en SQL dos NULL no
-- son iguales, asi que dos gastos de publicidad del mismo dia (los dos sin
-- pedido) pasaban el control. Si el cron corria dos veces, se le cobraba dos
-- veces al local. Se ve en supabase/tests/campanias.sql, paso 08.

alter table public.campania_gastos drop constraint if exists campania_gastos_un_dia;

-- Publicidad (sin pedido): uno por campaña y día.
create unique index campania_gastos_dia_unico
  on public.campania_gastos (campania_id, fecha)
  where pedido_id is null;

-- Plus: un envío regalado por pedido.
create unique index campania_gastos_pedido_unico
  on public.campania_gastos (pedido_id)
  where pedido_id is not null;
