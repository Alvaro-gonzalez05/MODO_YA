import 'dart:async';
import 'dart:math';

import '../models/estados.dart';
import '../models/models.dart';
import 'repositories.dart';

/// Datos de demostracion con calles reales de Malargue.
///
/// Sirven para dos cosas: que las apps se puedan correr y mostrar antes de
/// tener la base conectada, y que los tests de UI tengan un set fijo. Cuando
/// entre `EnviosRepositorySupabase` esto queda solo para tests y para el
/// flavor `demo`.
abstract final class DatosDemo {
  static const centroMalargue = (lat: -35.4756, lng: -69.5847);

  static const comercios = <Comercio>[
    Comercio(
      id: 'com-001',
      nombre: 'Pizzeria Don Luis',
      rubro: 'Pizzeria',
      direccion: Direccion(
        calle: 'Av. Roca 420',
        referencia: 'Frente a la plaza',
        lat: -35.4761,
        lng: -69.5839,
      ),
      telefono: '+54 260 442-1180',
      aprobacion: EstadoAprobacion.aprobado,
      suscripcion: EstadoSuscripcion.activa,
      enviosDelMes: 148,
    ),
    Comercio(
      id: 'com-002',
      nombre: 'Rotiseria La Cumbre',
      rubro: 'Comidas rapidas',
      direccion: Direccion(
        calle: 'Av. San Martin 980',
        lat: -35.4772,
        lng: -69.5861,
      ),
      telefono: '+54 260 442-3390',
      aprobacion: EstadoAprobacion.aprobado,
      suscripcion: EstadoSuscripcion.porVencer,
      enviosDelMes: 92,
    ),
    Comercio(
      id: 'com-003',
      nombre: 'Farmacia del Sur',
      rubro: 'Farmacia',
      direccion: Direccion(
        calle: 'Esquivel Aldao 155',
        lat: -35.4739,
        lng: -69.5822,
      ),
      telefono: '+54 260 442-7714',
      aprobacion: EstadoAprobacion.pendiente,
      suscripcion: EstadoSuscripcion.sinSuscripcion,
    ),
  ];

  static const repartidores = <Repartidor>[
    Repartidor(
      id: 'rep-001',
      nombre: 'Nahuel Quiroga',
      telefono: '+54 260 415-2288',
      vehiculo: Vehiculo.moto,
      aprobacion: EstadoAprobacion.aprobado,
      conectado: true,
      reputacion: 4.9,
      viajesCompletados: 312,
      ubicacion: Direccion(
        calle: 'Rufino Ortega 300',
        lat: -35.4748,
        lng: -69.5833,
      ),
    ),
    Repartidor(
      id: 'rep-002',
      nombre: 'Brenda Aguirre',
      telefono: '+54 260 464-9071',
      vehiculo: Vehiculo.moto,
      aprobacion: EstadoAprobacion.aprobado,
      conectado: true,
      ocupado: true,
      reputacion: 4.8,
      viajesCompletados: 205,
      ubicacion: Direccion(
        calle: 'Av. San Martin 1240',
        lat: -35.4783,
        lng: -69.5869,
      ),
    ),
    Repartidor(
      id: 'rep-003',
      nombre: 'Emiliano Sosa',
      telefono: '+54 260 430-1145',
      vehiculo: Vehiculo.bicicleta,
      aprobacion: EstadoAprobacion.pendiente,
      reputacion: 5.0,
    ),
  ];

  /// El cadete "que soy yo" cuando corro la app de repartidor en demo.
  static const repartidorActual = 'rep-001';

  /// El comercio "que soy yo" cuando corro la app de gestion en demo.
  static const comercioActual = 'com-001';
}

/// Implementacion en memoria de [EnviosRepository].
class EnviosRepositoryDemo implements EnviosRepository {
  EnviosRepositoryDemo({Tarifario? tarifario})
      : _tarifario = tarifario ?? Tarifario.inicial {
    _envios.addAll(_semilla());
    _emitir();
  }

  final Tarifario _tarifario;
  final _envios = <Envio>[];
  final _rnd = Random(7);

  final _controller = StreamController<List<Envio>>.broadcast();
  final _ofertas = StreamController<OfertaServicio?>.broadcast();

  var _contador = 8500;

  List<Envio> _semilla() {
    final ahora = DateTime.now();
    return [
      Envio(
        id: 'env-001',
        codigo: 'MY-8492',
        comercioId: 'com-001',
        comercioNombre: 'Pizzeria Don Luis',
        origen: DatosDemo.comercios[0].direccion,
        destino: const Direccion(
          calle: 'Av. San Martin 450',
          referencia: 'Porton verde, timbre 2',
          lat: -35.4769,
          lng: -69.5852,
        ),
        cliente: const DatosCliente(
          nombre: 'Marcela Diaz',
          telefono: '+54 260 456-1122',
          indicaciones: 'Tocar timbre, no golpear.',
        ),
        cotizacion: _tarifario.cotizar(2.4),
        quienPaga: QuienPaga.cliente,
        estado: EstadoEnvio.enCamino,
        creadoEn: ahora.subtract(const Duration(minutes: 18)),
        repartidorId: 'rep-002',
        repartidorNombre: 'Brenda Aguirre',
        codigoEntrega: '4471',
        retiradoEn: ahora.subtract(const Duration(minutes: 7)),
      ),
      Envio(
        id: 'env-002',
        codigo: 'MY-8495',
        comercioId: 'com-001',
        comercioNombre: 'Pizzeria Don Luis',
        origen: DatosDemo.comercios[0].direccion,
        destino: const Direccion(
          calle: 'Barrio Municipal, Casa 14',
          referencia: 'Manzana C',
          lat: -35.4801,
          lng: -69.5791,
        ),
        cliente: const DatosCliente(
          nombre: 'Julian Paez',
          telefono: '+54 260 471-8890',
        ),
        cotizacion: _tarifario.cotizar(1.8),
        quienPaga: QuienPaga.comercio,
        estado: EstadoEnvio.buscandoRepartidor,
        creadoEn: ahora.subtract(const Duration(minutes: 2)),
      ),
      Envio(
        id: 'env-003',
        codigo: 'MY-8488',
        comercioId: 'com-001',
        comercioNombre: 'Pizzeria Don Luis',
        origen: DatosDemo.comercios[0].direccion,
        destino: const Direccion(
          calle: 'Fortin Malargue 88',
          lat: -35.4722,
          lng: -69.5878,
        ),
        cliente: const DatosCliente(
          nombre: 'Sofia Benitez',
          telefono: '+54 260 488-2001',
        ),
        cotizacion: _tarifario.cotizar(3.1),
        quienPaga: QuienPaga.cliente,
        estado: EstadoEnvio.entregado,
        creadoEn: ahora.subtract(const Duration(hours: 2)),
        repartidorId: 'rep-001',
        repartidorNombre: 'Nahuel Quiroga',
        codigoEntrega: '9013',
        retiradoEn: ahora.subtract(const Duration(minutes: 104)),
        entregadoEn: ahora.subtract(const Duration(minutes: 91)),
      ),
    ];
  }

  void _emitir() => _controller.add(List.unmodifiable(_envios));

  Envio _buscar(String id) =>
      _envios.firstWhere((e) => e.id == id, orElse: () => throw StateError(
            'No existe el envio $id',
          ));

  void _reemplazar(Envio envio) {
    final i = _envios.indexWhere((e) => e.id == envio.id);
    _envios[i] = envio;
    _emitir();
  }

  /// Estado actual seguido de los cambios.
  ///
  /// Sin el `yield` inicial, quien se suscribe despues del constructor no ve
  /// nada hasta la proxima modificacion y la UI se queda cargando para
  /// siempre. Con Supabase esto lo resuelve el propio `stream()` del SDK,
  /// que arranca mandando el snapshot.
  Stream<List<Envio>> _todos() async* {
    yield List.unmodifiable(_envios);
    yield* _controller.stream;
  }

  @override
  Stream<List<Envio>> watchPorComercio(String comercioId) => _todos().map(
        (todos) => todos.where((e) => e.comercioId == comercioId).toList()
          ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn)),
      );

  @override
  Stream<List<Envio>> watchActivos() => _todos().map(
        (todos) => todos.where((e) => e.estado.esActivo).toList(),
      );

  @override
  Stream<Envio?> watchEnCursoDeRepartidor(String repartidorId) => _todos().map(
        (todos) => todos
            .where((e) => e.repartidorId == repartidorId && e.estado.esActivo)
            .firstOrNull,
      );

  @override
  Stream<OfertaServicio?> watchOfertaPara(String repartidorId) async* {
    yield null;
    yield* _ofertas.stream;
  }

  /// Dispara una oferta de prueba hacia el cadete, para poder mostrar la
  /// pantalla B3 sin motor de asignacion todavia.
  void simularOferta({Duration ventana = const Duration(seconds: 30)}) {
    final pendiente = _envios
        .where((e) => e.estado == EstadoEnvio.buscandoRepartidor)
        .firstOrNull;
    if (pendiente == null) return;
    _ofertas.add(
      OfertaServicio(
        envio: pendiente,
        distanciaAlRetiroKm: 0.8,
        expiraEn: DateTime.now().add(ventana),
      ),
    );
  }

  @override
  Future<Envio?> porId(String envioId) async =>
      _envios.where((e) => e.id == envioId).firstOrNull;

  @override
  Future<Envio> crear({
    required String comercioId,
    required Direccion destino,
    required DatosCliente cliente,
    required QuienPaga quienPaga,
    required double distanciaKm,
  }) async {
    final comercio =
        DatosDemo.comercios.firstWhere((c) => c.id == comercioId);
    final envio = Envio(
      id: 'env-${DateTime.now().microsecondsSinceEpoch}',
      codigo: 'MY-${++_contador}',
      comercioId: comercioId,
      comercioNombre: comercio.nombre,
      origen: comercio.direccion,
      destino: destino,
      cliente: cliente,
      cotizacion: _tarifario.cotizar(distanciaKm),
      quienPaga: quienPaga,
      estado: EstadoEnvio.cotizado,
      creadoEn: DateTime.now(),
    );
    _envios.add(envio);
    _emitir();
    return envio;
  }

  @override
  Future<Envio> confirmar(String envioId) =>
      cambiarEstado(envioId, EstadoEnvio.buscandoRepartidor);

  @override
  Future<Envio> aceptar({
    required String envioId,
    required String repartidorId,
  }) async {
    final envio = _buscar(envioId);
    if (!envio.estado.puedePasarA(EstadoEnvio.asignado)) {
      throw TransicionInvalida(envio.estado, EstadoEnvio.asignado);
    }
    final rep =
        DatosDemo.repartidores.firstWhere((r) => r.id == repartidorId);
    final actualizado = envio.copyWith(
      estado: EstadoEnvio.asignado,
      repartidorId: rep.id,
      repartidorNombre: rep.nombre,
      codigoEntrega: (1000 + _rnd.nextInt(9000)).toString(),
    );
    _reemplazar(actualizado);
    _ofertas.add(null);
    return actualizado;
  }

  @override
  Future<Envio> rechazar({
    required String envioId,
    required String repartidorId,
  }) async {
    // Sin motor de asignacion todavia: el rechazo solo cierra la oferta.
    // En produccion esto va a re-ofertar al siguiente cadete mas cercano.
    _ofertas.add(null);
    return _buscar(envioId);
  }

  @override
  Future<Envio> cambiarEstado(String envioId, EstadoEnvio nuevo) async {
    final envio = _buscar(envioId);
    if (!envio.estado.puedePasarA(nuevo)) {
      throw TransicionInvalida(envio.estado, nuevo);
    }
    final actualizado = envio.copyWith(
      estado: nuevo,
      retiradoEn: nuevo == EstadoEnvio.retirado ? DateTime.now() : null,
      entregadoEn: nuevo == EstadoEnvio.entregado ? DateTime.now() : null,
    );
    _reemplazar(actualizado);
    return actualizado;
  }

  @override
  Future<Envio> confirmarEntrega({
    required String envioId,
    required String codigo,
  }) async {
    final envio = _buscar(envioId);
    if (envio.codigoEntrega != codigo) throw const CodigoEntregaInvalido();
    return cambiarEstado(envioId, EstadoEnvio.entregado);
  }

  @override
  Future<Envio> cancelar(String envioId, String motivo) async {
    final envio = _buscar(envioId);
    final actualizado = envio.copyWith(
      estado: EstadoEnvio.cancelado,
      motivoCancelacion: motivo,
    );
    _reemplazar(actualizado);
    return actualizado;
  }

  void dispose() {
    _controller.close();
    _ofertas.close();
  }
}

/// Implementacion en memoria de [ComerciosRepository].
class ComerciosRepositoryDemo implements ComerciosRepository {
  final _comercios = List<Comercio>.from(DatosDemo.comercios);
  final _controller = StreamController<List<Comercio>>.broadcast();

  @override
  Future<Comercio?> porId(String id) async =>
      _comercios.where((c) => c.id == id).firstOrNull;

  @override
  Stream<List<Comercio>> watchTodos() async* {
    yield List.unmodifiable(_comercios);
    yield* _controller.stream;
  }

  @override
  Future<Comercio> actualizarAprobacion(
    String id,
    EstadoAprobacion estado,
  ) async {
    final i = _comercios.indexWhere((c) => c.id == id);
    final c = _comercios[i];
    final actualizado = Comercio(
      id: c.id,
      nombre: c.nombre,
      rubro: c.rubro,
      direccion: c.direccion,
      telefono: c.telefono,
      aprobacion: estado,
      suscripcion: c.suscripcion,
      logoUrl: c.logoUrl,
      enviosDelMes: c.enviosDelMes,
    );
    _comercios[i] = actualizado;
    _controller.add(List.unmodifiable(_comercios));
    return actualizado;
  }
}

/// Implementacion en memoria de [RepartidoresRepository].
class RepartidoresRepositoryDemo implements RepartidoresRepository {
  final _repartidores = List<Repartidor>.from(DatosDemo.repartidores);
  final _controller = StreamController<List<Repartidor>>.broadcast();

  void _emitir() => _controller.add(List.unmodifiable(_repartidores));

  @override
  Future<Repartidor?> porId(String id) async =>
      _repartidores.where((r) => r.id == id).firstOrNull;

  @override
  Stream<List<Repartidor>> watchTodos() async* {
    yield List.unmodifiable(_repartidores);
    yield* _controller.stream;
  }

  @override
  Stream<List<Repartidor>> watchDisponibles() =>
      watchTodos().map((l) => l.where((r) => r.esElegible).toList());

  @override
  Future<Repartidor> setConectado(String id, bool conectado) async {
    final i = _repartidores.indexWhere((r) => r.id == id);
    final actualizado = _repartidores[i].copyWith(conectado: conectado);
    _repartidores[i] = actualizado;
    _emitir();
    return actualizado;
  }

  @override
  Future<Repartidor> actualizarAprobacion(
    String id,
    EstadoAprobacion estado,
  ) async {
    final i = _repartidores.indexWhere((r) => r.id == id);
    final actualizado = _repartidores[i].copyWith(aprobacion: estado);
    _repartidores[i] = actualizado;
    _emitir();
    return actualizado;
  }
}

/// Implementacion en memoria de [TarifasRepository].
class TarifasRepositoryDemo implements TarifasRepository {
  var _tarifario = Tarifario.inicial;
  final _controller = StreamController<Tarifario>.broadcast();

  @override
  Stream<Tarifario> watch() async* {
    yield _tarifario;
    yield* _controller.stream;
  }

  @override
  Future<Tarifario> actualizar(Tarifario tarifario) async {
    _tarifario = tarifario;
    _controller.add(_tarifario);
    return _tarifario;
  }
}
