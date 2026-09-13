import 'estados.dart';

/// Un punto en el mapa con su direccion escrita y una referencia libre.
///
/// En Malargue la numeracion no siempre es confiable, asi que la referencia
/// ("porton verde, al lado del kiosco") es tan importante como la calle.
class Direccion {
  const Direccion({
    required this.calle,
    this.referencia,
    this.lat,
    this.lng,
  });

  final String calle;
  final String? referencia;
  final double? lat;
  final double? lng;

  bool get tieneCoordenadas => lat != null && lng != null;

  factory Direccion.fromJson(Map<String, dynamic> json) => Direccion(
        calle: json['calle'] as String,
        referencia: json['referencia'] as String?,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'calle': calle,
        if (referencia != null) 'referencia': referencia,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
      };

  Direccion copyWith({
    String? calle,
    String? referencia,
    double? lat,
    double? lng,
  }) =>
      Direccion(
        calle: calle ?? this.calle,
        referencia: referencia ?? this.referencia,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
      );
}

/// Cuadro tarifario vigente.
///
/// Todos los importes son configurables desde administracion: la clienta pidio
/// explicitamente poder actualizarlos sin publicar una version nueva de la app
/// (seccion 4 del documento).
class Tarifario {
  const Tarifario({
    required this.gananciaRepartidorBase,
    required this.comisionModoYa,
    required this.kmIncluidos,
    required this.precioKmAdicional,
    required this.radioBusquedaKm,
    required this.segundosParaAceptar,
  });

  /// Lo que cobra el cadete por un viaje dentro de [kmIncluidos].
  final int gananciaRepartidorBase;

  /// Lo que se queda MODO YA por servicio.
  final int comisionModoYa;

  /// Kilometros cubiertos por la tarifa base.
  final double kmIncluidos;

  /// Precio de cada kilometro que exceda [kmIncluidos].
  ///
  /// Pendiente de definir con la clienta; arranca en 0 para no inventar plata.
  final int precioKmAdicional;

  /// Radio inicial de busqueda de cadetes.
  final double radioBusquedaKm;

  /// Tiempo que tiene cada cadete para aceptar antes de pasar al siguiente.
  final int segundosParaAceptar;

  /// Valores iniciales de la etapa de prueba, tal cual el documento MVP:
  /// $3.000 para el cadete + $500 de comision = $3.500 hasta 2 km.
  static const inicial = Tarifario(
    gananciaRepartidorBase: 3000,
    comisionModoYa: 500,
    kmIncluidos: 2,
    precioKmAdicional: 0,
    radioBusquedaKm: 3,
    segundosParaAceptar: 30,
  );

  int get precioBase => gananciaRepartidorBase + comisionModoYa;

  /// Cotiza un envio de [km] kilometros.
  ///
  /// El calculo definitivo tiene que correr en el servidor (una funcion SQL con
  /// PostGIS): aca esta para previsualizar en la app antes de confirmar, pero
  /// el precio que vale es el que devuelve la base.
  Cotizacion cotizar(double km) {
    final excedente = km <= kmIncluidos ? 0.0 : km - kmIncluidos;
    final adicional = (excedente * precioKmAdicional).round();
    return Cotizacion(
      distanciaKm: km,
      gananciaRepartidor: gananciaRepartidorBase + adicional,
      comision: comisionModoYa,
      kmAdicionales: excedente,
    );
  }

  factory Tarifario.fromJson(Map<String, dynamic> json) => Tarifario(
        gananciaRepartidorBase: json['ganancia_repartidor_base'] as int,
        comisionModoYa: json['comision_modo_ya'] as int,
        kmIncluidos: (json['km_incluidos'] as num).toDouble(),
        precioKmAdicional: json['precio_km_adicional'] as int,
        radioBusquedaKm: (json['radio_busqueda_km'] as num).toDouble(),
        segundosParaAceptar: json['segundos_para_aceptar'] as int,
      );

  Map<String, dynamic> toJson() => {
        'ganancia_repartidor_base': gananciaRepartidorBase,
        'comision_modo_ya': comisionModoYa,
        'km_incluidos': kmIncluidos,
        'precio_km_adicional': precioKmAdicional,
        'radio_busqueda_km': radioBusquedaKm,
        'segundos_para_aceptar': segundosParaAceptar,
      };

  Tarifario copyWith({
    int? gananciaRepartidorBase,
    int? comisionModoYa,
    double? kmIncluidos,
    int? precioKmAdicional,
    double? radioBusquedaKm,
    int? segundosParaAceptar,
  }) =>
      Tarifario(
        gananciaRepartidorBase:
            gananciaRepartidorBase ?? this.gananciaRepartidorBase,
        comisionModoYa: comisionModoYa ?? this.comisionModoYa,
        kmIncluidos: kmIncluidos ?? this.kmIncluidos,
        precioKmAdicional: precioKmAdicional ?? this.precioKmAdicional,
        radioBusquedaKm: radioBusquedaKm ?? this.radioBusquedaKm,
        segundosParaAceptar: segundosParaAceptar ?? this.segundosParaAceptar,
      );
}

/// Resultado de cotizar un envio: cuanto sale y como se reparte.
class Cotizacion {
  const Cotizacion({
    required this.distanciaKm,
    required this.gananciaRepartidor,
    required this.comision,
    required this.kmAdicionales,
  });

  final double distanciaKm;
  final int gananciaRepartidor;
  final int comision;
  final double kmAdicionales;

  int get total => gananciaRepartidor + comision;

  /// Estimacion de minutos de viaje. Provisoria: asume 22 km/h promedio en
  /// zona urbana mas 4 minutos fijos de retiro. Cuando tengamos PostGIS y
  /// datos reales del piloto, esto se reemplaza por el calculo del servidor.
  int get minutosEstimados => 4 + (distanciaKm / 22 * 60).round();
}

/// Un comercio adherido.
class Comercio {
  const Comercio({
    required this.id,
    required this.nombre,
    required this.rubro,
    required this.direccion,
    required this.telefono,
    required this.aprobacion,
    required this.suscripcion,
    this.logoUrl,
    this.enviosDelMes = 0,
  });

  final String id;
  final String nombre;
  final String rubro;
  final Direccion direccion;
  final String telefono;
  final EstadoAprobacion aprobacion;
  final EstadoSuscripcion suscripcion;
  final String? logoUrl;
  final int enviosDelMes;

  /// Solo un comercio aprobado y al dia puede pedir cadetes.
  bool get puedePedirEnvios =>
      aprobacion.puedeOperar && suscripcion.permiteOperar;

  factory Comercio.fromJson(Map<String, dynamic> json) => Comercio(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        rubro: json['rubro'] as String,
        direccion: Direccion.fromJson(
          Map<String, dynamic>.from(json['direccion'] as Map),
        ),
        telefono: json['telefono'] as String,
        aprobacion: EstadoAprobacion.fromWire(json['aprobacion'] as String),
        suscripcion: EstadoSuscripcion.fromWire(json['suscripcion'] as String),
        logoUrl: json['logo_url'] as String?,
        enviosDelMes: json['envios_del_mes'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'rubro': rubro,
        'direccion': direccion.toJson(),
        'telefono': telefono,
        'aprobacion': aprobacion.wire,
        'suscripcion': suscripcion.wire,
        if (logoUrl != null) 'logo_url': logoUrl,
        'envios_del_mes': enviosDelMes,
      };
}

/// Un cadete.
class Repartidor {
  const Repartidor({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.vehiculo,
    required this.aprobacion,
    this.conectado = false,
    this.ocupado = false,
    this.ubicacion,
    this.reputacion = 5.0,
    this.viajesCompletados = 0,
    this.fotoUrl,
  });

  final String id;
  final String nombre;
  final String telefono;
  final Vehiculo vehiculo;
  final EstadoAprobacion aprobacion;

  /// El cadete apreto "Conectarme" y comparte ubicacion.
  final bool conectado;

  /// Ya tiene un envio en curso: el motor de asignacion no debe ofrecerle otro.
  final bool ocupado;

  final Direccion? ubicacion;
  final double reputacion;
  final int viajesCompletados;
  final String? fotoUrl;

  /// Condiciones para que el motor le ofrezca un envio.
  bool get esElegible => aprobacion.puedeOperar && conectado && !ocupado;

  factory Repartidor.fromJson(Map<String, dynamic> json) => Repartidor(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        telefono: json['telefono'] as String,
        vehiculo: Vehiculo.fromWire(json['vehiculo'] as String),
        aprobacion: EstadoAprobacion.fromWire(json['aprobacion'] as String),
        conectado: json['conectado'] as bool? ?? false,
        ocupado: json['ocupado'] as bool? ?? false,
        ubicacion: json['ubicacion'] == null
            ? null
            : Direccion.fromJson(
                Map<String, dynamic>.from(json['ubicacion'] as Map),
              ),
        reputacion: (json['reputacion'] as num?)?.toDouble() ?? 5.0,
        viajesCompletados: json['viajes_completados'] as int? ?? 0,
        fotoUrl: json['foto_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'telefono': telefono,
        'vehiculo': vehiculo.wire,
        'aprobacion': aprobacion.wire,
        'conectado': conectado,
        'ocupado': ocupado,
        if (ubicacion != null) 'ubicacion': ubicacion!.toJson(),
        'reputacion': reputacion,
        'viajes_completados': viajesCompletados,
        if (fotoUrl != null) 'foto_url': fotoUrl,
      };

  Repartidor copyWith({
    bool? conectado,
    bool? ocupado,
    Direccion? ubicacion,
    EstadoAprobacion? aprobacion,
  }) =>
      Repartidor(
        id: id,
        nombre: nombre,
        telefono: telefono,
        vehiculo: vehiculo,
        aprobacion: aprobacion ?? this.aprobacion,
        conectado: conectado ?? this.conectado,
        ocupado: ocupado ?? this.ocupado,
        ubicacion: ubicacion ?? this.ubicacion,
        reputacion: reputacion,
        viajesCompletados: viajesCompletados,
        fotoUrl: fotoUrl,
      );
}

/// Datos del destinatario. Solo se muestran completos al cadete asignado.
class DatosCliente {
  const DatosCliente({
    required this.nombre,
    required this.telefono,
    this.indicaciones,
  });

  final String nombre;
  final String telefono;
  final String? indicaciones;

  factory DatosCliente.fromJson(Map<String, dynamic> json) => DatosCliente(
        nombre: json['nombre'] as String,
        telefono: json['telefono'] as String,
        indicaciones: json['indicaciones'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'telefono': telefono,
        if (indicaciones != null) 'indicaciones': indicaciones,
      };
}

/// Un envio: la entidad central del producto.
class Envio {
  const Envio({
    required this.id,
    required this.codigo,
    required this.comercioId,
    required this.comercioNombre,
    required this.origen,
    required this.destino,
    required this.cliente,
    required this.cotizacion,
    required this.quienPaga,
    required this.estado,
    required this.creadoEn,
    this.repartidorId,
    this.repartidorNombre,
    this.codigoEntrega,
    this.retiradoEn,
    this.entregadoEn,
    this.motivoCancelacion,
  });

  final String id;

  /// Codigo corto y legible que se muestra en pantalla: `MY-8492`.
  final String codigo;

  final String comercioId;
  final String comercioNombre;
  final Direccion origen;
  final Direccion destino;
  final DatosCliente cliente;
  final Cotizacion cotizacion;
  final QuienPaga quienPaga;
  final EstadoEnvio estado;
  final DateTime creadoEn;

  final String? repartidorId;
  final String? repartidorNombre;

  /// Codigo de 4 digitos que el cliente le dicta al cadete para cerrar la
  /// entrega. Es el mecanismo verificable que pide el documento.
  final String? codigoEntrega;

  final DateTime? retiradoEn;
  final DateTime? entregadoEn;
  final String? motivoCancelacion;

  int get total => cotizacion.total;

  /// Cuanto tiempo lleva abierto el envio.
  Duration get antiguedad => DateTime.now().difference(creadoEn);

  factory Envio.fromJson(Map<String, dynamic> json) => Envio(
        id: json['id'] as String,
        codigo: json['codigo'] as String,
        comercioId: json['comercio_id'] as String,
        comercioNombre: json['comercio_nombre'] as String,
        origen: Direccion.fromJson(
          Map<String, dynamic>.from(json['origen'] as Map),
        ),
        destino: Direccion.fromJson(
          Map<String, dynamic>.from(json['destino'] as Map),
        ),
        cliente: DatosCliente.fromJson(
          Map<String, dynamic>.from(json['cliente'] as Map),
        ),
        cotizacion: Cotizacion(
          distanciaKm: (json['distancia_km'] as num).toDouble(),
          gananciaRepartidor: json['ganancia_repartidor'] as int,
          comision: json['comision'] as int,
          kmAdicionales: (json['km_adicionales'] as num?)?.toDouble() ?? 0,
        ),
        quienPaga: QuienPaga.fromWire(json['quien_paga'] as String),
        estado: EstadoEnvio.fromWire(json['estado'] as String),
        creadoEn: DateTime.parse(json['creado_en'] as String),
        repartidorId: json['repartidor_id'] as String?,
        repartidorNombre: json['repartidor_nombre'] as String?,
        codigoEntrega: json['codigo_entrega'] as String?,
        retiradoEn: json['retirado_en'] == null
            ? null
            : DateTime.parse(json['retirado_en'] as String),
        entregadoEn: json['entregado_en'] == null
            ? null
            : DateTime.parse(json['entregado_en'] as String),
        motivoCancelacion: json['motivo_cancelacion'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'codigo': codigo,
        'comercio_id': comercioId,
        'comercio_nombre': comercioNombre,
        'origen': origen.toJson(),
        'destino': destino.toJson(),
        'cliente': cliente.toJson(),
        'distancia_km': cotizacion.distanciaKm,
        'ganancia_repartidor': cotizacion.gananciaRepartidor,
        'comision': cotizacion.comision,
        'km_adicionales': cotizacion.kmAdicionales,
        'quien_paga': quienPaga.wire,
        'estado': estado.wire,
        'creado_en': creadoEn.toIso8601String(),
        if (repartidorId != null) 'repartidor_id': repartidorId,
        if (repartidorNombre != null) 'repartidor_nombre': repartidorNombre,
        if (codigoEntrega != null) 'codigo_entrega': codigoEntrega,
        if (retiradoEn != null) 'retirado_en': retiradoEn!.toIso8601String(),
        if (entregadoEn != null) 'entregado_en': entregadoEn!.toIso8601String(),
        if (motivoCancelacion != null) 'motivo_cancelacion': motivoCancelacion,
      };

  Envio copyWith({
    EstadoEnvio? estado,
    String? repartidorId,
    String? repartidorNombre,
    String? codigoEntrega,
    DateTime? retiradoEn,
    DateTime? entregadoEn,
    String? motivoCancelacion,
  }) =>
      Envio(
        id: id,
        codigo: codigo,
        comercioId: comercioId,
        comercioNombre: comercioNombre,
        origen: origen,
        destino: destino,
        cliente: cliente,
        cotizacion: cotizacion,
        quienPaga: quienPaga,
        estado: estado ?? this.estado,
        creadoEn: creadoEn,
        repartidorId: repartidorId ?? this.repartidorId,
        repartidorNombre: repartidorNombre ?? this.repartidorNombre,
        codigoEntrega: codigoEntrega ?? this.codigoEntrega,
        retiradoEn: retiradoEn ?? this.retiradoEn,
        entregadoEn: entregadoEn ?? this.entregadoEn,
        motivoCancelacion: motivoCancelacion ?? this.motivoCancelacion,
      );
}

/// Oferta de un envio a un cadete concreto, con su ventana de tiempo.
class OfertaServicio {
  const OfertaServicio({
    required this.envio,
    required this.distanciaAlRetiroKm,
    required this.expiraEn,
  });

  final Envio envio;

  /// A cuanto esta el cadete del punto de retiro.
  final double distanciaAlRetiroKm;

  final DateTime expiraEn;

  Duration get restante {
    final r = expiraEn.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  bool get vencida => restante == Duration.zero;
}
