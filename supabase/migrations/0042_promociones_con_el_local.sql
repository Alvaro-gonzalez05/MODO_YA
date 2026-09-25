-- 0042 - La vista de promociones dice de qué local es cada una
--
-- La administracion ve las promociones de todos los locales en una sola
-- pantalla: sin el nombre habria que pedir los comercios aparte y cruzarlos en
-- la app. `v_campanias` ya lo resuelve asi.

-- Se borra y se vuelve a crear: el nombre nuevo va en el medio y Postgres no
-- deja renombrar columnas de una vista con `create or replace`.
drop view public.v_promociones;

create view public.v_promociones
with (security_invoker = true)
as
select
  pr.id, pr.comercio_id, co.nombre as comercio_nombre,
  pr.nombre, pr.porcentaje, pr.alcance,
  pr.dias, pr.desde, pr.hasta, pr.activa, pr.creado_en,
  (select count(*) from public.promocion_secciones ps where ps.promocion_id = pr.id) as secciones,
  (select count(*) from public.promocion_productos pp where pp.promocion_id = pr.id) as productos,
  public.promocion_vigente(pr.id) as vigente
from public.promociones pr
left join public.comercios co on co.id = pr.comercio_id;
