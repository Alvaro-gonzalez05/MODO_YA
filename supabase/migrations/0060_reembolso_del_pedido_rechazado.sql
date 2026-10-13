-- 0060 - Si el local rechaza un pedido cobrado, se devuelve la plata
--
-- Hasta ahora `rechazar_pedido` dejaba el pedido en `rechazado` y listo: la
-- pantalla del cliente le prometia "te devolvemos el dinero" y no habia ni
-- funcion ni pantalla para hacerlo, ni siquiera para anotar que se devolvio por
-- afuera (hallazgo 2 de docs/hallazgos-de-la-revision.md). Con los pagos
-- simulados no se notaba; cobrando de verdad, es plata del cliente retenida sin
-- ningun circuito.
--
-- Como queda:
--
--   * **Al cliente se le devuelve el 100%**, productos y envio. El que falló
--     fue el local; el cliente no hizo nada mal y el envio ni siquiera se hizo.
--   * **Al local se le cobra una penalidad**, un porcentaje de lo que hubiera
--     cobrado por ese pedido (`tarifarios.penalidad_rechazo_pct`, 50% por
--     defecto). Entra en `cargos_comercio`, asi que aparece sola en su
--     liquidacion y en la que mira la administracion.
--
-- El reembolso contra Mercado Pago **no lo hace la base**: hace falta el access
-- token, que vive solo en las Edge Functions. Aca queda marcado como pendiente
-- y lo ejecuta el cron `reembolsar-pedidos`, igual que el push. Si falla —sin
-- red, Mercado Pago caido— la fila queda pendiente y se reintenta sola; colgado
-- del rechazo, un fallo dejaria al cliente sin su plata y sin que nadie se
-- entere.

alter table public.tarifarios
  add column penalidad_rechazo_pct smallint not null default 50
    check (penalidad_rechazo_pct between 0 and 100);

comment on column public.tarifarios.penalidad_rechazo_pct is
  'Que porcentaje de lo que hubiera cobrado se le carga al local cuando rechaza un pedido ya pago.';

alter table public.pagos
  -- Cuando se pidio el reembolso y cuando Mercado Pago lo confirmo. Mientras
  -- el segundo este nulo, el cron lo sigue intentando.
  add column reembolso_pedido_en timestamptz,
  add column reembolsado_en timestamptz,
  add column monto_reembolsado integer check (monto_reembolsado >= 0),
  add column mp_refund_id text;

create index pagos_reembolsos_pendientes_idx
  on public.pagos (reembolso_pedido_en)
  where reembolso_pedido_en is not null and reembolsado_en is null;

-- El cargo dice de que pedido salio: sin esto, "Ajuste $5.000" en la
-- liquidacion no se puede explicar tres semanas despues.
alter table public.cargos_comercio
  add column pedido_id uuid references public.pedidos(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Rechazar un pedido pago dispara las dos cosas
-- ---------------------------------------------------------------------------

create or replace function public.rechazar_pedido(
  p_pedido uuid,
  p_motivo text
)
returns public.pedidos
language plpgsql security definer set search_path = public
as $$
declare
  ped public.pedidos;
  pg  public.pagos;
  pct smallint;
  penalidad integer;
begin
  update public.pedidos
     set estado = 'rechazado', motivo_rechazo = p_motivo
   where id = p_pedido
     and comercio_id = public.mi_comercio_id()
     and estado = 'pagado'
  returning * into ped;

  if ped.id is null then
    raise exception 'El pedido no existe o ya no se puede rechazar'
      using errcode = 'MY004';
  end if;

  select * into pg from public.pagos where id = ped.pago_id;

  -- Solo hay plata que devolver si entro de verdad. Un pedido que todavia
  -- estaba por cobrarse no deja nada pendiente.
  if pg.id is not null and pg.estado = 'acreditado' then
    update public.pagos
       set reembolso_pedido_en = coalesce(reembolso_pedido_en, now())
     where id = pg.id;

    select coalesce(t.penalidad_rechazo_pct, 50) into pct
      from public.tarifarios t
     where t.vigente_hasta is null
     order by t.vigente_desde desc
     limit 1;

    -- Sobre lo que el local hubiera cobrado (los productos), no sobre el
    -- envio: el envio es de MODO YA y ademas no se hizo.
    penalidad := round(ped.subtotal * coalesce(pct, 50) / 100.0);

    if penalidad > 0 then
      insert into public.cargos_comercio (comercio_id, concepto, detalle, monto, fecha, pedido_id)
      values (
        ped.comercio_id, 'ajuste',
        format('Penalidad por rechazar el pedido %s (%s%% de %s)', ped.codigo, coalesce(pct, 50), ped.subtotal),
        penalidad, public.hoy(), ped.id
      );
    end if;
  end if;

  return ped;
end;
$$;

-- ---------------------------------------------------------------------------
-- Lo que el cron le pasa a la Edge Function
-- ---------------------------------------------------------------------------

create or replace function public.reembolsos_pendientes()
returns table (
  pago_id     uuid,
  pedido_id   uuid,
  codigo      text,
  mp_order_id text,
  monto       integer
)
language sql stable security definer set search_path = public
as $$
  select pg.id, p.id, p.codigo, pg.mp_order_id, pg.monto
    from public.pagos pg
    join public.pedidos p on p.pago_id = pg.id
   where pg.reembolso_pedido_en is not null
     and pg.reembolsado_en is null
     -- Despues de un dia intentando, lo mira una persona: puede ser que
     -- Mercado Pago no deje devolverlo y haya que resolverlo por afuera.
     and pg.reembolso_pedido_en > now() - interval '1 day';
$$;

create or replace function public.confirmar_reembolso(
  p_pago      uuid,
  p_mp_refund text,
  p_monto     integer
)
returns void
language sql security definer set search_path = public
as $$
  update public.pagos
     set estado = 'reembolsado',
         reembolsado_en = now(),
         monto_reembolsado = p_monto,
         mp_refund_id = p_mp_refund
   where id = p_pago;
$$;

revoke execute on function public.reembolsos_pendientes() from public, anon, authenticated;
revoke execute on function public.confirmar_reembolso(uuid, text, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- El disparador
-- ---------------------------------------------------------------------------

create or replace function public.reembolsar_lo_pendiente()
returns bigint
language plpgsql security definer set search_path = public, extensions
as $$
declare
  url   text;
  clave text;
begin
  if not exists (select 1 from public.reembolsos_pendientes()) then
    return null;
  end if;

  select decrypted_secret into url   from vault.decrypted_secrets where name = 'url_funciones';
  select decrypted_secret into clave from vault.decrypted_secrets where name = 'clave_de_servicio';
  if url is null or clave is null then
    raise warning 'Falta el secreto para reembolsar (correr guardar_secretos.ps1)';
    return null;
  end if;

  return net.http_post(
    url := url || '/reembolsar',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || clave
    ),
    body := jsonb_build_object('accion', 'reembolsar'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function public.reembolsar_lo_pendiente() from public, anon, authenticated;

select cron.schedule('reembolsar-pedidos', '* * * * *', $$select public.reembolsar_lo_pendiente()$$)
 where not exists (select 1 from cron.job where jobname = 'reembolsar-pedidos');
