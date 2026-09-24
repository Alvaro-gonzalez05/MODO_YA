import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';
import 'models/marketplace.dart';
import 'models/models.dart';
import 'repositories/campanias_repository.dart';
import 'repositories/carteles_repository.dart';
import 'repositories/liquidaciones_repository.dart';
import 'repositories/pagos_repository.dart';
import 'repositories/catalogo_repository.dart';
import 'repositories/comercios_repository.dart';
import 'repositories/cuentas_repository.dart';
import 'repositories/envios_repository.dart';
import 'repositories/pedidos_repository.dart';
import 'repositories/promociones_repository.dart';
import 'repositories/repartidores_repository.dart';
import 'repositories/tarifas_repository.dart';
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

/// El envio que el rider tiene en curso, si tiene.
final envioEnCursoProvider = Provider<AsyncValue<Envio?>>((ref) {
  return ref.watch(enviosDelRepartidorProvider).whenData(
        (lista) => lista.where((e) => e.estado.esActivo).firstOrNull,
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

final pedidosPendientesDePagoProvider = StreamProvider<List<Pedido>>(
  (ref) => ref.watch(pedidosRepositoryProvider).watchPendientesDePago(),
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
