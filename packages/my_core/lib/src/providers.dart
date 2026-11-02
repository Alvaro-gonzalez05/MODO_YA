import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';
import 'models/estados.dart';
import 'models/marketplace.dart';
import 'models/models.dart';
import 'repositories/campanias_repository.dart';
import 'repositories/carteles_repository.dart';
import 'repositories/documentacion_repository.dart';
import 'repositories/liquidaciones_repository.dart';
import 'repositories/mp_notificaciones_repository.dart';
import 'repositories/notificaciones_repository.dart';
import 'repositories/pagos_repository.dart';
import 'repositories/catalogo_repository.dart';
import 'repositories/comercios_repository.dart';
import 'repositories/cuentas_repository.dart';
import 'repositories/envios_repository.dart';
import 'repositories/pedidos_repository.dart';
import 'repositories/preinscripciones_repository.dart';
import 'repositories/promociones_repository.dart';
import 'repositories/reclamos_repository.dart';
import 'repositories/repartidores_repository.dart';
import 'repositories/solicitudes_rider_repository.dart';
import 'repositories/tarifas_repository.dart';
import 'push.dart';
import 'sesion.dart';

// ---- Repositorios -----------------------------------------------------------
//
// Las pantallas consumen siempre estos providers. En un test se sobrescriben
// con una clase que haga `implements EnviosRepository` (en Dart toda clase es
// tambien una interfaz).

final enviosRepositoryProvider = Provider((_) => const EnviosRepository());
final comerciosRepositoryProvider = Provider((_) => const ComerciosRepository());
final repartidoresRepositoryProvider = Provider((_) => const RepartidoresRepository());
final tarifasRepositoryProvider = Provider((_) => const TarifasRepository());
final catalogoRepositoryProvider = Provider((_) => const CatalogoRepository());
final pedidosRepositoryProvider = Provider((_) => const PedidosRepository());
final direccionesRepositoryProvider = Provider((_) => const DireccionesRepository());
final cuentasRepositoryProvider = Provider((_) => const CuentasRepository());
final cartelesRepositoryProvider = Provider((_) => const CartelesRepository());
final pagosRepositoryProvider = Provider((_) => const PagosRepository());
final liquidacionesRepositoryProvider = Provider((_) => const LiquidacionesRepository());
final campaniasRepositoryProvider = Provider((_) => const CampaniasRepository());
final promocionesRepositoryProvider = Provider((_) => const PromocionesRepository());
final notificacionesRepositoryProvider = Provider((_) => const NotificacionesRepository());

/// Anota el celular para recibir notificaciones cuando alguien entra, y lo
/// olvida cuando sale.
///
/// Va atado a la sesión y no al arranque de la app: antes de saber quién es no
/// hay a quién anotarle el token, y si no se borrara al salir, el que preste el
/// celular recibiría las notificaciones del dueño anterior.
final pushProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<Sesion?>>(sesionActualProvider, (antes, ahora) {
    final habia = antes?.value != null;
    final hay = ahora.value != null;
    if (hay && !habia) MyPush.registrar();
    if (habia && !hay) MyPush.olvidar();
  }, fireImmediately: true);
});

/// Lo que traía la última notificación que se tocó, para que la app navegue.
/// Null hasta que se toque alguna.
final pushDestinoProvider = StreamProvider<Map<String, String>?>((ref) async* {
  // La que abrió la app desde cerrada llegó antes de que hubiera oyentes.
  final pendiente = MyPush.tomarPendiente();
  if (pendiente != null) yield pendiente;
  yield* MyPush.alTocar.stream;
});

// ---- Comunes ----------------------------------------------------------------

final tarifarioProvider = StreamProvider<Tarifario?>(
  (ref) => enVivo(
    canal: 'tarifario',
    tablas: const ['tarifarios'],
    leer: ref.watch(tarifasRepositoryProvider).vigente,
  ),
);

final rubrosProvider = StreamProvider<List<Rubro>>(
  (ref) => enVivo(
    canal: 'rubros',
    tablas: const ['rubros'],
    leer: ref.watch(catalogoRepositoryProvider).rubros,
  ),
);

final comercioPorIdProvider = StreamProvider.family<Comercio?, String>(
  (ref, id) => enVivo(
    canal: 'comercio-$id',
    tablas: const ['comercios', 'horarios_comercio'],
    leer: () => ref.read(comerciosRepositoryProvider).porId(id),
    refrescarCada: const Duration(minutes: 1),
  ),
);

// ---- Local ------------------------------------------------------------------

/// El local de la sesion. Se invalida despues de editar sus datos.
final comercioActualProvider = StreamProvider<Comercio?>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Stream.value(null);
  return enVivo(
    canal: 'mi-comercio',
    tablas: const ['comercios', 'horarios_comercio'],
    leer: () => ref.read(comerciosRepositoryProvider).porId(id),
    refrescarCada: const Duration(minutes: 1),
  );
});

final enviosDelComercioProvider = StreamProvider<List<Envio>>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Stream.value(const []);
  return ref.watch(enviosRepositoryProvider).watchDelComercio(id);
});

final pedidosDelComercioProvider = StreamProvider<List<Pedido>>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Stream.value(const []);
  return ref.watch(pedidosRepositoryProvider).watchDelComercio(id);
});

/// Menu completo (incluye lo no disponible). Para el editor del local.
final menuDeComercioProvider = StreamProvider.family<Menu, String>(
  (ref, comercioId) => enVivo(
    canal: 'menu-$comercioId',
    tablas: _tablasMenu,
    leer: () => ref.read(catalogoRepositoryProvider).menu(comercioId),
  ),
);

final horariosProvider = StreamProvider.family<List<Horario>, String>(
  (ref, comercioId) => enVivo(
    canal: 'horarios-$comercioId',
    tablas: const ['horarios_comercio'],
    leer: () => ref.read(comerciosRepositoryProvider).horarios(comercioId),
  ),
);

final envioProvider = StreamProvider.family<Envio?, String>(
  (ref, id) => ref.watch(enviosRepositoryProvider).watchPorId(id),
);

// ---- Cliente ----------------------------------------------------------------

/// Carteles del inicio, en vivo: si la administracion los edita, cambian solos.
final cartelesActivosProvider = StreamProvider<List<Cartel>>(
  (ref) => ref.watch(cartelesRepositoryProvider).watchActivos(),
);

/// Todos los carteles (tambien los apagados), para el editor del panel.
final cartelesProvider = StreamProvider<List<Cartel>>(
  (ref) => enVivo(
    canal: 'carteles-todos',
    tablas: const ['carteles'],
    leer: ref.watch(cartelesRepositoryProvider).todos,
  ),
);

/// Vidriera del cliente, opcionalmente filtrada por rubro.
final vidrieraProvider = StreamProvider.family<List<Comercio>, String?>(
  (ref, rubroId) => enVivo(
    canal: 'vidriera-${rubroId ?? 'todos'}',
    tablas: const ['comercios', 'horarios_comercio'],
    leer: () => ref.read(comerciosRepositoryProvider).vidriera(rubroId: rubroId),
    refrescarCada: const Duration(minutes: 1),
  ),
);

/// Menu que ve el cliente: solo lo disponible.
final menuPublicoProvider = StreamProvider.family<Menu, String>(
  (ref, comercioId) => enVivo(
    canal: 'menu-publico-$comercioId',
    tablas: _tablasMenu,
    leer: () => ref.read(catalogoRepositoryProvider).menu(comercioId, soloDisponibles: true),
  ),
);

final direccionesProvider = StreamProvider<List<DireccionCliente>>(
  (ref) => enVivo(
    canal: 'direcciones',
    tablas: const ['direcciones_cliente'],
    leer: ref.watch(direccionesRepositoryProvider).mias,
  ),
);

final pedidosDelClienteProvider = StreamProvider<List<Pedido>>(
  (ref) => ref.watch(pedidosRepositoryProvider).watchDelCliente(),
);

/// Todos los pedidos recientes, para la sección Pedidos de la administración.
final todosLosPedidosProvider = StreamProvider<List<Pedido>>(
  (ref) => ref.watch(pedidosRepositoryProvider).watchTodos(),
);

final pedidoProvider = StreamProvider.family<Pedido?, String>(
  (ref, id) => ref.watch(pedidosRepositoryProvider).watchPorId(id),
);

// ---- Rider ------------------------------------------------------------------

final repartidorActualProvider = StreamProvider<Repartidor?>((ref) {
  final id = ref.watch(sesionProvider).repartidorId;
  if (id == null) return Stream.value(null);
  return ref.watch(repartidoresRepositoryProvider).watchPorId(id);
});

final enviosDelRepartidorProvider = StreamProvider<List<Envio>>((ref) {
  final id = ref.watch(sesionProvider).repartidorId;
  if (id == null) return Stream.value(const []);
  return ref.watch(enviosRepositoryProvider).watchDelRepartidor(id);
});

/// Los envios que el rider tiene en curso: uno, o dos si se sumo un segundo
/// pedido del mismo local (0056).
final enviosEnCursoProvider = Provider<AsyncValue<List<Envio>>>((ref) {
  return ref.watch(enviosDelRepartidorProvider).whenData(
        (lista) => lista.where((e) => e.estado.esActivo).toList(),
      );
});

final ofertasProvider = StreamProvider<List<OfertaServicio>>((ref) {
  if (ref.watch(sesionProvider).repartidorId == null) return Stream.value(const []);
  return ref.watch(enviosRepositoryProvider).watchOfertas();
});

// ---- Administracion ---------------------------------------------------------

final todosLosComerciosProvider = StreamProvider<List<Comercio>>(
  (ref) => enVivo(
    canal: 'comercios-todos',
    tablas: const ['comercios', 'horarios_comercio'],
    leer: ref.watch(comerciosRepositoryProvider).todos,
    refrescarCada: const Duration(minutes: 1),
  ),
);

final todosLosRepartidoresProvider = StreamProvider<List<Repartidor>>(
  (ref) => ref.watch(repartidoresRepositoryProvider).watchTodos(),
);

final enviosActivosProvider = StreamProvider<List<Envio>>(
  (ref) => ref.watch(enviosRepositoryProvider).watchActivos(),
);

/// Liquidaciones pendientes del período elegido (administración).
typedef Periodo = ({DateTime desde, DateTime hasta});

final pendientesComerciosProvider = StreamProvider.family<List<PendienteComercio>, Periodo>(
  (ref, p) => ref.watch(liquidacionesRepositoryProvider).watchPendientesComercios(p.desde, p.hasta),
);

final pendientesRidersProvider = StreamProvider.family<List<PendienteRider>, Periodo>(
  (ref, p) => ref.watch(liquidacionesRepositoryProvider).watchPendientesRiders(p.desde, p.hasta),
);

final historialLiquidacionesProvider = StreamProvider<List<Liquidacion>>(
  (ref) => ref.watch(liquidacionesRepositoryProvider).watchHistorial(),
);

final cargosDeComercioProvider = StreamProvider.family<List<CargoComercio>, String>(
  (ref, id) => ref.watch(liquidacionesRepositoryProvider).watchCargos(id),
);

/// El detalle de lo que se le va a pagar a un rider en un período.
typedef RangoDeRider = ({String repartidorId, DateTime desde, DateTime hasta});

final detalleDeRiderProvider =
    FutureProvider.family<List<RenglonDeRider>, RangoDeRider>((ref, r) =>
        ref.watch(liquidacionesRepositoryProvider).detalleDeRider(r.repartidorId, r.desde, r.hasta));

/// Cargos de un rider, para la administración y para el propio rider.
final cargosDeRiderProvider = StreamProvider.family<List<CargoRider>, String>(
  (ref, id) => ref.watch(liquidacionesRepositoryProvider).watchCargosRider(id),
);

/// Los riders que se bajaron de un envío, para que la administración decida.
final abandonosProvider = StreamProvider.family<List<AbandonoDeEnvio>, String?>(
  (ref, repartidorId) =>
      ref.watch(liquidacionesRepositoryProvider).watchAbandonos(repartidorId: repartidorId),
);

/// Campañas del local de la sesión (publicidad y MODO YA Plus).
final campaniasDelComercioProvider = StreamProvider<List<Campania>>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Stream.value(const []);
  return ref.watch(campaniasRepositoryProvider).watchDelComercio(id);
});

final rendimientoCampaniaProvider = FutureProvider.family<RendimientoCampania, String>(
  (ref, id) => ref.watch(campaniasRepositoryProvider).rendimiento(id),
);

final gastosDeCampaniaProvider = StreamProvider.family<List<GastoCampania>, String>(
  (ref, id) => ref.watch(campaniasRepositoryProvider).watchGastos(id),
);

/// Promociones del local de la sesión (descuentos sobre su menú).
final promocionesDelComercioProvider = StreamProvider<List<Promocion>>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Stream.value(const []);
  return ref.watch(promocionesRepositoryProvider).watchDelComercio(id);
});

/// Todas las promociones, para la administración.
final promocionesDeTodosProvider = StreamProvider<List<Promocion>>(
  (ref) => ref.watch(promocionesRepositoryProvider).watchTodas(),
);

/// Los mandados que pidió el cliente de la sesión.
final misMandadosProvider = StreamProvider<List<Envio>>(
  (ref) => ref.watch(enviosRepositoryProvider).watchMisMandados(),
);

/// Los riders que el local puede elegir como suyos.
final ridersParaElegirProvider = StreamProvider<List<RiderParaElegir>>(
  (ref) => ref.watch(repartidoresRepositoryProvider).watchParaElegir(),
);

/// Todas las notificaciones, para la administración.
final notificacionesProvider = StreamProvider<List<Notificacion>>(
  (ref) => ref.watch(notificacionesRepositoryProvider).watchTodas(),
);

/// La bandeja de quien está usando la app (la campanita).
final misNotificacionesProvider = StreamProvider<List<MiNotificacion>>(
  (ref) => ref.watch(notificacionesRepositoryProvider).watchMias(),
);

/// Cuántas tiene sin leer, para el globito.
final noLeidasProvider = Provider<int>(
  (ref) => ref.watch(misNotificacionesProvider).value?.where((n) => !n.leida).length ?? 0,
);

/// MODO YA Plus del cliente.
final miPlusProvider = StreamProvider<EstadoPlus>(
  (ref) => ref.watch(pagosRepositoryProvider).watchPlus(),
);

/// Tarjetas guardadas del cliente que está usando la app.
final tarjetasGuardadasProvider = StreamProvider<List<TarjetaGuardada>>(
  (ref) => ref.watch(pagosRepositoryProvider).watchTarjetas(),
);

/// Todo lo que forma un menú: si cambia cualquiera, se vuelve a leer.
const _tablasMenu = ['secciones_menu', 'productos', 'opciones_producto', 'opcion_items'];

final solicitudesRiderRepositoryProvider = Provider((_) => const SolicitudesRiderRepository());

/// Las solicitudes de alta de rider: las del local, o todas para la
/// administración (lo decide el RLS).
final solicitudesRiderProvider = StreamProvider<List<SolicitudRider>>(
  (ref) => ref.watch(solicitudesRiderRepositoryProvider).watch(),
);

final preinscripcionesRepositoryProvider = Provider((_) => const PreinscripcionesRepository());

/// Los formularios de la landing (locales y riders que quieren sumarse). Solo
/// los ve la administración.
final preinscripcionesProvider = StreamProvider<List<Preinscripcion>>(
  (ref) => ref.watch(preinscripcionesRepositoryProvider).watch(),
);

// ---- Mi liquidación: lo que el rider y el local están por cobrar ------------
//
// Todo esto sale de las mismas funciones que usa la administración (0065 las
// abrió al dueño de los datos). No hay una consulta paralela "para el rider" a
// propósito: dos consultas distintas son dos números que un día no van a
// coincidir, y el que cobra menos de lo que esperaba no vuelve a confiar en la
// pantalla.

/// El resumen del período del rider de la sesión.
///
/// Es `null` cuando no hizo nada en el período: la función devuelve una fila por
/// rider con movimiento, no una fila en cero (ver el comentario de 0065). La
/// pantalla distingue "todavía no hiciste nada" de "cargando".
final miLiquidacionDeRiderProvider =
    Provider.family<AsyncValue<PendienteRider?>, Periodo>((ref, p) {
  final id = ref.watch(sesionProvider).repartidorId;
  if (id == null) return const AsyncValue.data(null);
  return ref.watch(pendientesRidersProvider(p)).whenData(
        (lista) => lista.where((x) => x.repartidorId == id).firstOrNull,
      );
});

/// El resumen del período del local de la sesión.
final miLiquidacionDeComercioProvider =
    Provider.family<AsyncValue<PendienteComercio?>, Periodo>((ref, p) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return const AsyncValue.data(null);
  return ref.watch(pendientesComerciosProvider(p)).whenData(
        (lista) => lista.where((x) => x.comercioId == id).firstOrNull,
      );
});

/// Los pedidos que entran en la liquidación de un local, uno por uno.
typedef RangoDeComercio = ({String comercioId, DateTime desde, DateTime hasta});

final detalleDeComercioProvider =
    FutureProvider.family<List<RenglonDeComercio>, RangoDeComercio>((ref, r) =>
        ref.watch(liquidacionesRepositoryProvider).detalleDeComercio(r.comercioId, r.desde, r.hasta));

/// Los descuentos del período, con el mismo filtro que el resumen.
final cargosDelPeriodoRiderProvider =
    FutureProvider.family<List<RenglonDeCargo>, RangoDeRider>((ref, r) =>
        ref.watch(liquidacionesRepositoryProvider).cargosDelRider(r.repartidorId, r.desde, r.hasta));

final cargosDelPeriodoComercioProvider =
    FutureProvider.family<List<RenglonDeCargo>, RangoDeComercio>((ref, r) =>
        ref.watch(liquidacionesRepositoryProvider).cargosDelComercio(r.comercioId, r.desde, r.hasta));

/// El historial de liquidaciones cerradas de quien está usando la app.
final misLiquidacionesDeRiderProvider = StreamProvider<List<Liquidacion>>((ref) {
  final id = ref.watch(sesionProvider).repartidorId;
  if (id == null) return Stream.value(const []);
  return ref.watch(liquidacionesRepositoryProvider).watchMisLiquidacionesRider(id);
});

final misLiquidacionesDeComercioProvider = StreamProvider<List<Liquidacion>>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Stream.value(const []);
  return ref.watch(liquidacionesRepositoryProvider).watchMisLiquidacionesComercio(id);
});

/// El renglón por renglón de una liquidación ya cerrada.
///
/// La clave es un record y no la `Liquidacion`: un record compara por valor, y
/// una familia de Riverpod que recibe un objeto nuevo en cada `build` vuelve a
/// consultar para siempre.
typedef Cerrada = ({String liquidacionId, bool esComercio});

final renglonesCerradosProvider =
    FutureProvider.family<List<RenglonCerrado>, Cerrada>((ref, c) => ref
        .watch(liquidacionesRepositoryProvider)
        .renglonesCerrados(c.liquidacionId, esComercio: c.esComercio));
// ---- Reclamos y documentación del rider -------------------------------------
//
// Las dos cosas tenían la base entera y ninguna pantalla (hallazgos 6 y 7).

final reclamosRepositoryProvider = Provider((_) => const ReclamosRepository());

/// Los reclamos que puede ver el que está usando la app: los que abrió él, o
/// todos si es la administración. Una sola consulta para los dos casos porque
/// lo decide el RLS (`reclamos_leer`), no la app.
final reclamosProvider = StreamProvider<List<Reclamo>>(
  (ref) => ref.watch(reclamosRepositoryProvider).watch(),
);

/// Los reclamos de un pedido, para mostrarlos en su seguimiento.
final reclamosDelPedidoProvider = Provider.family<List<Reclamo>, String>(
  (ref, pedidoId) => (ref.watch(reclamosProvider).value ?? const <Reclamo>[])
      .where((r) => r.pedidoId == pedidoId)
      .toList(),
);

/// Cuántos reclamos esperan una decisión de la administración, para el globito
/// del panel.
final reclamosSinResolverProvider = Provider<int>(
  (ref) => (ref.watch(reclamosProvider).value ?? const <Reclamo>[])
      .where((r) => !r.estado.esCerrado)
      .length,
);

final documentacionRepositoryProvider = Provider((_) => const DocumentacionRepository());

/// Qué documentos se le exigen a cada vehículo. Cambia muy de vez en cuando
/// (es un insert en `documentos_exigidos`), así que se lee una vez por sesión.
final documentosExigidosProvider = FutureProvider<List<DocumentoExigido>>(
  (ref) => ref.watch(documentacionRepositoryProvider).exigidos(),
);

/// Toda la documentación que el RLS deja ver: la de todos si es la
/// administración, la propia si es un rider.
final documentacionProvider = StreamProvider<List<DocumentoRider>>(
  (ref) => ref.watch(documentacionRepositoryProvider).watch(),
);

/// La carpeta de un rider, cruzando lo que se le exige por su vehículo con lo
/// que subió. La usan la pantalla del rider y la ficha de la administración.
typedef RiderYVehiculo = ({String repartidorId, Vehiculo vehiculo});

final carpetaDeRiderProvider = Provider.family<AsyncValue<CarpetaRider>, RiderYVehiculo>((ref, r) {
  final exigidos = ref.watch(documentosExigidosProvider);
  final subidos = ref.watch(documentacionProvider);
  if (exigidos.hasError) return AsyncValue<CarpetaRider>.error(exigidos.error!, exigidos.stackTrace!);
  if (subidos.hasError) return AsyncValue<CarpetaRider>.error(subidos.error!, subidos.stackTrace!);
  if (!exigidos.hasValue || !subidos.hasValue) return const AsyncValue<CarpetaRider>.loading();
  return AsyncValue.data(CarpetaRider.armar(
    vehiculo: r.vehiculo,
    exigidos: exigidos.value!,
    subidos: subidos.value!.where((d) => d.repartidorId == r.repartidorId).toList(),
  ));
});

/// La carpeta del rider que está usando la app del rider.
final miCarpetaProvider = Provider<AsyncValue<CarpetaRider>>((ref) {
  final rider = ref.watch(repartidorActualProvider);
  if (rider.hasError) return AsyncValue<CarpetaRider>.error(rider.error!, rider.stackTrace!);
  final r = rider.value;
  if (r == null) return const AsyncValue<CarpetaRider>.loading();
  return ref.watch(carpetaDeRiderProvider((repartidorId: r.id, vehiculo: r.vehiculo)));
});

/// Cuántos documentos esperan que la administración los mire, para el globito.
final documentosSinRevisarProvider = Provider<int>(
  (ref) => (ref.watch(documentacionProvider).value ?? const <DocumentoRider>[])
      .where((d) => d.estado == EstadoAprobacion.pendiente)
      .length,
);

// ---- El resumen de la administración ----------------------------------------

/// Las cuatro consultas que alimentan el resumen de la administración, juntas.
///
/// Eran cinco: la quinta traía los pedidos con el cobro sin registrar, de
/// cuando se pagaba en efectivo o por transferencia. Desde 0058 el cobro lo
/// acredita Mercado Pago y nadie lo registra a mano, así que salió con la
/// sección Cobros.
typedef ResumenAdmin = ({
  List<Comercio> comercios,
  List<Repartidor> riders,
  List<Envio> enviosActivos,
  List<Preinscripcion> preinscripciones,
});

/// Junta las consultas del panel en un solo [AsyncValue].
///
/// El panel las leía por separado con `.value ?? const []`, y una consulta que
/// fallaba se veía igual que una que no tiene nada: ceros y "Todo en orden".
/// Eso es peor que no mostrar nada, porque la administración se queda
/// tranquila mientras no ve la mitad de la operación. Juntándolas acá el
/// error de cualquiera llega como error a `MyAsync`, que ya muestra el cartel
/// con "Reintentar" en el resto de la app.
final resumenAdminProvider = Provider<AsyncValue<ResumenAdmin>>((ref) {
  final comercios = ref.watch(todosLosComerciosProvider);
  final riders = ref.watch(todosLosRepartidoresProvider);
  final envios = ref.watch(enviosActivosProvider);
  final preinscripciones = ref.watch(preinscripcionesProvider);

  final partes = <AsyncValue<Object?>>[comercios, riders, envios, preinscripciones];

  for (final p in partes) {
    // El error solo gana si esa consulta nunca llegó a traer nada. Si ya había
    // datos se siguen mostrando: es la misma política de `MyAsync`, que
    // prefiere lo de hace un segundo a parpadear en cada refresco.
    if (p.hasError && !p.hasValue) {
      return AsyncError(p.error!, p.stackTrace ?? StackTrace.empty);
    }
  }
  for (final p in partes) {
    if (!p.hasValue) return const AsyncLoading();
  }

  return AsyncData((
    comercios: comercios.requireValue,
    riders: riders.requireValue,
    enviosActivos: envios.requireValue,
    preinscripciones: preinscripciones.requireValue,
  ));
});

/// Vuelve a pedir todas las consultas del resumen. El refresco del panel solo
/// invalidaba dos, así que el mapa no se movía.
void refrescarResumenAdmin(WidgetRef ref) {
  ref.invalidate(todosLosComerciosProvider);
  ref.invalidate(todosLosRepartidoresProvider);
  ref.invalidate(enviosActivosProvider);
  ref.invalidate(preinscripcionesProvider);
}

// ---- El buzón de avisos de Mercado Pago -------------------------------------

final mpNotificacionesRepositoryProvider = Provider((_) => const MpNotificacionesRepository());

/// Los avisos que mandó Mercado Pago, tal como llegaron. Solo los ve la
/// administración (lo decide el RLS de `mp_notificaciones`).
final avisosMercadoPagoProvider = StreamProvider<List<AvisoMercadoPago>>(
  (ref) => ref.watch(mpNotificacionesRepositoryProvider).watch(),
);

// ---- Un cobro que el banco está revisando no se le vuelve a pedir -----------

/// Qué pasó con el cobro de un pedido del cliente: `sin_pago`, `en_revision`,
/// `acreditado`, `rechazado` o `reembolsado`.
///
/// Existe porque el cliente no puede leer `pagos` (RLS) y la pantalla de pago
/// necesita saber que ya hay un cobro hecho esperando al banco: si no, le
/// vuelve a pedir la tarjeta, y ese segundo cobro es plata de verdad (hallazgo
/// A3 de docs/hallazgos-de-la-auditoria-2.md).
///
/// No es un stream porque `pagos` no emite realtime para el cliente. Se
/// refresca con `ref.invalidate` después de intentar pagar; mientras el banco
/// se decide, lo que se mueve solo es el estado del pedido, que sí está en vivo.
final estadoDelPagoProvider = FutureProvider.family<String, String>(
  (ref, pedidoId) => ref.watch(pagosRepositoryProvider).estadoDelPago(pedidoId),
);
