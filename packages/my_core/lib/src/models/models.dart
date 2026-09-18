import '../formato.dart';
import 'estados.dart';

/// Lectores tolerantes de las filas que devuelve PostgREST.
///
/// Los numeric de Postgres llegan como num (a veces String si son muy grandes);
/// los timestamps como String ISO. Centralizarlo evita casts sueltos por todo
/// el codigo.
abstract final class Fila {
  static String texto(Map<String, dynamic> f, String k) => (f[k] ?? '').toString();

  static String? textoOpcional(Map<String, dynamic> f, String k) {
    final v = f[k];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  static int entero(Map<String, dynamic> f, String k, [int defecto = 0]) {
    final v = f[k];
    if (v is num) return v.toInt();
    if (v is String) return num.tryParse(v)?.toInt() ?? defecto;
    return defecto;
  }

  static int? enteroOpcional(Map<String, dynamic> f, String k) =>
      f[k] == null ? null : entero(f, k);

  static double decimal(Map<String, dynamic> f, String k, [double defecto = 0]) {
    final v = f[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? defecto;
    return defecto;
  }

  static double? decimalOpcional(Map<String, dynamic> f, String k) =>
      f[k] == null ? null : decimal(f, k);

  static bool booleano(Map<String, dynamic> f, String k, [bool defecto = false]) {
    final v = f[k];
    return v is bool ? v : defecto;
  }

  static DateTime fecha(Map<String, dynamic> f, String k) =>
      DateTime.parse(f[k] as String).toLocal();

  static DateTime? fechaOpcional(Map<String, dynamic> f, String k) =>
      f[k] == null ? null : DateTime.parse(f[k] as String).toLocal();
}

/// Un punto con su direccion escrita y una referencia libre.
///
/// En Malargue la numeracion no siempre es confiable, asi que la referencia
/// ("porton verde, al lado del kiosco") importa tanto como la calle.
class Direccion {
  const Direccion({required this.calle, this.referencia, this.lat, this.lng});

  final String calle;
  final String? referencia;
  final double? lat;
  final double? lng;

  bool get tieneCoordenadas => lat != null && lng != null;
}

/// Cuadro tarifario vigente. Editable desde administracion (se versiona: cada
/// cambio crea uno nuevo en la base).
class Tarifario {
  const Tarifario({
    required this.gananciaRepartidorBase,
    required this.comisionModoYa,
    required this.kmIncluidos,
    required this.precioKmAdicional,
    required this.radioBusquedaKm,
    required this.segundosParaAceptar,
    this.id,
    this.ciudadId,
    this.precioSuscripcionMensual,
  });

  final String? id;
  final String? ciudadId;
  final int gananciaRepartidorBase;
  final int comisionModoYa;
  final double kmIncluidos;
  final int precioKmAdicional;
  final double radioBusquedaKm;
  final int segundosParaAceptar;
  final int? precioSuscripcionMensual;

  int get precioBase => gananciaRepartidorBase + comisionModoYa;

  factory Tarifario.fromRow(Map<String, dynamic> f) => Tarifario(
        id: Fila.textoOpcional(f, 'id'),
        ciudadId: Fila.textoOpcional(f, 'ciudad_id'),
        gananciaRepartidorBase: Fila.entero(f, 'ganancia_repartidor_base'),
        comisionModoYa: Fila.entero(f, 'comision_modo_ya'),
        kmIncluidos: Fila.decimal(f, 'km_incluidos'),
        precioKmAdicional: Fila.entero(f, 'precio_km_adicional'),
        radioBusquedaKm: Fila.decimal(f, 'radio_busqueda_km'),
        segundosParaAceptar: Fila.entero(f, 'segundos_para_aceptar'),
        precioSuscripcionMensual: Fila.enteroOpcional(f, 'precio_suscripcion_mensual'),
      );

  Tarifario copyWith({
    int? gananciaRepartidorBase,
    int? comisionModoYa,
    double? kmIncluidos,
    int? precioKmAdicional,
    double? radioBusquedaKm,
    int? segundosParaAceptar,
  }) =>
      Tarifario(
        id: id,
        ciudadId: ciudadId,
        gananciaRepartidorBase: gananciaRepartidorBase ?? this.gananciaRepartidorBase,
        comisionModoYa: comisionModoYa ?? this.comisionModoYa,
        kmIncluidos: kmIncluidos ?? this.kmIncluidos,
        precioKmAdicional: precioKmAdicional ?? this.precioKmAdicional,
        radioBusquedaKm: radioBusquedaKm ?? this.radioBusquedaKm,
        segundosParaAceptar: segundosParaAceptar ?? this.segundosParaAceptar,
        precioSuscripcionMensual: precioSuscripcionMensual,
      );
}

/// Cotizacion de un envio. El precio que vale siempre es el del servidor.
class Cotizacion {
  const Cotizacion({
    required this.distanciaKm,
    required this.gananciaRepartidor,
    required this.comision,
    this.kmAdicionales = 0,
    this.totalServidor,
    this.minutosServidor,
  });

  final double distanciaKm;
  final int gananciaRepartidor;
  final int comision;
  final double kmAdicionales;

  /// Lo que devolvio la base. Si no vino, se reconstruye.
  final int? totalServidor;
  final int? minutosServidor;

  int get total => totalServidor ?? gananciaRepartidor + comision;
  int get minutosEstimados => minutosServidor ?? 4 + (distanciaKm / 22 * 60).round();

  factory Cotizacion.fromJson(Map<String, dynamic> f) => Cotizacion(
        distanciaKm: Fila.decimal(f, 'distancia_km'),
        kmAdicionales: Fila.decimal(f, 'km_adicionales'),
        gananciaRepartidor: Fila.entero(f, 'ganancia_repartidor'),
        comision: Fila.entero(f, 'comision'),
        totalServidor: Fila.enteroOpcional(f, 'total'),
        minutosServidor: Fila.enteroOpcional(f, 'minutos_estimados'),
      );
}

/// Un local. Se lee de la vista `v_comercios`.
class Comercio {
  const Comercio({
    required this.id,
    required this.nombre,
    required this.rubro,
    required this.direccion,
    required this.telefono,
    required this.aprobacion,
    this.rubroId,
    this.logoUrl,
    this.portadaUrl,
    this.abierto = false,
    this.aceptaPedidos = true,
    this.demoraEstimadaMin = 25,
  });

  final String id;
  final String nombre;
  final String rubro;
  final String? rubroId;
  final Direccion direccion;
  final String telefono;
  final EstadoAprobacion aprobacion;
  /// La marca, cuadrada: va al lado del nombre.
  final String? logoUrl;

  /// Foto ancha de la tarjeta (comida o el local).
  final String? portadaUrl;

  /// Calculado en la base con los horarios y el interruptor de pausa.
  final bool abierto;
  final bool aceptaPedidos;
  final int demoraEstimadaMin;

  bool get puedePedirEnvios => aprobacion.puedeOperar && direccion.tieneCoordenadas;

  factory Comercio.fromRow(Map<String, dynamic> f) => Comercio(
        id: Fila.texto(f, 'id'),
        nombre: Fila.texto(f, 'nombre'),
        rubro: Fila.textoOpcional(f, 'rubro_nombre') ?? Fila.texto(f, 'rubro'),
        rubroId: Fila.textoOpcional(f, 'rubro_id'),
        direccion: Direccion(
          calle: Fila.texto(f, 'calle'),
          referencia: Fila.textoOpcional(f, 'referencia'),
          lat: Fila.decimalOpcional(f, 'lat'),
          lng: Fila.decimalOpcional(f, 'lng'),
        ),
        telefono: Fila.texto(f, 'telefono'),
        aprobacion: EstadoAprobacion.fromWire(f['estado_aprobacion'] as String?),
        logoUrl: Fila.textoOpcional(f, 'logo_url'),
        portadaUrl: Fila.textoOpcional(f, 'portada_url'),
        abierto: Fila.booleano(f, 'abierto'),
        aceptaPedidos: Fila.booleano(f, 'acepta_pedidos', true),
        demoraEstimadaMin: Fila.entero(f, 'demora_estimada_min', 25),
      );
}

/// Un rider. Se lee de la vista `v_repartidores`.
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
    this.ubicacionEn,
    this.reputacion = 5.0,
    this.viajesCompletados = 0,
    this.fotoUrl,
  });

  final String id;
  final String nombre;
  final String telefono;
  final Vehiculo vehiculo;
  final EstadoAprobacion aprobacion;
  final bool conectado;
  final bool ocupado;
  final Direccion? ubicacion;
  final DateTime? ubicacionEn;
  final double reputacion;
  final int viajesCompletados;
  final String? fotoUrl;

  factory Repartidor.fromRow(Map<String, dynamic> f) {
    final lat = Fila.decimalOpcional(f, 'lat');
    final lng = Fila.decimalOpcional(f, 'lng');
    return Repartidor(
      id: Fila.texto(f, 'id'),
      nombre: Fila.texto(f, 'nombre'),
      telefono: Fila.texto(f, 'telefono'),
      vehiculo: Vehiculo.fromWire(f['vehiculo'] as String?),
      aprobacion: EstadoAprobacion.fromWire(f['estado_aprobacion'] as String?),
      conectado: Fila.booleano(f, 'conectado'),
      ocupado: Fila.booleano(f, 'ocupado'),
      ubicacion: lat == null || lng == null ? null : Direccion(calle: '', lat: lat, lng: lng),
      ubicacionEn: Fila.fechaOpcional(f, 'ultima_ubicacion_en'),
      reputacion: Fila.decimal(f, 'reputacion', 5),
      viajesCompletados: Fila.entero(f, 'viajes_completados'),
      fotoUrl: Fila.textoOpcional(f, 'foto_url'),
    );
  }
}

/// Datos del destinatario. Solo los ve el rider asignado.
class DatosCliente {
  const DatosCliente({required this.nombre, required this.telefono, this.indicaciones});

  final String nombre;
  final String telefono;
  final String? indicaciones;
}

/// Un envio. Se lee de la vista `v_envios`.
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
    this.pedidoId,
    this.repartidorId,
    this.repartidorNombre,
    this.codigoEntrega,
    this.retiradoEn,
    this.entregadoEn,
    this.motivoCancelacion,
    this.cobrarAlEntregar = 0,
    this.cobroMetodo,
  });

  final String id;
  final String codigo;
  final String? pedidoId;
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
  final String? codigoEntrega;
  final DateTime? retiradoEn;
  final DateTime? entregadoEn;
  final String? motivoCancelacion;

  /// Lo que el rider le cobra al cliente en la puerta (efectivo o posnet).
  /// 0 si no tiene que cobrar nada.
  final int cobrarAlEntregar;
  final MetodoPago? cobroMetodo;

  bool get hayQueCobrar => cobrarAlEntregar > 0;

  /// "Cobrar $12.500 en efectivo" / "... con posnet".
  String get textoCobro =>
      'Cobrar ${Formato.pesos(cobrarAlEntregar)} ${cobroMetodo == MetodoPago.tarjeta ? 'con posnet (tarjeta)' : 'en efectivo'}';

  int get total => cotizacion.total;

  factory Envio.fromRow(Map<String, dynamic> f) => Envio(
        id: Fila.texto(f, 'id'),
        codigo: Fila.texto(f, 'codigo'),
        pedidoId: Fila.textoOpcional(f, 'pedido_id'),
        comercioId: Fila.texto(f, 'comercio_id'),
        comercioNombre: Fila.texto(f, 'comercio_nombre'),
        origen: Direccion(
          calle: Fila.texto(f, 'origen_calle'),
          referencia: Fila.textoOpcional(f, 'origen_referencia'),
          lat: Fila.decimalOpcional(f, 'origen_lat'),
          lng: Fila.decimalOpcional(f, 'origen_lng'),
        ),
        destino: Direccion(
          calle: Fila.texto(f, 'destino_calle'),
          referencia: Fila.textoOpcional(f, 'destino_referencia'),
          lat: Fila.decimalOpcional(f, 'destino_lat'),
          lng: Fila.decimalOpcional(f, 'destino_lng'),
        ),
        cliente: DatosCliente(
          nombre: Fila.texto(f, 'cliente_nombre'),
          telefono: Fila.texto(f, 'cliente_telefono'),
          indicaciones: Fila.textoOpcional(f, 'cliente_indicaciones'),
        ),
        cotizacion: Cotizacion(
          distanciaKm: Fila.decimal(f, 'distancia_km'),
          kmAdicionales: Fila.decimal(f, 'km_adicionales'),
          gananciaRepartidor: Fila.entero(f, 'ganancia_repartidor'),
          comision: Fila.entero(f, 'comision'),
          totalServidor: Fila.enteroOpcional(f, 'total'),
          minutosServidor: Fila.enteroOpcional(f, 'minutos_estimados'),
        ),
        quienPaga: QuienPaga.fromWire((f['paga'] as String?) ?? 'comercio'),
        estado: EstadoEnvio.fromWire(f['estado'] as String?),
        creadoEn: Fila.fecha(f, 'creado_en'),
        repartidorId: Fila.textoOpcional(f, 'repartidor_id'),
        repartidorNombre: Fila.textoOpcional(f, 'repartidor_nombre'),
        codigoEntrega: Fila.textoOpcional(f, 'codigo_entrega'),
        retiradoEn: Fila.fechaOpcional(f, 'retirado_en'),
        entregadoEn: Fila.fechaOpcional(f, 'entregado_en'),
        motivoCancelacion: Fila.textoOpcional(f, 'motivo_cancelacion'),
        cobrarAlEntregar: Fila.entero(f, 'cobrar_al_entregar'),
        cobroMetodo: f['cobro_metodo'] == null ? null : MetodoPago.fromWire(f['cobro_metodo'] as String?),
      );
}

/// Oferta de un envio a un rider, con su ventana de tiempo.
///
/// Se lee de `ofertas_abiertas`, que a proposito NO trae los datos del cliente:
/// el rider todavia no acepto.
class OfertaServicio {
  const OfertaServicio({
    required this.id,
    required this.envio,
    required this.distanciaAlRetiroKm,
    required this.expiraEn,
  });

  final String id;
  final Envio envio;
  final double distanciaAlRetiroKm;
  final DateTime expiraEn;

  Duration get restante {
    final r = expiraEn.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  bool get vencida => restante == Duration.zero;

  factory OfertaServicio.fromRow(Map<String, dynamic> f) => OfertaServicio(
        id: Fila.texto(f, 'oferta_id'),
        distanciaAlRetiroKm: Fila.decimal(f, 'distancia_al_retiro_km'),
        expiraEn: Fila.fecha(f, 'expira_en'),
        envio: Envio(
          id: Fila.texto(f, 'envio_id'),
          codigo: Fila.texto(f, 'codigo'),
          comercioId: Fila.texto(f, 'comercio_id'),
          comercioNombre: Fila.texto(f, 'comercio_nombre'),
          origen: Direccion(
            calle: Fila.texto(f, 'origen_calle'),
            referencia: Fila.textoOpcional(f, 'origen_referencia'),
            lat: Fila.decimalOpcional(f, 'origen_lat'),
            lng: Fila.decimalOpcional(f, 'origen_lng'),
          ),
          destino: Direccion(
            calle: Fila.texto(f, 'destino_calle'),
            lat: Fila.decimalOpcional(f, 'destino_lat'),
            lng: Fila.decimalOpcional(f, 'destino_lng'),
          ),
          cliente: const DatosCliente(nombre: '', telefono: ''),
          cotizacion: Cotizacion(
            distanciaKm: Fila.decimal(f, 'distancia_km'),
            gananciaRepartidor: Fila.entero(f, 'ganancia_repartidor'),
            comision: 0,
            minutosServidor: Fila.enteroOpcional(f, 'minutos_estimados'),
          ),
          quienPaga: QuienPaga.cliente,
          estado: EstadoEnvio.fromWire(f['estado'] as String?),
          creadoEn: Fila.fecha(f, 'ofrecida_en'),
          cobrarAlEntregar: Fila.entero(f, 'cobrar_al_entregar'),
          cobroMetodo: f['cobro_metodo'] == null ? null : MetodoPago.fromWire(f['cobro_metodo'] as String?),
        ),
      );
}
