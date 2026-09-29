-- Guardar tarifas no tiene que pisar lo que no se toco.
--
-- Existe por el hallazgo 4 de docs/hallazgos-de-la-revision.md: el insert de
-- admin_nuevo_tarifario nombraba las columnas una por una y `precio_plus_mensual`
-- nunca se sumo, asi que cada guardado devolvia el precio de Plus al default.

create temporary table _r (paso text, resultado text);

do $$
declare
  u_adm uuid := gen_random_uuid();
  ciudad uuid;
  original public.tarifarios;
  t public.tarifarios;
begin
  select id into ciudad from public.ciudades where nombre = 'Malargue';

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          raw_app_meta_data, raw_user_meta_data,
                          email_confirmed_at, created_at, updated_at)
  values (u_adm,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
          'tarifa-adm@test.local','x','{"rol":"admin"}','{"nombre":"Tarifa Admin"}',now(),now(),now());

  select * into original from public.tarifarios
   where ciudad_id = ciudad and servicio = 'delivery' and vigente_hasta is null;

  perform set_config('request.jwt.claims', json_build_object('sub',u_adm)::text, true);

  -- ---- Se fija un precio de Plus distinto del default ------------------------
  t := public.admin_nuevo_tarifario(
    ciudad, original.ganancia_repartidor_base, original.comision_modo_ya,
    original.precio_km_adicional, original.km_incluidos, original.radio_busqueda_km,
    original.segundos_para_aceptar, original.precio_suscripcion_mensual,
    'delivery', 4000);

  insert into _r values ('1. se puede fijar el precio de Plus',
    case when t.precio_plus_mensual = 4000 then 'OK  $4.000'
         else format('MAL  quedo en %s', t.precio_plus_mensual) end);

  -- Adentro de una transaccion now() no avanza, asi que al cerrar este
  -- tarifario quedaria vigente_hasta = vigente_desde y la restriccion de
  -- vigencia lo rechaza. En la vida real cada guardado es su propia
  -- transaccion; aca se lo envejece a mano.
  update public.tarifarios set vigente_desde = vigente_desde - interval '1 hour'
   where id = t.id;

  insert into _r values ('2. el cliente lo ve',
    case when public.precio_plus() = 4000 then 'OK  $4.000'
         else format('MAL  precio_plus() dice %s', public.precio_plus()) end);

  -- ---- Se guarda otra tarifa SIN mandar el precio de Plus --------------------
  -- Es lo que hacia la app antes de 0049, y lo que seguiria haciendo una app
  -- vieja que no conozca el parametro nuevo.
  t := public.admin_nuevo_tarifario(
    ciudad, original.ganancia_repartidor_base + 100, original.comision_modo_ya,
    original.precio_km_adicional, original.km_incluidos, original.radio_busqueda_km,
    original.segundos_para_aceptar, original.precio_suscripcion_mensual);

  insert into _r values ('3. tocar otra tarifa no pisa el de Plus',
    case when t.precio_plus_mensual = 4000 then 'OK  sigue en $4.000'
         else format('MAL  volvio a %s', t.precio_plus_mensual) end);

  insert into _r values ('4. y el cliente lo sigue viendo igual',
    case when public.precio_plus() = 4000 then 'OK  $4.000'
         else format('MAL  precio_plus() dice %s', public.precio_plus()) end);

  update public.tarifarios set vigente_desde = vigente_desde - interval '30 minutes'
   where id = t.id;

  -- ---- Se puede volver a cambiar --------------------------------------------
  t := public.admin_nuevo_tarifario(
    ciudad, original.ganancia_repartidor_base, original.comision_modo_ya,
    original.precio_km_adicional, original.km_incluidos, original.radio_busqueda_km,
    original.segundos_para_aceptar, original.precio_suscripcion_mensual,
    'delivery', 3000);

  insert into _r values ('5. se puede bajar de nuevo',
    case when t.precio_plus_mensual = 3000 then 'OK  $3.000' else 'MAL' end);

  perform set_config('request.jwt.claims', null, true);

  -- ---- Limpieza: se deja vigente el tarifario original -----------------------
  delete from public.tarifarios where ciudad_id = ciudad and creado_por = u_adm;
  update public.tarifarios set vigente_hasta = null where id = original.id;
  delete from auth.users where id = u_adm;

  select * into t from public.tarifarios where id = original.id;
  insert into _r values ('6. la base queda como estaba',
    case when t.vigente_hasta is null and t.precio_plus_mensual = original.precio_plus_mensual
         then 'OK  vigente el de siempre' else 'MAL  quedo tocado' end);
end $$;

select paso, resultado from _r order by paso;
