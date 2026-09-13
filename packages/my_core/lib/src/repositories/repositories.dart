import '../models/estados.dart';
import '../models/models.dart';

/// Acceso a los envios.
///
/// Las apps dependen de esta interfaz y nunca de Supabase directamente. Hoy
/// corre [EnviosRepositoryDemo] con datos en memoria; cuando el proyecto de
/// Supabase este conectado se agrega `EnviosRepositorySupabase` y solo cambia
/// el provider que lo construye.
abstract interface class EnviosRepository {
  /// Envios de un comercio, del mas nuevo al mas viejo.
  Stream<List<Envio>> watchPorComercio(String comercioId);

  /// Envios activos en toda la ciudad (mapa y tablero del administrador).
  Stream<List<Envio>> watchActivos();

  /// El envio que el cadete tiene en curso, si tiene alguno.
  Stream<Envio?> watchEnCursoDeRepartidor(String repartidorId);

  /// Ofertas que el motor de asignacion le esta haciendo a este cadete.
  Stream<OfertaServicio?> watchOfertaPara(String repartidorId);

  Future<Envio?> porId(String envioId);

  /// Crea el envio en estado [EstadoEnvio.cotizado].
  Future<Envio> crear({
    required String comercioId,
    required Direccion destino,
    required DatosCliente cliente,
    required QuienPaga quienPaga,
    required double distanciaKm,
  });

  /// Confirma la cotizacion y arranca la busqueda de cadetes.
  Future<Envio> confirmar(String envioId);

  /// El cadete acepta la oferta y queda asignado.
  Future<Envio> aceptar({required String envioId, required String repartidorId});

  Future<Envio> rechazar({
    required String envioId,
    required String repartidorId,
  });

  /// Avanza la maquina de estados. Valida la transicion antes de mandar.
  Future<Envio> cambiarEstado(String envioId, EstadoEnvio nuevo);

  /// Cierra la entrega validando el codigo que dicta el cliente.
  Future<Envio> confirmarEntrega({
    required String envioId,
    required String codigo,
  });

  Future<Envio> cancelar(String envioId, String motivo);
}

/// Acceso a comercios.
abstract interface class ComerciosRepository {
  Future<Comercio?> porId(String id);
  Stream<List<Comercio>> watchTodos();
  Future<Comercio> actualizarAprobacion(String id, EstadoAprobacion estado);
}

/// Acceso a cadetes.
abstract interface class RepartidoresRepository {
  Future<Repartidor?> porId(String id);
  Stream<List<Repartidor>> watchTodos();

  /// Cadetes conectados y libres, para el mapa y el contador del comercio.
  Stream<List<Repartidor>> watchDisponibles();

  Future<Repartidor> setConectado(String id, bool conectado);
  Future<Repartidor> actualizarAprobacion(String id, EstadoAprobacion estado);
}

/// Cuadro tarifario, editable desde administracion.
abstract interface class TarifasRepository {
  Stream<Tarifario> watch();
  Future<Tarifario> actualizar(Tarifario tarifario);
}

/// Error de dominio: se intento una transicion que la maquina de estados
/// no permite.
class TransicionInvalida implements Exception {
  const TransicionInvalida(this.desde, this.hacia);

  final EstadoEnvio desde;
  final EstadoEnvio hacia;

  @override
  String toString() =>
      'No se puede pasar de "${desde.label}" a "${hacia.label}".';
}

/// Error de dominio: el codigo de entrega no coincide.
class CodigoEntregaInvalido implements Exception {
  const CodigoEntregaInvalido();

  @override
  String toString() => 'El codigo de entrega no es correcto.';
}
