-- 0010 - Las claves de atribucion no deben bloquear el borrado de una cuenta
--
-- Las columnas del tipo "quien hizo esto" (actor_id, aprobado_por, validado_por,
-- cancelado_por, creado_por, resuelto_por) apuntan a `perfiles`. Con el
-- comportamiento por defecto (NO ACTION) cualquiera de ellas impide borrar un
-- usuario, y el borrado de cuenta es un requisito de Google Play.
--
-- La decision correcta es `on delete set null`: el registro de auditoria se
-- conserva, lo unico que se pierde es a quien atribuirselo. Borrar el evento
-- junto con el usuario seria peor: destruiria justamente la evidencia que hace
-- falta para resolver un reclamo.
--
-- Ojo con lo que NO se toca: `envios.comercio_id` y `envios.repartidor_id`
-- siguen en NO ACTION a proposito. Un comercio con envios hechos no se borra,
-- se suspende; si se pudiera borrar, se irian con el los importes de
-- liquidaciones ya cerradas.

alter table public.envio_eventos
  drop constraint envio_eventos_actor_id_fkey,
  add  constraint envio_eventos_actor_id_fkey
       foreign key (actor_id) references public.perfiles(id) on delete set null;

alter table public.comercios
  drop constraint comercios_aprobado_por_fkey,
  add  constraint comercios_aprobado_por_fkey
       foreign key (aprobado_por) references public.perfiles(id) on delete set null;

alter table public.repartidores
  drop constraint repartidores_aprobado_por_fkey,
  add  constraint repartidores_aprobado_por_fkey
       foreign key (aprobado_por) references public.perfiles(id) on delete set null;

alter table public.documentos_repartidor
  drop constraint documentos_repartidor_validado_por_fkey,
  add  constraint documentos_repartidor_validado_por_fkey
       foreign key (validado_por) references public.perfiles(id) on delete set null;

alter table public.envios
  drop constraint envios_cancelado_por_fkey,
  add  constraint envios_cancelado_por_fkey
       foreign key (cancelado_por) references public.perfiles(id) on delete set null;

alter table public.tarifarios
  drop constraint tarifarios_creado_por_fkey,
  add  constraint tarifarios_creado_por_fkey
       foreign key (creado_por) references public.perfiles(id) on delete set null;

alter table public.reclamos
  drop constraint reclamos_resuelto_por_fkey,
  add  constraint reclamos_resuelto_por_fkey
       foreign key (resuelto_por) references public.perfiles(id) on delete set null;
