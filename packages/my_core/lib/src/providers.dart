import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/estados.dart';
import 'models/models.dart';
import 'repositories/demo_repositories.dart';
import 'repositories/repositories.dart';

/// Identidad del usuario logueado.
///
/// Hoy se resuelve con los datos demo. Cuando entre Supabase Auth, este
/// provider va a leer el JWT (el rol viaja en `app_metadata` gracias al
/// Custom Access Token Hook) y el resto de la app no se entera del cambio.
class Sesion {
  const Sesion({
    required this.rol,
    required this.usuarioId,
    this.comercioId,
    this.repartidorId,
    this.nombre = '',
  });

  final RolUsuario rol;
  final String usuarioId;
  final String? comercioId;
  final String? repartidorId;
  final String nombre;

  static const demoComercio = Sesion(
    rol: RolUsuario.comercio,
    usuarioId: 'usr-com-001',
    comercioId: DatosDemo.comercioActual,
    nombre: 'Pizzeria Don Luis',
  );

  static const demoRepartidor = Sesion(
    rol: RolUsuario.repartidor,
    usuarioId: 'usr-rep-001',
    repartidorId: DatosDemo.repartidorActual,
    nombre: 'Nahuel Quiroga',
  );

  static const demoAdmin = Sesion(
    rol: RolUsuario.admin,
    usuarioId: 'usr-adm-001',
    nombre: 'Administracion MODO YA',
  );
}

/// La sesion activa. Cada app la sobrescribe en su `ProviderScope`.
final sesionProvider = Provider<Sesion>(
  (ref) => throw UnimplementedError(
    'Sobrescribi sesionProvider en el ProviderScope de la app.',
  ),
);

// --- Repositorios ---------------------------------------------------------
// Las apps consumen siempre estas interfaces. Para pasar a Supabase alcanza
// con sobrescribir estos providers con la implementacion real.

final enviosRepositoryProvider = Provider<EnviosRepository>((ref) {
  final repo = EnviosRepositoryDemo();
  ref.onDispose(repo.dispose);
  return repo;
});

final comerciosRepositoryProvider =
    Provider<ComerciosRepository>((ref) => ComerciosRepositoryDemo());

final repartidoresRepositoryProvider =
    Provider<RepartidoresRepository>((ref) => RepartidoresRepositoryDemo());

final tarifasRepositoryProvider =
    Provider<TarifasRepository>((ref) => TarifasRepositoryDemo());

// --- Datos derivados ------------------------------------------------------

/// Cuadro tarifario vigente.
final tarifarioProvider = StreamProvider<Tarifario>(
  (ref) => ref.watch(tarifasRepositoryProvider).watch(),
);

/// Envios del comercio de la sesion actual.
final enviosDelComercioProvider = StreamProvider<List<Envio>>((ref) {
  final sesion = ref.watch(sesionProvider);
  final comercioId = sesion.comercioId;
  if (comercioId == null) return const Stream.empty();
  return ref.watch(enviosRepositoryProvider).watchPorComercio(comercioId);
});

/// Envios del comercio que todavia estan en la calle.
final enviosActivosDelComercioProvider = Provider<List<Envio>>((ref) {
  return ref.watch(enviosDelComercioProvider).maybeWhen(
        data: (envios) => envios.where((e) => e.estado.esActivo).toList(),
        orElse: () => const [],
      );
});

/// Todos los envios activos de la ciudad (mapa y tablero del admin).
final enviosActivosProvider = StreamProvider<List<Envio>>(
  (ref) => ref.watch(enviosRepositoryProvider).watchActivos(),
);

/// Cadetes conectados y libres.
final repartidoresDisponiblesProvider = StreamProvider<List<Repartidor>>(
  (ref) => ref.watch(repartidoresRepositoryProvider).watchDisponibles(),
);

final todosLosRepartidoresProvider = StreamProvider<List<Repartidor>>(
  (ref) => ref.watch(repartidoresRepositoryProvider).watchTodos(),
);

final todosLosComerciosProvider = StreamProvider<List<Comercio>>(
  (ref) => ref.watch(comerciosRepositoryProvider).watchTodos(),
);

/// El comercio de la sesion actual.
final comercioActualProvider = FutureProvider<Comercio?>((ref) {
  final id = ref.watch(sesionProvider).comercioId;
  if (id == null) return Future.value(null);
  return ref.watch(comerciosRepositoryProvider).porId(id);
});

/// El cadete de la sesion actual.
final repartidorActualProvider = FutureProvider<Repartidor?>((ref) {
  final id = ref.watch(sesionProvider).repartidorId;
  if (id == null) return Future.value(null);
  return ref.watch(repartidoresRepositoryProvider).porId(id);
});

/// El envio que el cadete tiene en curso.
final envioEnCursoProvider = StreamProvider<Envio?>((ref) {
  final id = ref.watch(sesionProvider).repartidorId;
  if (id == null) return const Stream.empty();
  return ref.watch(enviosRepositoryProvider).watchEnCursoDeRepartidor(id);
});

/// La oferta que el motor de asignacion le esta haciendo al cadete.
final ofertaActualProvider = StreamProvider<OfertaServicio?>((ref) {
  final id = ref.watch(sesionProvider).repartidorId;
  if (id == null) return const Stream.empty();
  return ref.watch(enviosRepositoryProvider).watchOfertaPara(id);
});
