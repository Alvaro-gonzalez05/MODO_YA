-- Mandados: el cliente pide un rider para que le retire algo y se lo lleve.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_cli uuid := gen_random_uuid();
  u_otro uuid := gen_random_uuid();
  u_rep uuid := gen_random_uuid();
  ciudad uuid; cli uuid; otro uuid; rep uuid;
  env public.envios;
  of  public.ofertas;
  cot record;
  n integer;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values
    (u_cli, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','mand-cli@test.local','x','{"provider":"email"}','{"nombre":"Marcela Diaz","telefono":"+54 260 456-1122"}',now(),now(),now()),
    (u_otro,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','mand-otro@test.local','x','{"provider":"email"}','{"nombre":"Otro Cliente","telefono":"+54 260 999-9999"}',now(),now(),now()),
    (u_rep, '00000000-0000-0000-0000-000000000000','authenticated','authenticated','mand-rep@test.local','x','{"rol":"repartidor"}','{"nombre":"Cadete Mandado"}',now(),now(),now());

  select id into cli  from public.clientes where perfil_id = u_cli;
  select id into otro from public.clientes where perfil_id = u_otro;

  insert into public.repartidores (perfil_id, ciudad_id, nombre, telefono, vehiculo,
                                   estado_aprobacion, conectado, ultima_ubicacion, ultima_ubicacion_en)
  values (u_rep, ciudad, 'Cadete Mandado','2604111555','moto','aprobado',true,
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5820,-35.4760),4326)::extensions.geography, now())
  returning id into rep;

  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);

  -- ---- Cuanto sale ----------------------------------------------------------
  select * into cot from public.cotizar_mandado(-35.4761, -69.5839, -35.4769, -69.5852);
  insert into _r values ('1. cotiza antes de pedirlo',
    case when cot.total > 0 then format('OK  $%s, %s km', cot.total, cot.distancia_km)
         else 'MAL  no cotizo' end);

  -- ---- Sin decir que retirar no se puede ------------------------------------
  begin
    perform public.crear_mandado('Roca 400', -35.4761, -69.5839,
                                 'San Martin 500', -35.4769, -69.5852, '   ');
    insert into _r values ('2. exige decir que retirar', 'MAL  lo dejo pasar');
  exception when others then
    insert into _r values ('2. exige decir que retirar', 'OK  rechazado');
  end;

  -- ---- Pedirlo --------------------------------------------------------------
  env := public.crear_mandado(
    'Roca 400', -35.4761, -69.5839,
    'San Martin 500', -35.4769, -69.5852,
    'Un sobre a nombre de Marcela', 'Porton verde');

  insert into _r values ('3. queda pedido y buscando rider',
    format('codigo=%s estado=%s total=$%s', env.codigo, env.estado, env.total));

  insert into _r values ('4. es del cliente y no de un local',
    case when env.cliente_id = cli and env.comercio_id is null
         then 'OK  sin local' else 'MAL' end);

  insert into _r values ('5. el precio lo puso el servidor',
    case when env.total = cot.total then format('OK  $%s, lo mismo que cotizo', env.total)
         else format('MAL  cotizo %s y cobro %s', cot.total, env.total) end);

  insert into _r values ('6. el rider cobra el envio en la puerta',
    case when env.cobrar_al_entregar = env.total and env.cobro_metodo = 'efectivo'
         then format('OK  cobra $%s en efectivo', env.cobrar_al_entregar) else 'MAL' end);

  insert into _r values ('7. el rider sabe que tiene que retirar',
    case when env.origen_referencia = 'Un sobre a nombre de Marcela'
         then 'OK  ' || env.origen_referencia else 'MAL' end);

  -- ---- Sale a buscar en la misma llamada ------------------------------------
  select * into of from public.ofertas where envio_id = env.id;
  insert into _r values ('8. ya se le ofrecio a alguien',
    case when of.repartidor_id = rep then 'OK  sin quedar trabado en cotizado' else 'MAL  no salio a buscar' end);

  perform set_config('request.jwt.claims', null, true);

  -- ---- Privacidad -----------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  set local role authenticated;
  select count(*) into n from public.v_envios where id = env.id;
  reset role;
  insert into _r values ('9. el cliente ve su mandado',
    case when n = 1 then 'OK  1 fila' else format('MAL  ve %s', n) end);

  perform set_config('request.jwt.claims', json_build_object('sub',u_otro)::text, true);
  set local role authenticated;
  select count(*) into n from public.v_envios where id = env.id;
  reset role;
  insert into _r values ('10. otro cliente no lo ve',
    case when n = 0 then 'OK  0 filas' else format('MAL  ve %s', n) end);

  -- ---- Lo puede cancelar el que lo pidio -------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub',u_otro)::text, true);
  begin
    perform public.cancelar_envio(env.id, 'no era mio');
    insert into _r values ('11. un ajeno no lo cancela', 'MAL  lo cancelo');
  exception when others then
    insert into _r values ('11. un ajeno no lo cancela', 'OK  rechazado');
  end;

  perform set_config('request.jwt.claims', json_build_object('sub',u_cli)::text, true);
  env := public.cancelar_envio(env.id, 'me lo trajo un amigo');
  insert into _r values ('12. el que lo pidio si lo cancela',
    case when env.estado = 'cancelado' then 'OK  cancelado' else 'MAL' end);
  perform set_config('request.jwt.claims', null, true);

  -- ---- Un envio no puede ser de los dos ni de ninguno ------------------------
  begin
    insert into public.envios (ciudad_id, origen_calle, destino_calle, cliente_nombre,
                               cliente_telefono, tarifario_id, distancia_km,
                               ganancia_repartidor, comision, paga)
    values (ciudad, 'a', 'b', 'x', 'y',
            (select id from public.tarifarios where vigente_hasta is null limit 1),
            1, 100, 10, 'cliente');
    insert into _r values ('13. sin local ni cliente no entra', 'MAL  lo dejo pasar');
  exception when others then
    insert into _r values ('13. sin local ni cliente no entra', 'OK  rechazado');
  end;

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.ofertas where envio_id = env.id;
  delete from public.envio_eventos where envio_id = env.id;
  delete from public.envios where cliente_id in (cli, otro);
  delete from public.repartidores where id = rep;
  delete from public.clientes where id in (cli, otro);
  delete from auth.users where id in (u_cli, u_otro, u_rep);
end $$;

select paso, resultado from _r order by length(paso), paso;
