/// Enums del dominio.
///
/// Los valores de `wire` son exactamente los de los enums de Postgres
/// (supabase/migrations). Si cambia uno, cambian los dos.
library;

T _desdeWire<T extends Enum>(List<T> valores, String? wire, String Function(T) de, String nombre) {
  for (final v in valores) {
    if (de(v) == wire) return v;
  }
  throw ArgumentError('$nombre desconocido: $wire');
}

/// Estado de un envio (el tramo con cadete).
enum EstadoEnvio {
  borrador('borrador', 'Borrador'),
  cotizado('cotizado', 'Cotizado'),
  buscandoRepartidor('buscando_repartidor', 'Buscando rider'),
  asignado('asignado', 'Rider en camino al local'),
  enLocal('en_local', 'Rider en el local'),
  retirado('retirado', 'Retirado'),
  enCamino('en_camino', 'En camino'),
  entregado('entregado', 'Entregado'),
  sinRepartidor('sin_repartidor', 'Sin rider disponible'),
  cancelado('cancelado', 'Cancelado');

  const EstadoEnvio(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoEnvio fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Estado de envío');

  bool get esFinal => this == entregado || this == cancelado || this == sinRepartidor;

  /// En la calle: se puede seguir.
  bool get esActivo => !esFinal && this != borrador && this != cotizado;
}

/// Estado de un pedido del marketplace (cliente -> local).
enum EstadoPedido {
  carrito('carrito', 'En carrito'),
  pendientePago('pendiente_pago', 'Esperando pago'),
  pagado('pagado', 'Nuevo'),
  aceptado('aceptado', 'Aceptado'),
  enPreparacion('en_preparacion', 'En preparación'),
  listo('listo', 'Listo para retirar'),
  enCamino('en_camino', 'En camino'),
  entregado('entregado', 'Entregado'),
  rechazado('rechazado', 'Rechazado'),
  cancelado('cancelado', 'Cancelado');

  const EstadoPedido(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoPedido fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Estado de pedido');

  bool get esFinal => this == entregado || this == rechazado || this == cancelado;

  /// Lo que el local tiene que atender ahora.
  bool get esParaElLocal =>
      this == pagado || this == aceptado || this == enPreparacion || this == listo;
}

enum EstadoAprobacion {
  pendiente('pendiente', 'En revisión'),
  aprobado('aprobado', 'Aprobado'),
  rechazado('rechazado', 'Rechazado'),
  suspendido('suspendido', 'Suspendido');

  const EstadoAprobacion(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoAprobacion fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Estado de aprobación');

  bool get puedeOperar => this == aprobado;
}

enum QuienPaga {
  comercio('comercio', 'Lo paga el comercio'),
  cliente('cliente', 'Lo paga el cliente');

  const QuienPaga(this.wire, this.label);

  final String wire;
  final String label;

  static QuienPaga fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Quien paga');
}

enum Vehiculo {
  moto('moto', 'Moto'),
  bicicleta('bicicleta', 'Bicicleta'),
  auto('auto', 'Auto'),
  aPie('a_pie', 'A pie');

  const Vehiculo(this.wire, this.label);

  final String wire;
  final String label;

  static Vehiculo fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Vehículo');
}

enum MetodoPago {
  efectivo('efectivo', 'Efectivo'),
  mercadoPago('mercado_pago', 'Mercado Pago'),
  transferencia('transferencia', 'Transferencia'),
  otro('otro', 'Otro');

  const MetodoPago(this.wire, this.label);

  final String wire;
  final String label;

  static MetodoPago fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Método de pago');
}

enum TipoOpcion {
  /// Se elige una sola (tamano).
  unica('unica', 'Elegí una'),

  /// Se pueden elegir varias (agregados).
  multiple('multiple', 'Elegí las que quieras');

  const TipoOpcion(this.wire, this.label);

  final String wire;
  final String label;

  static TipoOpcion fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Tipo de opción');
}

/// Rol de la cuenta. Decide que app y que pantallas ve cada uno.
enum RolUsuario {
  cliente('cliente'),
  comercio('comercio'),
  repartidor('repartidor'),
  admin('admin');

  const RolUsuario(this.wire);

  final String wire;

  static RolUsuario fromWire(String? v) =>
      _desdeWire(values, v, (e) => e.wire, 'Rol');
}
