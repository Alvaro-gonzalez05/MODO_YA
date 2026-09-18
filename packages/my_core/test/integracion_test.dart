// Test de integracion: los repositorios de la app contra la base REAL.
//
// Recorre el flujo completo que hacen las pantallas, con las mismas clases:
//
//   admin crea un local y un rider (Edge Function)
//   el local arma su menu con foto y opciones
//   el rider se conecta y comparte ubicacion
//   un cliente guarda su direccion, cotiza y hace un pedido
//   la administracion confirma el pago
//   el local lo acepta, lo prepara y lo marca listo
//   el rider recibe la oferta, la acepta, retira y entrega con el codigo
//   el cliente ve el codigo y el pedido termina entregado
//   y aparte: cadeteria con rechazo del rider, cancelacion y tiempo real
//
// Lo que prueba y un test SQL no puede: que los nombres de columnas de las
// vistas coincidan con los fromRow de Dart, que los parametros de las RPC esten
// bien escritos, que las respuestas se parseen, y que Realtime entregue eventos
// con el RLS de cada usuario.
//
// Preparacion (crea cuentas de prueba y env/test.json):
//   .\supabase\tests\preparar_prueba_app.ps1
// Corrida:
//   flutter test test/integracion_test.dart --dart-define-from-file=../../env/test.json
// Limpieza:
//   .\supabase\tests\preparar_prueba_app.ps1 -Limpiar

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_core/my_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Supabase;
import 'package:supabase_flutter/supabase_flutter.dart' as sb show Supabase;

const _adminEmail = String.fromEnvironment('MY_TEST_ADMIN_EMAIL');
const _adminPass = String.fromEnvironment('MY_TEST_ADMIN_PASSWORD');
const _clienteEmail = String.fromEnvironment('MY_TEST_CLIENTE_EMAIL');
const _clientePass = String.fromEnvironment('MY_TEST_CLIENTE_PASSWORD');

/// PNG de 1x1 para probar la subida de fotos sin depender de un archivo.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

// Malargue: el local en la plaza, el rider a ~400 m, el cliente a ~500 m.
const _local = (lat: -35.4761, lng: -69.5839);
const _rider = (lat: -35.4755, lng: -69.5800);
const _casa = (lat: -35.4790, lng: -69.5870);

const envios = EnviosRepository();
const comercios = ComerciosRepository();
const riders = RepartidoresRepository();
const catalogo = CatalogoRepository();
const pedidos = PedidosRepository();
const direcciones = DireccionesRepository();
const cuentas = CuentasRepository();
const auth = AuthRepository();

final _sello = DateTime.now().millisecondsSinceEpoch.toString().substring(7);
final _localEmail = 'local-$_sello@modoya.test';
final _riderEmail = 'rider-$_sello@modoya.test';

// Estado compartido entre pasos.
late String localPass;
late String riderPass;
late Sesion sLocal;
late Sesion sRider;
late Producto pizza;
late String direccionId;
late String pedidoId;
late String envioDelPedido;
String? codigoQueVeElCliente;
late String envioCadeteria;

Future<Sesion> entrarComo(String email, String pass) async {
  try {
    await auth.salir();
  } catch (_) {}
  await auth.entrar(email, pass);
  final r = await Backend.db.rpc('mi_sesion');
  return Sesion.fromJson(Map<String, dynamic>.from(r as Map), email: email);
}

/// Espera a que [condicion] se cumpla, reintentando. Para cosas asincronas del
/// servidor (motor de asignacion, Realtime).
Future<T> esperar<T>(Future<T> Function() leer, bool Function(T) condicion,
    {Duration limite = const Duration(seconds: 20), String que = 'la condicion'}) async {
  final fin = DateTime.now().add(limite);
  late T ultimo;
  while (DateTime.now().isBefore(fin)) {
    ultimo = await leer();
    if (condicion(ultimo)) return ultimo;
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  fail('Paso el tiempo esperando $que. Ultimo valor: $ultimo');
}

void main() {
  setUpAll(() async {
    if (_adminEmail.isEmpty || _clienteEmail.isEmpty || !Entorno.tieneSupabase) {
      fail('Faltan las variables de prueba. Corre supabase/tests/preparar_prueba_app.ps1 '
          'y usa --dart-define-from-file=../../env/test.json');
    }
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test bloquea la red por defecto (todo request devuelve 400).
    // Este test existe justamente para hablar con la base real.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});

    await sb.Supabase.initialize(
      url: Entorno.supabaseUrl,
      publishableKey: Entorno.supabaseKey,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        detectSessionInUri: false,
      ),
    );
  });

  tearDownAll(() async {
    try {
      await auth.salir();
    } catch (_) {}
  });

  const largo = Timeout(Duration(minutes: 2));

  // ---------------------------------------------------------------------------
  test('01 admin: sesion con rol admin', () async {
    final s = await entrarComo(_adminEmail, _adminPass);
    expect(s.rol, RolUsuario.admin);
  }, timeout: largo);

  test('02 admin: da de alta un local y un rider (Edge Function)', () async {
    final rubros = await catalogo.rubros();
    expect(rubros, isNotEmpty, reason: 'la semilla de rubros tiene que existir');
    final pizzeria = rubros.firstWhere((r) => r.nombre == 'Pizzería');

    final altaLocal = await cuentas.crearComercio(
      email: _localEmail,
      nombre: 'Pizzeria Test $_sello',
      telefono: '2604111111',
      calle: 'Av. Roca 420',
      referencia: 'Frente a la plaza',
      rubroId: pizzeria.id,
      lat: _local.lat,
      lng: _local.lng,
    );
    expect(altaLocal.passwordTemporal, isNotNull);
    localPass = altaLocal.passwordTemporal!;

    final altaRider = await cuentas.crearRepartidor(
      email: _riderEmail,
      nombre: 'Rider Test $_sello',
      telefono: '2604222222',
      vehiculo: Vehiculo.moto,
    );
    riderPass = altaRider.passwordTemporal!;

    final todos = await comercios.todos();
    final c = todos.firstWhere((c) => c.nombre == 'Pizzeria Test $_sello');
    expect(c.aprobacion, EstadoAprobacion.aprobado);
    expect(c.rubro, 'Pizzería');
    expect(c.direccion.lat, closeTo(_local.lat, 0.0001), reason: 'v_comercios tiene que traer lat numerico');
    expect(c.abierto, isFalse, reason: 'sin horarios cargados figura cerrado (0027)');
  }, timeout: largo);

  test('03 admin: un email repetido da un error legible', () async {
    await expectLater(
      cuentas.crearRepartidor(email: _riderEmail, nombre: 'Dup', telefono: '1', vehiculo: Vehiculo.moto),
      throwsA(isA<ErrorModoYa>().having((e) => e.codigo, 'codigo', 'email_existente')),
    );
  }, timeout: largo);

  // ---------------------------------------------------------------------------
  test('04 local: entra con la clave temporal y arma su menu con foto y opciones', () async {
    sLocal = await entrarComo(_localEmail, localPass);
    expect(sLocal.rol, RolUsuario.comercio);
    expect(sLocal.comercioId, isNotNull);
    expect(sLocal.aprobacion, EstadoAprobacion.aprobado);

    await catalogo.guardarSeccion(comercioId: sLocal.comercioId!, nombre: 'Pizzas');
    var menu = await catalogo.menu(sLocal.comercioId!);
    final seccion = menu.secciones.single;

    final id = await catalogo.guardarProducto(
      comercioId: sLocal.comercioId!,
      seccionId: seccion.id,
      nombre: 'Muzzarella',
      descripcion: 'Salsa casera',
      precio: 8000,
      foto: _png,
      fotoExtension: 'png',
      opciones: const [
        OpcionProducto(
          nombre: 'Tamano',
          obligatoria: true,
          items: [OpcionItem(nombre: 'Chica'), OpcionItem(nombre: 'Grande', precioExtra: 2000)],
        ),
        OpcionProducto(
          nombre: 'Agregados',
          tipo: TipoOpcion.multiple,
          items: [OpcionItem(nombre: 'Extra queso', precioExtra: 900)],
        ),
      ],
    );

    menu = await catalogo.menu(sLocal.comercioId!);
    pizza = menu.productos.firstWhere((p) => p.id == id);
    expect(pizza.fotoUrl, contains('/catalogo/${sLocal.comercioId}/productos/'));
    expect(pizza.opciones.map((o) => o.nombre), ['Tamano', 'Agregados']);
    expect(pizza.opciones.first.items.map((i) => i.nombre), ['Chica', 'Grande']);
    expect(pizza.opciones.first.items.last.precioExtra, 2000);
    expect(menu.deSeccion(seccion.id), hasLength(1));

    // La foto se sirve de verdad desde el bucket publico.
    final resp = await HttpClient().getUrl(Uri.parse(pizza.fotoUrl!)).then((r) => r.close());
    expect(resp.statusCode, 200, reason: 'la foto subida tiene que poder descargarse');
  }, timeout: largo);

  test('05 local: horarios que cruzan medianoche se guardan y se leen', () async {
    await comercios.guardarHorarios(const [
      Horario(dia: 5, abre: '20:00', cierra: '01:00'),
      Horario(dia: 6, abre: '11:00', cierra: '15:00'),
    ]);
    final h = await comercios.horarios(sLocal.comercioId!);
    expect(h.map((x) => '${x.dia} ${x.abre}-${x.cierra}'), ['5 20:00-01:00', '6 11:00-15:00']);
    expect(h.first.cruzaMedianoche, isTrue);
    // Todo el dia, todos los dias: el local queda abierto el resto del test
    // (sin horarios figuraria cerrado y no se le podria pedir).
    await comercios.guardarHorarios([
      for (var d = 0; d < 7; d++) Horario(dia: d, abre: '00:00', cierra: '23:59'),
    ]);
    final abierto = await comercios.porId(sLocal.comercioId!);
    expect(abierto!.abierto, isTrue);
  }, timeout: largo);

  test('06 local: no puede aprobarse ni tocar datos ajenos a su vidriera', () async {
    await expectLater(
      comercios.cambiarAprobacion(sLocal.comercioId!, EstadoAprobacion.suspendido),
      throwsA(isA<ErrorModoYa>().having((e) => e.codigo, 'codigo', '42501')),
    );
    await comercios.actualizar(sLocal.comercioId!, demoraEstimadaMin: 30);
    final c = await comercios.porId(sLocal.comercioId!);
    expect(c!.demoraEstimadaMin, 30);
  }, timeout: largo);

  // ---------------------------------------------------------------------------
  test('07 rider: se conecta con ubicacion', () async {
    sRider = await entrarComo(_riderEmail, riderPass);
    expect(sRider.rol, RolUsuario.repartidor);
    await riders.actualizarUbicacion(_rider.lat, _rider.lng);
    await riders.setConectado(true);
    final r = await riders.watchPorId(sRider.repartidorId!).first;
    expect(r!.conectado, isTrue);
    expect(r.ubicacion!.lat, closeTo(_rider.lat, 0.0001), reason: 'v_repartidores tiene que traer lat');
  }, timeout: largo);

  // ---------------------------------------------------------------------------
  test('08 cliente: ve el local, guarda direccion y cotiza', () async {
    final s = await entrarComo(_clienteEmail, _clientePass);
    expect(s.rol, RolUsuario.cliente);
    expect(s.clienteId, isNotNull, reason: 'el alta tiene que crear la ficha de cliente');

    final vidriera = await comercios.vidriera();
    final local = vidriera.firstWhere((c) => c.id == sLocal.comercioId);
    expect(local.abierto, isTrue);

    final publico = await catalogo.menu(local.id, soloDisponibles: true);
    expect(publico.productos.map((p) => p.id), contains(pizza.id));

    direccionId = await direcciones.agregar(
      alias: 'Casa',
      calle: 'San Martin 1240',
      referencia: 'Porton negro',
      lat: _casa.lat,
      lng: _casa.lng,
    );
    final mias = await direcciones.mias();
    final d = mias.firstWhere((x) => x.id == direccionId);
    expect(d.predeterminada, isTrue, reason: 'la primera direccion queda como principal');
    expect(d.lat, closeTo(_casa.lat, 0.0001));

    final cot = await pedidos.cotizar(comercioId: local.id, direccionId: direccionId);
    expect(cot.costoEnvio, greaterThanOrEqualTo(3500));
    expect(cot.minutosEstimados, greaterThan(30), reason: 'incluye los 30 min de demora del local');
  }, timeout: largo);

  test('09 cliente: hace el pedido y el precio lo pone el servidor', () async {
    final grande = pizza.opciones.first.items.firstWhere((i) => i.nombre == 'Grande');
    final queso = pizza.opciones.last.items.single;

    pedidoId = await pedidos.crear(
      comercioId: sLocal.comercioId!,
      direccionId: direccionId,
      nota: 'Tocar timbre',
      metodo: MetodoPago.tarjeta,
      items: [
        ItemCarrito(producto: pizza, cantidad: 2, elegidas: [grande, queso], nota: 'bien cocida'),
      ],
    );

    // Le llega al local en el momento: no espera a la administracion.
    final p = await pedidos.watchPorId(pedidoId).first;
    expect(p!.estado, EstadoPedido.pagado);
    expect(p.metodoPago, MetodoPago.tarjeta);
    expect(p.subtotal, (8000 + 2000 + 900) * 2);
    expect(p.items.single.opciones, containsAll(['Tamano: Grande', 'Agregados: Extra queso']));
    expect(p.clienteNombre, 'Cliente Prueba');

    final mis = await pedidos.watchDelCliente().first;
    expect(mis.map((x) => x.id), contains(pedidoId));
  }, timeout: largo);

  test('10 cliente: el servidor hace cumplir las reglas de las opciones', () async {
    final chica = pizza.opciones.first.items.firstWhere((i) => i.nombre == 'Chica');
    final grande = pizza.opciones.first.items.firstWhere((i) => i.nombre == 'Grande');

    Future<void> debeRebotar(List<OpcionItem> elegidas, String contiene) => expectLater(
          pedidos.crear(
            comercioId: sLocal.comercioId!,
            direccionId: direccionId,
            metodo: MetodoPago.efectivo,
            items: [ItemCarrito(producto: pizza, cantidad: 1, elegidas: elegidas)],
          ),
          throwsA(isA<ErrorModoYa>()
              .having((e) => e.codigo, 'codigo', 'MY006')
              .having((e) => e.mensaje, 'mensaje', contains(contiene))),
        );

    // Sin elegir el tamano (obligatorio).
    await debeRebotar(const [], 'Falta elegir tamano');
    // Dos tamanos en un grupo de eleccion unica.
    await debeRebotar([chica, grande], 'una sola opcion');
    // La misma opcion dos veces.
    await debeRebotar([grande, grande], 'repetida');

    // Una opcion que no existe.
    await expectLater(
      pedidos.crear(
        comercioId: sLocal.comercioId!,
        direccionId: direccionId,
        metodo: MetodoPago.efectivo,
        items: [
          ItemCarrito(
            producto: pizza,
            cantidad: 1,
            elegidas: const [OpcionItem(id: '00000000-0000-0000-0000-000000000000', nombre: 'trucha')],
          ),
        ],
      ),
      throwsA(isA<ErrorModoYa>()),
    );
  }, timeout: largo);

  // ---------------------------------------------------------------------------
  test('11 admin: ve el pedido por cobrar y registra el cobro', () async {
    await entrarComo(_adminEmail, _adminPass);
    final pendientes = await pedidos.watchPendientesDePago().first;
    final p = pendientes.firstWhere((x) => x.id == pedidoId);
    expect(p.items, isNotEmpty);
    expect(p.cobrado, isFalse);
    await pedidos.marcarPagado(pedidoId, MetodoPago.tarjeta);
    final despues = await pedidos.watchPendientesDePago().first;
    expect(despues.map((x) => x.id), isNot(contains(pedidoId)));
  }, timeout: largo);

  test('12 local: acepta, prepara y lo marca listo (sale a buscar rider)', () async {
    await entrarComo(_localEmail, localPass);
    final lista = await pedidos.watchDelComercio(sLocal.comercioId!).first;
    final p = lista.firstWhere((x) => x.id == pedidoId);
    expect(p.estado, EstadoPedido.pagado);
    expect(p.items.single.cantidad, 2);

    await pedidos.aceptar(pedidoId);
    await pedidos.avanzar(pedidoId, EstadoPedido.enPreparacion);
    await pedidos.avanzar(pedidoId, EstadoPedido.listo);

    final listo = await pedidos.watchPorId(pedidoId).first;
    expect(listo!.estado, EstadoPedido.listo);
    expect(listo.envioId, isNotNull);
    envioDelPedido = listo.envioId!;

    final e = await envios.watchPorId(envioDelPedido).first;
    expect(e!.estado, EstadoEnvio.buscandoRepartidor);
    expect(e.pedidoId, pedidoId);
  }, timeout: largo);

  // ---------------------------------------------------------------------------
  test('13 rider: recibe la oferta sin datos del cliente, la acepta y avanza', () async {
    await entrarComo(_riderEmail, riderPass);
    final ofertas = await esperar(
      () => envios.watchOfertas().first,
      (l) => l.any((o) => o.envio.id == envioDelPedido),
      que: 'la oferta del envio del pedido',
    );
    final oferta = ofertas.firstWhere((o) => o.envio.id == envioDelPedido);
    expect(oferta.envio.cliente.nombre, isEmpty, reason: 'antes de aceptar no ve al cliente');
    expect(oferta.distanciaAlRetiroKm, lessThan(3));
    expect(oferta.vencida, isFalse);

    await envios.responderOferta(oferta.id, acepta: true);
    var e = await envios.watchPorId(envioDelPedido).first;
    expect(e!.estado, EstadoEnvio.asignado);
    expect(e.cliente.nombre, 'Cliente Prueba', reason: 'al aceptar ya ve al cliente');

    await envios.avanzar(envioDelPedido, EstadoEnvio.enLocal);
    await envios.avanzar(envioDelPedido, EstadoEnvio.retirado);
    await envios.avanzar(envioDelPedido, EstadoEnvio.enCamino);
    e = await envios.watchPorId(envioDelPedido).first;
    expect(e!.estado, EstadoEnvio.enCamino);
  }, timeout: largo);

  test('14 cliente: ve el pedido en camino, al rider y el codigo de entrega', () async {
    await entrarComo(_clienteEmail, _clientePass);
    final p = await pedidos.watchPorId(pedidoId).first;
    expect(p!.estado, EstadoPedido.enCamino, reason: 'retirado arrastra al pedido');

    final seg = await pedidos.seguimiento(pedidoId);
    expect(seg!.repartidorNombre, 'Rider Test $_sello');
    expect(seg.codigoEntrega, matches(RegExp(r'^\d{4}$')));
    expect(seg.riderLat, isNotNull);
    codigoQueVeElCliente = seg.codigoEntrega;
  }, timeout: largo);

  test('15 rider: un codigo equivocado no cierra; el del cliente si', () async {
    await entrarComo(_riderEmail, riderPass);
    final equivocado = codigoQueVeElCliente == '0000' ? '1111' : '0000';
    await expectLater(
      envios.confirmarEntrega(envioDelPedido, equivocado),
      throwsA(isA<ErrorModoYa>().having((e) => e.codigo, 'codigo', 'MY002')),
    );
    await envios.confirmarEntrega(envioDelPedido, codigoQueVeElCliente!);

    final mios = await envios.watchDelRepartidor(sRider.repartidorId!).first;
    expect(mios.firstWhere((e) => e.id == envioDelPedido).estado, EstadoEnvio.entregado);
    final r = await riders.watchPorId(sRider.repartidorId!).first;
    expect(r!.ocupado, isFalse);
    expect(r.viajesCompletados, 1);
  }, timeout: largo);

  test('16 cliente: el pedido quedo entregado', () async {
    await entrarComo(_clienteEmail, _clientePass);
    final p = await pedidos.watchPorId(pedidoId).first;
    expect(p!.estado, EstadoPedido.entregado);
  }, timeout: largo);

  // ---------------------------------------------------------------------------
  test('17 local: cadeteria, el rider rechaza y el envio sigue buscando', () async {
    await entrarComo(_localEmail, localPass);
    final cot = await envios.cotizar(lat: _casa.lat, lng: _casa.lng);
    expect(cot.total, cot.gananciaRepartidor + cot.comision);

    envioCadeteria = await envios.crearYBuscar(
      calle: 'San Martin 1240',
      lat: _casa.lat,
      lng: _casa.lng,
      clienteNombre: 'Julian',
      clienteTelefono: '2604333333',
      paga: QuienPaga.comercio,
    );
    var e = await envios.watchPorId(envioCadeteria).first;
    expect(e!.estado, EstadoEnvio.buscandoRepartidor);
    expect(e.codigo, startsWith('MY-'));

    await entrarComo(_riderEmail, riderPass);
    final ofertas = await esperar(
      () => envios.watchOfertas().first,
      (l) => l.any((o) => o.envio.id == envioCadeteria),
      que: 'la oferta de cadeteria',
    );
    await envios.responderOferta(ofertas.firstWhere((o) => o.envio.id == envioCadeteria).id, acepta: false);

    // Antes quedaba `sin_repartidor` para siempre. Ahora sigue buscando: el
    // cron se lo vuelve a ofrecer (a este mismo rider, pasado un minuto).
    await entrarComo(_localEmail, localPass);
    await Future<void>.delayed(const Duration(seconds: 12));
    final sigue = await envios.watchPorId(envioCadeteria).first;
    expect(sigue!.estado, EstadoEnvio.buscandoRepartidor);
  }, timeout: largo);

  test('18 local: tiempo real, cancelar llega por Realtime', () async {
    final recibidos = <Envio?>[];
    final sub = envios.watchPorId(envioCadeteria).listen(recibidos.add);
    await esperar(() async => recibidos.length, (n) => n >= 1, que: 'la primera lectura');
    // Tiempo para que el canal quede suscripto.
    await Future<void>.delayed(const Duration(seconds: 3));

    await envios.cancelar(envioCadeteria, 'Prueba de tiempo real');

    await esperar(
      () async => recibidos,
      (l) => l.any((x) => x?.estado == EstadoEnvio.cancelado),
      limite: const Duration(seconds: 15),
      que: 'que Realtime avise la cancelacion sin volver a pedir',
    );
    await sub.cancel();
  }, timeout: largo);

  test('19 limpieza: el local borra su producto y la foto', () async {
    await catalogo.borrarProducto(pizza);
    final menu = await catalogo.menu(sLocal.comercioId!);
    expect(menu.productos, isEmpty);

    await entrarComo(_riderEmail, riderPass);
    await riders.setConectado(false);
  }, timeout: largo);
}
