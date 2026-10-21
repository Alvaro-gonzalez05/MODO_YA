-- Un envío de cadetería no queda trabado en `cotizado` (migración 0067).
--
-- Tres cosas: que pedirlo sea atómico, que lo que ya quedó trabado se venza, y
-- que el vencimiento NO toque el envío de un pedido de la app, que espera en
-- `cotizado` a propósito mientras la cocina prepara.
--
-- Todo va dentro de un solo `do`: es una sola transacción, así que el cron
-- `vencer-ofertas` (que corre cada 10 s en otra sesión) nunca ve estos envíos
-- y ningún rider real recibe una oferta de prueba.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_com uuid := gen_random_uuid();
  u_cli uuid := gen_random_uuid();
  ciudad uuid; com uuid; cli uuid; dir uuid; sec uuid; prod uuid;
  env    public.envios;
  viejo  public.envios;
  nuevo  public.envios;
  delped public.envios;
  ped    public.pedidos;
  n      integer;
  ok     boolean;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, email_confirmed_at, created_at, updated_at)
  values
    (u_com,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','cotiz-com@test.local','x','{"rol":"comercio"}',now(),now(),now()),
    (u_cli,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','cotiz-cli@test.local','x','{"provider":"email"}',now(),now(),now());

  insert into public.comercios (perfil_id, ciudad_id, nombre, rubro, telefono, calle, ubicacion, estado_aprobacion)
  values (u_com, ciudad, 'Cotiz Local', 'Pizzeria', '2604000091', 'Roca 950',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5846, -35.4757), 4326)::extensions.geography, 'aprobado')
  returning id into com;

  insert into public.horarios_comercio (comercio_id, dia, abre, cierra)
  select com, d, '00:00', '23:59' from generate_series(0, 6) d;
  insert into public.secciones_menu (comercio_id, nombre) values (com, 'Pizzas') returning id into sec;
  insert into public.productos (comercio_id, seccion_id, nombre, precio, disponible)
  values (com, sec, 'Muzzarella', 10000, true) returning id into prod;

  select id into cli from public.clientes where perfil_id = u_cli;
  insert into public.direcciones_cliente (cliente_id, alias, calle, ubicacion, predeterminada)
  values (cli, 'Casa', 'San Martin 550',
          extensions.ST_SetSRID(extensions.ST_MakePoint(-69.5800, -35.4700), 4326)::extensions.geography, true)
  returning id into dir;

  -- ---- 1. Pedirlo es una sola llamada ---------------------------------------
  -- Con el rol `authenticated` puesto, que es como llama la app: si faltara el
  -- grant, esto explotaria.
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  begin
    set local role authenticated;
    env := public.pedir_envio('Alvear 100', -35.4720, -69.5810, 'Cliente Uno', '2604555001', 'cliente');
    reset role;
  exception when others then
    reset role;
    insert into _r values ('01 pedir_envio sale a buscar de una', 'MAL  ' || left(sqlerrm, 60));
  end;
  perform set_config('request.jwt.claims', null, true);

  if env.id is not null then
    insert into _r values ('01 pedir_envio sale a buscar de una',
      case when env.estado = 'buscando_repartidor' and env.confirmado_en is not null
           then 'OK  nace buscando rider'
           else format('MAL  estado=%s confirmado=%s', env.estado, env.confirmado_en) end);
  end if;

  -- ---- 2. Lo que quedo trabado se vence -------------------------------------
  -- Como lo dejaba la app vieja: crear_envio y nada mas.
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  viejo := public.crear_envio('Alvear 200', -35.4730, -69.5820, 'Cliente Dos', '2604555002', 'cliente');
  nuevo := public.crear_envio('Alvear 300', -35.4740, -69.5830, 'Cliente Tres', '2604555003', 'cliente');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('02 crear_envio solo deja el envio en cotizado',
    case when viejo.estado = 'cotizado' then 'OK  asi quedaba trabado'
         else 'MAL  ' || viejo.estado end);

  update public.envios set creado_en = now() - interval '20 minutes' where id = viejo.id;

  n := public.vencer_envios_cotizados();

  insert into _r values ('03 el de hace 20 minutos se cancela',
    (select case when estado = 'cancelado'
                   and motivo_cancelacion = 'No se llegó a confirmar la búsqueda de rider'
                 then 'OK  con el motivo escrito'
                 else format('MAL  %s / %s', estado, motivo_cancelacion) end
       from public.envios where id = viejo.id));

  insert into _r values ('04 el recien creado no se toca',
    (select case when estado = 'cotizado' then 'OK  todavia esta a tiempo'
                 else 'MAL  ' || estado end
       from public.envios where id = nuevo.id));

  -- ---- 3. El envio de un pedido de la app espera a la cocina ----------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_cli)::text, true);
  ped := public.crear_pedido(com, dir,
    jsonb_build_array(jsonb_build_object('producto_id', prod, 'cantidad', 1)), null, 'mercado_pago');
  perform set_config('request.jwt.claims', null, true);

  ped := public.confirmar_pago_online(ped.id, 'PAY-COTIZ', 'acreditado'::public.estado_pago,
    1::smallint, null, 'simulado-orden-cotiz');

  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  ped := public.aceptar_pedido(ped.id);
  perform set_config('request.jwt.claims', null, true);

  select * into delped from public.envios where id = ped.envio_id;
  insert into _r values ('05 aceptar el pedido deja el envio en cotizado',
    case when delped.estado = 'cotizado' then 'OK  esperando la cocina'
         else 'MAL  ' || delped.estado end);

  -- Una cocina lenta: hora y media. El cron no se lo puede llevar.
  update public.envios set creado_en = now() - interval '90 minutes' where id = ped.envio_id;
  n := public.vencer_envios_cotizados();

  insert into _r values ('06 el envio del pedido sobrevive al cron',
    (select case when estado = 'cotizado' then 'OK  el cron no mata pedidos en el horno'
                 else 'MAL  ' || estado end
       from public.envios where id = ped.envio_id));

  insert into _r values ('07 y el pedido tampoco se cayo',
    (select case when estado = 'aceptado' then 'OK' else 'MAL  ' || estado end
       from public.pedidos where id = ped.id));

  -- Y cuando esta listo sale a buscar como siempre.
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  ped := public.avanzar_pedido(ped.id, 'en_preparacion');
  ped := public.avanzar_pedido(ped.id, 'listo');
  perform set_config('request.jwt.claims', null, true);

  insert into _r values ('08 listo lo saca a buscar igual que antes',
    (select case when estado = 'buscando_repartidor' then 'OK'
                 else 'MAL  ' || estado end
       from public.envios where id = ped.envio_id));

  -- ---- 4. El local puede sacarlo a buscar a mano ----------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', u_com)::text, true);
  begin
    set local role authenticated;
    env := public.confirmar_envio(nuevo.id);
    reset role;
    insert into _r values ('09 el local saca a buscar el que quedo trabado',
      case when env.estado = 'buscando_repartidor' then 'OK  boton "Buscar rider ahora"'
           else 'MAL  ' || env.estado end);
  exception when others then
    reset role;
    insert into _r values ('09 el local saca a buscar el que quedo trabado',
      'MAL  ' || left(sqlerrm, 60));
  end;
  perform set_config('request.jwt.claims', null, true);

  -- ---- 5. El cron no lo puede llamar un usuario -----------------------------
  -- Cancela envios de cualquier local: solo el cron.
  ok := false;
  begin
    set local role authenticated;
    n := public.vencer_envios_cotizados();
    reset role;
  exception when others then
    reset role;
    ok := true;
  end;
  insert into _r values ('10 NO un usuario vence envios de otros',
    case when ok then 'OK  sin permiso' else 'VULNERABLE lo pudo correr' end);

  insert into _r values ('11 el cron esta programado',
    case when exists (select 1 from cron.job where jobname = 'vencer-cotizados')
         then 'OK  cada 5 minutos' else 'MAL  no quedo agendado' end);

  -- ---- Limpieza --------------------------------------------------------------
  delete from public.ofertas where envio_id in (
    select id from public.envios where comercio_id = com
  );
  delete from public.envio_eventos where envio_id in (
    select id from public.envios where comercio_id = com
  );
  delete from public.pedido_item_opciones where pedido_item_id in
    (select id from public.pedido_items where pedido_id = ped.id);
  delete from public.pedido_items where pedido_id = ped.id;
  delete from public.pedido_eventos where pedido_id = ped.id;
  update public.pedidos set pago_id = null, envio_id = null where id = ped.id;
  delete from public.pagos where id = ped.pago_id;
  delete from public.envios where comercio_id = com;
  delete from public.pedidos where id = ped.id;
  delete from public.productos where comercio_id = com;
  delete from public.secciones_menu where comercio_id = com;
  delete from public.horarios_comercio where comercio_id = com;
  delete from public.direcciones_cliente where cliente_id = cli;
  delete from public.clientes where id = cli;
  delete from public.comercios where id = com;
  delete from auth.users where id in (u_com, u_cli);
end $$;

select paso, resultado from _r order by paso;
