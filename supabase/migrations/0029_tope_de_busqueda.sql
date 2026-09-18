-- 0029 - Tope de la busqueda de rider
--
-- Desde 0027 la busqueda no se rinde: cada 10 s se vuelve a ofrecer el envio,
-- tambien a quien ya dijo que no. Pero un envio olvidado (una prueba de hace
-- dos dias, un pedido que nadie cancelo) le seguiria sonando a los riders para
-- siempre. Despues de 3 horas buscando pasa a `sin_repartidor` y el local
-- decide si lo relanza (ofrecer_al_siguiente lo vuelve a poner a buscar).

create or replace function public.vencer_ofertas()
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  o public.ofertas;
  e record;
  n integer := 0;
begin
  for o in
    select * from public.ofertas
     where respuesta is null and expira_en <= now()
  loop
    update public.ofertas set respuesta = 'expirada', respondida_en = now()
     where id = o.id;
    n := n + 1;
  end loop;

  update public.envios set estado = 'sin_repartidor'
   where estado = 'buscando_repartidor'
     and creado_en < now() - interval '3 hours'
     and not exists (
       -- "ab" y no "o": o es la variable del primer loop.
       select 1 from public.ofertas ab
       where ab.envio_id = envios.id and ab.respuesta is null and ab.expira_en > now()
     );

  -- Solo los que estan buscando: los `sin_repartidor` los relanza el local.
  for e in
    select id from public.envios
     where estado = 'buscando_repartidor'
     order by creado_en
  loop
    perform public.ofrecer_al_siguiente(e.id);
  end loop;

  return n;
end;
$$;
