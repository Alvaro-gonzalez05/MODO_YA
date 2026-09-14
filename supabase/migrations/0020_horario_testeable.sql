-- 0020 - La logica de horarios recibe el momento a evaluar
--
-- El test de 0019 armaba los turnos alrededor de la hora real y fallaba cerca
-- de la medianoche: un turno de "una hora antes a una hora despues" corrido a
-- las 00:30 en realidad empezo el dia anterior, pero el test lo guardaba como
-- de hoy. La funcion estaba bien; el test no se podia escribir bien.
--
-- Se separa la logica en comercio_abierto_en(comercio, momento), que se prueba
-- con horas fijas. comercio_abierto(comercio) queda igual por fuera (la usa
-- v_comercios) y solo le pasa la hora actual de Mendoza. Mendoza no tiene
-- horario de verano, asi que la conversion es estable todo el ano.

create or replace function public.comercio_abierto_en(
  p_comercio uuid,
  p_momento  timestamp   -- hora local de Mendoza
)
returns boolean
language plpgsql stable security definer set search_path = public
as $$
declare
  c    public.comercios;
  hoy  smallint := extract(dow from p_momento);
  ayer smallint := (extract(dow from p_momento)::int + 6) % 7;
  hora time     := p_momento::time;
begin
  select * into c from public.comercios where id = p_comercio;
  if c.id is null or c.estado_aprobacion <> 'aprobado' or not c.acepta_pedidos then
    return false;
  end if;

  if not exists (select 1 from public.horarios_comercio where comercio_id = c.id) then
    return true;
  end if;

  return exists (
    select 1 from public.horarios_comercio h
    where h.comercio_id = c.id
      and (
        (h.dia = hoy  and h.cierra > h.abre and hora >= h.abre and hora < h.cierra)
        or (h.dia = hoy  and h.cierra < h.abre and hora >= h.abre)
        or (h.dia = ayer and h.cierra < h.abre and hora <  h.cierra)
      )
  );
end;
$$;

create or replace function public.comercio_abierto(p_comercio uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.comercio_abierto_en(p_comercio, (now() at time zone 'America/Argentina/Mendoza'))
$$;

revoke execute on function public.comercio_abierto_en(uuid, timestamp) from public, anon;
grant execute on function public.comercio_abierto_en(uuid, timestamp) to authenticated;
