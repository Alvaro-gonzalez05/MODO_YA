import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/marketplace.dart';
import 'models/models.dart';
import 'repositories/carteles_repository.dart';
import 'repositories/catalogo_repository.dart';
import 'repositories/comercios_repository.dart';
import 'repositories/cuentas_repository.dart';
import 'repositories/envios_repository.dart';
import 'repositories/pedidos_repository.dart';
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

// ---- Comunes ----------------------------------------------------------------

final tarifarioProvider = FutureProvider<Tarifario?>(
  (ref) => ref.watch(tarifasRepositoryProvider).vigente(),
);

final rubrosProvider = FutureProvider<List<Rubro>>(
  (ref) => ref.watch(catalogoRepositoryProvider).rubros(),
);

final comercioPorIdProvider = FutureProvider.family<Comercio?, String>(
  (ref, id) => ref.watch(comerciosRepositoryProvider).porId(id),
);

// ---- Local ------------------------------------------------------------------

/// El local de la sesion. Se invalida despues de editar sus datos.
final comercioActualProvider = FutureProvider<Comercio?>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Future.value(null);
  return ref.watch(comerciosRepositoryProvider).porId(id);
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
final menuDeComercioProvider = FutureProvider.family<Menu, String>(
  (ref, comercioId) => ref.watch(catalogoRepositoryProvider).menu(comercioId),
);

final horariosProvider = FutureProvider.family<List<Horario>, String>(
  (ref, comercioId) => ref.watch(comerciosRepositoryProvider).horarios(comercioId),
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
final cartelesProvider = FutureProvider<List<Cartel>>(
  (ref) => ref.watch(cartelesRepositoryProvider).todos(),
);

/// Vidriera del cliente, opcionalmente filtrada por rubro.
final vidrieraProvider = FutureProvider.family<List<Comercio>, String?>(
  (ref, rubroId) => ref.watch(comerciosRepositoryProvider).vidriera(rubroId: rubroId),
);

/// Menu que ve el cliente: solo lo disponible.
final menuPublicoProvider = FutureProvider.family<Menu, String>(
  (ref, comercioId) => ref.watch(catalogoRepositoryProvider).menu(comercioId, soloDisponibles: true),
);

final direccionesProvider = FutureProvider<List<DireccionCliente>>(
  (ref) => ref.watch(direccionesRepositoryProvider).mias(),
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

final todosLosComerciosProvider = FutureProvider<List<Comercio>>(
  (ref) => ref.watch(comerciosRepositoryProvider).todos(),
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
