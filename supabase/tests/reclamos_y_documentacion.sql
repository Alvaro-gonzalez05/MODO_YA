-- Reclamos y documentacion del rider: lo que agrego 0066 y lo que ya estaba.
--
-- Existe por los hallazgos 6 y 7 de docs/hallazgos-de-la-revision.md. Las dos
-- funcionalidades tenian backend y ninguna pantalla; al construirlas hubo que
-- tapar cuatro huecos, y estos son los que se pueden probar desde SQL.
--
-- Ojo (CLAUDE.md): sql.ps1 corre como `postgres`, que SALTEA el RLS. Todo lo
-- que verifica permisos hace `set local role authenticated` y despues
-- `reset role`, o pasaria igual con la politica mal.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli  uuid := gen_random_uuid();
  u_otro uuid := gen_random_uuid();
  u_com  uuid := gen_random_uuid();
  u_rid  uuid := gen_random_uuid();
  u_adm  uuid := gen_random_uuid();
  ciudad uuid;
  cli    uuid;
  com    uuid;
  rid    uuid;
  ped    uuid;
  rec    uuid;
  doc    uuid;
  n      int;
  ok     boolean;
  d      public.documentos_repartidor;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_cli ,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
     'rec-cli@test.local','x','{"rol":"cliente"}','{"nombre":"Reclamante"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
     'rec-otro@test.local','x','{"rol":"cliente"}','{"nombre":"Otro Cliente"}',now(),now(),now()),
    (u_com ,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
     'rec-com@test.local','x','{"rol":"comercio"}','{"nombre":"Local Reclamo"}',now(),now(),now()),
    (u_rid ,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
     'rec-rid@test.local','x','{"rol":"repartidor"}','{"nombre":"Rider Doc"}',now(),now(),now()),
    (u_adm ,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
     'rec-adm@test.local','x','{"rol":"admin"}','{"nombre":"Admin Reclamos"}',now(),now(),now());

  select id into cli from public.clientes where perfil_id = u_cli;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo, estado_aprobacion)
  values (u_rid, ciudad, 'Rider Doc', '2604000111', 'moto', 'aprobado')
  returning id into rid;

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle,
                                ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Reclamo', 'Pizzeria', '2604000222', 'San Martin 100',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5841,-35.4757),4326)::extensions.geography,
          'aprobado')
  returning id into com;

  -- Un pedido rechazado, que nunca llego a tener envio: justo el caso que el
  -- modelo no sabia representar antes de 0066.
  insert into public.pedidos (ciudad_id, cliente_id, comercio_id, estado,
                              entrega_calle, entrega_ubicacion, subtotal, costo_envio)
  values (ciudad, cli, com, 'rechazado', 'Rivadavia 50',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.58,-35.47),4326)::extensions.geography,
          8000, 1500)
  returning id into ped;

  -- ---- El cliente abre un reclamo de su pedido -------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  set local role authenticated;
  insert into public.reclamos (pedido_id, motivo, detalle)
  values (ped, 'No me lo entregaron', 'El local lo rechazo y nadie me aviso.')
  returning id into rec;
  reset role;

  insert into _r values ('01. el cliente abre un reclamo de su pedido',
    (select case when abierto_por = u_cli and rol_origen = 'cliente' and estado = 'abierto'
                 then 'OK  abierto, como cliente'
                 else format('MAL  %s / %s', rol_origen, estado) end
       from public.reclamos where id = rec));

  -- ---- Y no sobre el pedido de otro -----------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_otro)::text, true);
  set local role authenticated;
  begin
    insert into public.reclamos (pedido_id, motivo) values (ped, 'Quiero molestar');
    ok := true;
  exception when others then ok := false;
  end;
  reset role;
  insert into _r values ('02. nadie reclama sobre el pedido de otro',
    case when not ok then 'OK  rebota' else 'MAL  lo deja' end);

  -- ---- Ni sin contar que paso -----------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  set local role authenticated;
  begin
    insert into public.reclamos (pedido_id, motivo) values (ped, '   ');
    ok := true;
  exception when others then ok := false;
  end;
  reset role;
  insert into _r values ('03. el motivo no puede venir vacio',
    case when not ok then 'OK  rebota' else 'MAL  lo deja' end);

  -- ---- El local tambien puede abrir uno de un pedido suyo --------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_com)::text, true);
  set local role authenticated;
  begin
    insert into public.reclamos (pedido_id, motivo, detalle)
    values (ped, 'El rider no vino a buscarlo', 'Estuvo listo media hora.');
    ok := true;
  exception when others then ok := false;
  end;
  reset role;
  insert into _r values ('04. el local abre uno de un pedido suyo',
    case when ok then 'OK  entra' else 'MAL  rebota' end);

  -- ---- Cada uno ve solo el suyo ---------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_otro)::text, true);
  set local role authenticated;
  select count(*) into n from public.reclamos where pedido_id = ped;
  reset role;
  insert into _r values ('05. un tercero no ve ningun reclamo del pedido',
    case when n = 0 then 'OK  no ve nada' else format('MAL  ve %s', n) end);

  -- ---- Y no se lo resuelve solo ---------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  begin
    perform public.admin_resolver_reclamo(rec, 'resuelto', 'Me lo resuelvo solo');
    ok := true;
  exception when others then ok := false;
  end;
  insert into _r values ('06. el que reclama no se lo resuelve solo',
    case when not ok then 'OK  rebota' else 'MAL  lo deja' end);

  -- ---- La administracion lo toma y lo cierra ---------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_adm)::text, true);
  perform public.admin_resolver_reclamo(rec, 'en_revision', null);
  insert into _r values ('07. la administracion lo toma',
    (select case when estado = 'en_revision' and resuelto_en is null
                 then 'OK  en revision, sin cerrar'
                 else format('MAL  %s', estado) end
       from public.reclamos where id = rec));

  perform public.admin_resolver_reclamo(rec, 'resuelto', 'Te devolvimos la plata del pedido.');
  insert into _r values ('08. y lo cierra con la respuesta que ve el cliente',
    (select case when estado = 'resuelto' and resuelto_por = u_adm and resuelto_en is not null
                 then 'OK  ' || resolucion
                 else format('MAL  %s', estado) end
       from public.reclamos where id = rec));

  -- ---- Documentacion: el rider sube la suya ----------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_rid)::text, true);
  set local role authenticated;
  insert into public.documentos_repartidor (repartidor_id, tipo, archivo_url)
  values (rid, 'DNI', rid || '/DNI.jpg')
  returning id into doc;
  reset role;

  insert into _r values ('09. el rider sube un documento y queda pendiente',
    (select case when estado = 'pendiente' then 'OK  pendiente'
                 else format('MAL  %s', estado) end
       from public.documentos_repartidor where id = doc));

  -- ---- No se lo aprueba solo (es el agujero que tapo 0016) -------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_rid)::text, true);
  set local role authenticated;
  begin
    update public.documentos_repartidor set estado = 'aprobado' where id = doc;
    ok := true;
  exception when others then ok := false;
  end;
  reset role;
  insert into _r values ('10. el rider no se aprueba la documentacion solo',
    case when not ok then 'OK  rebota' else 'MAL  lo deja' end);

  -- ---- La administracion lo rechaza (hallazgo 15: antes era inalcanzable) ----
  perform set_config('request.jwt.claims', json_build_object('sub',u_adm)::text, true);
  d := public.admin_validar_documento(doc, 'rechazado', 'La foto esta cortada, no se lee el numero.');
  insert into _r values ('11. la administracion lo rechaza y le dice por que',
    case when d.estado = 'rechazado' and d.observacion is not null and d.validado_por = u_adm
         then 'OK  ' || d.observacion
         else format('MAL  %s', d.estado) end);

  -- ---- El rider lo vuelve a subir y vuelve a la cola -------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_rid)::text, true);
  set local role authenticated;
  update public.documentos_repartidor set archivo_url = rid || '/DNI.png' where id = doc;
  reset role;

  insert into _r values ('12. subirlo de nuevo lo devuelve a revision',
    (select case when estado = 'pendiente' and observacion is null and validado_en is null
                 then 'OK  pendiente y sin la observacion vieja'
                 else format('MAL  %s / %s', estado, coalesce(observacion,'sin obs')) end
       from public.documentos_repartidor where id = doc));

  -- ---- Y despues se aprueba --------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_adm)::text, true);
  d := public.admin_validar_documento(doc, 'aprobado', null);
  insert into _r values ('13. y despues se aprueba sin perder el archivo',
    case when d.estado = 'aprobado' and d.archivo_url = rid || '/DNI.png'
         then 'OK  aprobado' else format('MAL  %s', d.estado) end);

  -- ---- Nadie mas la ve -------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  set local role authenticated;
  select count(*) into n from public.documentos_repartidor where id = doc;
  reset role;
  insert into _r values ('14. un cliente no ve la documentacion del rider',
    case when n = 0 then 'OK  no la ve' else 'MAL  la ve' end);

  -- ---- Que se le exige a una moto -------------------------------------------
  select count(*) into n from public.documentos_exigidos where vehiculo = 'moto';
  insert into _r values ('15. la semilla dice que pedirle a una moto',
    case when n >= 1 then format('OK  %s documentos', n) else 'MAL  ninguno' end);

  -- ---- Limpieza --------------------------------------------------------------
  perform set_config('request.jwt.claims', null, true);
  delete from public.reclamos where pedido_id = ped;
  delete from public.pedidos where id = ped;
  delete from public.documentos_repartidor where repartidor_id = rid;
  delete from public.comercios where id = com;
  delete from public.repartidores where id = rid;
  delete from auth.users where id in (u_cli, u_otro, u_com, u_rid, u_adm);
end $$;

select paso, resultado from _r order by paso;
