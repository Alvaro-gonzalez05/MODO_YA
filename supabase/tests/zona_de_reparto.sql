-- Solo se reparte dentro de la ciudad (0071).
--
-- Sin zonas cargadas manda el radio de la ciudad (15 km para Malargüe); con una
-- zona activa manda el polígono. Un pin en Mendoza capital no se puede guardar,
-- ni cotizar, ni convertir en un mandado.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli uuid := gen_random_uuid();
  u_com uuid := gen_random_uuid();
  ciudad uuid; cli uuid; com uuid; zona uuid; dir uuid;
  centro extensions.geography;
  mendoza extensions.geography :=
    extensions.ST_SetSRID(extensions.ST_MakePoint(-68.8272, -32.8895), 4326)::extensions.geography;
  -- A 5 km del centro: adentro del radio, afuera del polígono chico de la prueba.
  a_cinco extensions.geography :=
    extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5847, -35.5206), 4326)::extensions.geography;
  n integer;
begin
  select id, c.centro into ciudad, centro from public.ciudades c where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','zona-cli@test.local','x','{"provider":"email"}','{"nombre":"Clienta Zona","telefono":"+54 260 456-0001"}',now(),now(),now()),
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','zona-com@test.local','x','{"rol":"comercio"}','{}',now(),now(),now());
  select id into cli from public.clientes where perfil_id = u_cli;

  -- ---- Dirección del cliente ---------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  set local role authenticated;
  dir := public.agregar_direccion('Casa', 'Roca 400', -35.4761, -69.5839);
  reset role;
  insert into _r values ('01 una dirección en el centro se guarda',
    case when dir is not null then 'OK' else 'MAL' end);

  begin
    set local role authenticated;
    perform public.agregar_direccion('Tía', 'San Martín 1000, Mendoza', -32.8895, -68.8272);
    reset role;
    insert into _r values ('02 NO una dirección en Mendoza capital', 'MAL  se guardó');
  exception when others then
    reset role;
    insert into _r values ('02 NO una dirección en Mendoza capital',
      case when sqlstate = 'MY008' then 'OK  ' || left(sqlerrm, 45) else 'MAL  ' || sqlstate || ' ' || sqlerrm end);
  end;

  begin
    update public.direcciones_cliente set ubicacion = mendoza where id = dir;
    insert into _r values ('03 NO mover el pin de una guardada afuera', 'MAL  se movió');
  exception when others then
    insert into _r values ('03 NO mover el pin de una guardada afuera',
      case when sqlstate = 'MY008' then 'OK  rechazado' else 'MAL  ' || sqlstate end);
  end;

  -- ---- Mandados: los dos pines -------------------------------------------------
  begin
    set local role authenticated;
    perform public.cotizar_mandado(-32.8895, -68.8272, -35.4769, -69.5852);
    reset role;
    insert into _r values ('04 NO cotizar un mandado que se retira afuera', 'MAL  cotizó');
  exception when others then
    reset role;
    insert into _r values ('04 NO cotizar un mandado que se retira afuera',
      case when sqlerrm like 'El punto de retiro%' then 'OK  dice cuál pin está mal' else 'MAL  ' || sqlerrm end);
  end;

  begin
    set local role authenticated;
    perform public.crear_mandado('Roca 400', -35.4761, -69.5839,
                                 'Av. Colón 100, Mendoza', -32.8895, -68.8272, 'Un sobre');
    reset role;
    insert into _r values ('05 NO pedir un mandado a Mendoza', 'MAL  se creó');
  exception when others then
    reset role;
    insert into _r values ('05 NO pedir un mandado a Mendoza',
      case when sqlstate = 'MY008' then 'OK  rechazado' else 'MAL  ' || sqlstate || ' ' || sqlerrm end);
  end;

  set local role authenticated;
  select count(*) into n from public.cotizar_mandado(-35.4761, -69.5839, -35.4769, -69.5852);
  reset role;
  insert into _r values ('06 un mandado dentro de la ciudad se cotiza igual que antes',
    case when n = 1 then 'OK' else 'MAL' end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- El local ----------------------------------------------------------------
  begin
    insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
    values (u_com, ciudad, 'Local Lejano', 'Pizzeria', '2604000092', 'Mendoza', mendoza, 'aprobado');
    insert into _r values ('07 NO un local ubicado afuera', 'MAL  se creó');
  exception when others then
    insert into _r values ('07 NO un local ubicado afuera',
      case when sqlstate = 'MY008' then 'OK  rechazado' else 'MAL  ' || sqlstate end);
  end;

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Local Zona', 'Pizzeria', '2604000092', 'Roca 950',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;
  insert into _r values ('08 un local en el centro se crea', case when com is not null then 'OK' else 'MAL' end);

  -- ---- Con una zona cargada manda el polígono -----------------------------------
  insert into _r values ('09 sin zonas, a 5 km entra por el radio',
    case when public.dentro_de_la_zona(ciudad, a_cinco) then 'OK' else 'MAL' end);

  insert into public.zonas (ciudad_id, nombre, poligono)
  values (ciudad, 'Prueba: el centro',
          extensions.ST_GeogFromText('POLYGON((-69.60 -35.49, -69.57 -35.49, -69.57 -35.46, -69.60 -35.46, -69.60 -35.49))'))
  returning id into zona;

  insert into _r values ('10 con zona, a 5 km queda afuera',
    case when not public.dentro_de_la_zona(ciudad, a_cinco) then 'OK  manda el polígono' else 'MAL' end);
  insert into _r values ('11 con zona, el centro sigue adentro',
    case when public.dentro_de_la_zona(ciudad, centro) then 'OK' else 'MAL' end);

  update public.zonas set activa = false where id = zona;
  insert into _r values ('12 una zona apagada no cuenta',
    case when public.dentro_de_la_zona(ciudad, a_cinco) then 'OK  vuelve al radio' else 'MAL' end);

  insert into _r values ('13 NO el cliente consulta la regla sin sesión',
    case when has_function_privilege('anon', 'public.dentro_de_la_zona(uuid, extensions.geography)', 'execute')
         then 'MAL  anon la puede llamar' else 'OK' end);

  -- ---- Limpieza ----------------------------------------------------------------
  delete from public.zonas where id = zona;
  delete from public.envio_eventos where envio_id in (select id from public.envios where cliente_id = cli);
  delete from public.ofertas where envio_id in (select id from public.envios where cliente_id = cli);
  delete from public.envios where cliente_id = cli;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.comercios where id = com;
  delete from public.clientes where id = cli;
  delete from auth.users where id in (u_cli, u_com);
end $$;

select paso, resultado from _r order by paso;
