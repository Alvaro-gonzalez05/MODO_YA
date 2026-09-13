/// Estado de un envio dentro de MODO YA.
///
/// El orden del enum es el orden real del ciclo de vida, asi que `index` sirve
/// para dibujar barras de progreso. Los valores de [wire] son los que van a
/// viajar a Postgres como `text` (o como enum nativo cuando armemos el schema),
/// por eso no dependen del nombre en Dart.
enum EstadoEnvio {
  /// El comercio esta cargando el envio pero todavia no confirmo.
  borrador('borrador', 'Borrador'),

  /// Se calculo distancia y precio; falta que el comercio acepte la cotizacion.
  cotizado('cotizado', 'Cotizado'),

  /// El motor de asignacion esta ofreciendo el envio a los cadetes cercanos.
  buscandoRepartidor('buscando_repartidor', 'Buscando cadete'),

  /// Un cadete acepto y va camino al comercio.
  asignado('asignado', 'Cadete en camino al local'),

  /// El cadete marco que llego al comercio.
  enLocal('en_local', 'Cadete en el local'),

  /// El pedido ya esta en manos del cadete.
  retirado('retirado', 'Retirado'),

  /// El cadete va camino al domicilio del cliente.
  enCamino('en_camino', 'En camino'),

  /// Entrega confirmada con el codigo.
  entregado('entregado', 'Entregado'),

  /// Nadie acepto dentro del tiempo de busqueda configurado.
  sinRepartidor('sin_repartidor', 'Sin cadete disponible'),

  /// Cancelado por el comercio, el cadete o la administracion.
  cancelado('cancelado', 'Cancelado');

  const EstadoEnvio(this.wire, this.label);

  /// Como se guarda en la base de datos.
  final String wire;

  /// Como se muestra al usuario.
  final String label;

  static EstadoEnvio fromWire(String value) => EstadoEnvio.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw ArgumentError('Estado de envio desconocido: $value'),
      );

  /// Estados en los que el envio ya no se mueve mas.
  bool get esFinal =>
      this == entregado || this == cancelado || this == sinRepartidor;

  /// El envio esta en la calle y se puede seguir en el mapa.
  bool get esActivo => !esFinal && this != borrador && this != cotizado;

  /// Transiciones permitidas.
  ///
  /// Esta tabla es la referencia; la regla se va a hacer valer del lado del
  /// servidor con una funcion RPC, para que ninguna de las apps pueda saltear
  /// pasos. Aca vive para validar en la UI antes de mandar.
  static const Map<EstadoEnvio, List<EstadoEnvio>> transiciones = {
    borrador: [cotizado, cancelado],
    cotizado: [buscandoRepartidor, cancelado],
    buscandoRepartidor: [asignado, sinRepartidor, cancelado],
    asignado: [enLocal, cancelado],
    enLocal: [retirado, cancelado],
    retirado: [enCamino, cancelado],
    enCamino: [entregado, cancelado],
    entregado: [],
    sinRepartidor: [buscandoRepartidor, cancelado],
    cancelado: [],
  };

  bool puedePasarA(EstadoEnvio siguiente) =>
      transiciones[this]?.contains(siguiente) ?? false;
}

/// Estado de aprobacion de una cuenta de comercio o de cadete.
///
/// Ni los comercios ni los cadetes pueden operar hasta que la administracion
/// los aprueba (seccion 12 del documento de la clienta).
enum EstadoAprobacion {
  pendiente('pendiente', 'En revision'),
  aprobado('aprobado', 'Aprobado'),
  rechazado('rechazado', 'Rechazado'),
  suspendido('suspendido', 'Suspendido');

  const EstadoAprobacion(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoAprobacion fromWire(String value) =>
      EstadoAprobacion.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw ArgumentError('Estado de aprobacion: $value'),
      );

  bool get puedeOperar => this == aprobado;
}

/// Quien se hace cargo del costo del envio. Lo elige el comercio al crearlo.
enum QuienPaga {
  comercio('comercio', 'Lo paga el comercio'),
  cliente('cliente', 'Lo paga el cliente');

  const QuienPaga(this.wire, this.label);

  final String wire;
  final String label;

  static QuienPaga fromWire(String value) => QuienPaga.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw ArgumentError('Quien paga: $value'),
      );
}

/// Vehiculo del cadete. Define que documentacion se le exige.
enum Vehiculo {
  moto('moto', 'Moto'),
  bicicleta('bicicleta', 'Bicicleta'),
  auto('auto', 'Auto'),
  aPie('a_pie', 'A pie');

  const Vehiculo(this.wire, this.label);

  final String wire;
  final String label;

  static Vehiculo fromWire(String value) => Vehiculo.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw ArgumentError('Vehiculo: $value'),
      );

  /// Documentacion minima exigida por tipo de vehiculo.
  ///
  /// La lista exacta sigue pendiente de definicion con la clienta
  /// (seccion 15 del documento); esto es el supuesto de trabajo.
  List<String> get documentacionRequerida => switch (this) {
        moto => const ['DNI', 'Licencia de conducir', 'Cedula verde', 'Seguro'],
        auto => const ['DNI', 'Licencia de conducir', 'Cedula verde', 'Seguro'],
        bicicleta => const ['DNI'],
        aPie => const ['DNI'],
      };
}

/// Estado de la suscripcion mensual del comercio.
enum EstadoSuscripcion {
  activa('activa', 'Activa'),
  porVencer('por_vencer', 'Por vencer'),
  vencida('vencida', 'Vencida'),
  sinSuscripcion('sin_suscripcion', 'Sin suscripcion');

  const EstadoSuscripcion(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoSuscripcion fromWire(String value) =>
      EstadoSuscripcion.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw ArgumentError('Estado de suscripcion: $value'),
      );

  bool get permiteOperar => this == activa || this == porVencer;
}

/// Rol del usuario autenticado. Va en el JWT y decide que app y que pantallas
/// ve cada uno, y que le deja hacer RLS del lado de la base.
enum RolUsuario {
  comercio('comercio'),
  repartidor('repartidor'),
  admin('admin');

  const RolUsuario(this.wire);

  final String wire;

  static RolUsuario fromWire(String value) => RolUsuario.values.firstWhere(
        (e) => e.wire == value,
        orElse: () => throw ArgumentError('Rol desconocido: $value'),
      );
}
