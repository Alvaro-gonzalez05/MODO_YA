-- 0054 - Un recordatorio que se salteo no sale despues, fuera de orden
--
-- **Arreglo de 0050.** Al ponerse al dia (cron caido, o dos momentos que caen
-- dentro de la misma vuelta de 5 minutos, por ejemplo 5 y 8) se manda solo el
-- ultimo que corresponde, que es lo buscado. Pero en la vuelta siguiente el
-- anterior seguia vencido y sin mandar, asi que salia igual: el cliente recibia
-- el recordatorio de los 8 minutos y cinco minutos despues el de los 5.
--
-- Ahora solo cuentan los momentos posteriores al ultimo que ya salio para ese
-- pedido. Lo que quedo atras se da por cubierto.

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
      -- De los recordatorios ya vencidos, el ultimo; y solo si es posterior al
      -- ultimo que se le mando a este pedido.
      select max(r.minuto)::smallint as minuto
        from unnest(n.recordatorios) as r(minuto)
       where p.creado_en <= now() - make_interval(mins => r.minuto)
         and r.minuto > coalesce((
           select max(e.minuto) from public.notificacion_envios e
            where e.notificacion_id = n.id and e.pedido_id = p.id
         ), 0)
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

revoke execute on function public.avisar_carritos_abandonados() from public, anon, authenticated;
