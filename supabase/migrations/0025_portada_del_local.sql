-- 0025 - Portada del local, aparte del logo
--
-- Hasta ahora el local tenia una sola imagen (logo_url) y la tarjeta del
-- cliente la usaba de portada. Como en las apps de delivery, son dos cosas:
--   portada_url: foto ancha de la comida o el local, arriba de la tarjeta.
--   logo_url:    la marca, cuadrada, al lado del nombre.

alter table public.comercios add column portada_url text;

comment on column public.comercios.portada_url is
  'Foto ancha de la tarjeta del local (la carga el local). El logo va aparte en logo_url.';

-- El local edita su vidriera (ver 0016): la portada tambien es suya.
grant update (portada_url) on public.comercios to authenticated;

-- Misma vista que en 0017, con la portada. Se agrega al final: "create or
-- replace view" no deja cambiar el orden de las columnas existentes.
create or replace view public.v_comercios
with (security_invoker = true)
as
select
  c.id, c.perfil_id, c.ciudad_id,
  c.nombre, c.rubro, c.rubro_id, r.nombre as rubro_nombre,
  c.telefono, c.calle, c.referencia,
  extensions.ST_Y(c.ubicacion::extensions.geometry) as lat,
  extensions.ST_X(c.ubicacion::extensions.geometry) as lng,
  c.logo_url, c.acepta_pedidos, c.demora_estimada_min,
  c.estado_aprobacion, c.creado_en,
  public.comercio_abierto(c.id) as abierto,
  c.portada_url
from public.comercios c
left join public.rubros r on r.id = c.rubro_id;

-- Los locales que ya cargaron una foto la subieron pensando en la portada
-- (era la unica imagen y se veia grande): pasa a ser la portada y el logo
-- queda para cargar.
update public.comercios
set portada_url = logo_url, logo_url = null
where logo_url is not null and portada_url is null;
