-- 0044 - Buzón de avisos de Mercado Pago (webhooks)
--
-- Mercado Pago avisa por HTTP cada vez que le pasa algo a un pago: se aprobo
-- uno que habia quedado en revision, se devolvio, entro un contracargo. Hoy
-- nada de eso nos llega: el cobro con tarjeta responde en el momento y con eso
-- alcanza para el caso feliz, pero un pago aprobado diez minutos tarde queda
-- muerto y una devolucion hecha desde el panel deja la liquidacion mal.
--
-- Este es el primer paso: **guardar**. La funcion `mp-webhook` recibe el aviso,
-- valida la firma y lo mete acá. Todavia no se actua sobre el pedido: eso se
-- agrega cuando tengamos las credenciales y podamos ver avisos de verdad (el
-- cuerpo cambia segun la aplicacion sea de Orders o de Payments).
--
-- Guardar primero y actuar despues no es pereza: si el dia de manana algo se
-- procesa mal, el aviso original quedo tal cual llego y se puede reprocesar.

create table public.mp_notificaciones (
  id          uuid primary key default gen_random_uuid(),
  recibido_en timestamptz not null default now(),

  -- "payment", "order"... y la accion concreta ("payment.updated").
  tipo        text,
  accion      text,

  -- El id del recurso en Mercado Pago (data.id): el pago o la orden.
  recurso_id  text,

  -- Lo manda Mercado Pago y es el mismo cuando reintenta: sirve para no
  -- guardar dos veces el mismo aviso.
  request_id  text,

  -- null = todavia no hay clave secreta configurada (MP_WEBHOOK_SECRET).
  firma_valida boolean,

  cuerpo      jsonb not null,

  procesada    boolean not null default false,
  procesada_en timestamptz,
  nota         text
);

create index mp_notificaciones_recurso_idx on public.mp_notificaciones (recurso_id);
create index mp_notificaciones_fecha_idx on public.mp_notificaciones (recibido_en desc);
create index mp_notificaciones_pendientes_idx
  on public.mp_notificaciones (recibido_en) where not procesada;

-- Mercado Pago reintenta cada 15 minutos hasta que le respondemos bien. Si el
-- reintento llega despues de que ya lo guardamos, no se duplica.
create unique index mp_notificaciones_sin_repetir
  on public.mp_notificaciones (request_id) where request_id is not null;

comment on table public.mp_notificaciones is
  'Avisos de Mercado Pago tal como llegaron. Los escribe la Edge Function mp-webhook.';

alter table public.mp_notificaciones enable row level security;

-- Nadie los toca desde la app: los escribe la Edge Function con service_role
-- (que saltea RLS) y los mira la administracion.
create policy mp_notificaciones_admin on public.mp_notificaciones
  for select to authenticated
  using ((select public.es_admin()));
