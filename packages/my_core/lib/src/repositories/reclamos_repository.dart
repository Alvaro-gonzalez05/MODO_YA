import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/models.dart';

/// Estado de un reclamo.
///
/// `reclamos.estado` es texto con un `check` de cuatro valores (0004:128), no
/// un enum de Postgres: si alguna vez se agrega uno hay que sumarlo acá y en
/// el check, en ese orden.
enum EstadoReclamo {
  abierto('abierto', 'Abierto'),
  enRevision('en_revision', 'En revisión'),
  resuelto('resuelto', 'Resuelto'),
  desestimado('desestimado', 'Desestimado');

  const EstadoReclamo(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoReclamo fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => EstadoReclamo.abierto);

  /// Ya se resolvió o se desestimó: no espera nada de la administración.
  bool get esCerrado => this == resuelto || this == desestimado;

  /// Lo que lee el que lo abrió, que no sabe ni le importa el nombre del estado.
  String get paraElQueReclama => switch (this) {
        abierto => 'Lo recibimos y lo vamos a mirar',
        enRevision => 'Lo estamos viendo',
        resuelto => 'Resuelto',
        desestimado => 'No lo vamos a tomar',
      };
}

/// Motivos sugeridos al abrir un reclamo.
///
/// `reclamos.motivo` es texto libre a propósito (la base no lo acota), así que
/// esto es una ayuda de la pantalla y no una lista cerrada: siempre se puede
/// escribir otro.
abstract final class MotivosDeReclamo {
  static const delCliente = [
    'No me llegó el pedido',
    'Llegó incompleto o equivocado',
    'Llegó en mal estado',
    'Tardó mucho más de lo dicho',
    'Me cobraron un importe que no corresponde',
    'Problema con el rider',
  ];

  static const delLocal = [
    'El rider no vino a buscar el pedido',
    'El rider se fue sin el pedido',
    'El cliente rechazó la entrega',
    'Problema con el cobro de un pedido',
    'Problema con la liquidación',
  ];

  static const delRider = [
    'El local no tenía el pedido listo',
    'El local estaba cerrado',
    'La dirección del cliente estaba mal',
    'El cliente no apareció',
    'Problema con lo que me liquidaron',
  ];
}

/// Un reclamo: lo abre un cliente, un local o un rider sobre un pedido o un
/// envío, y lo resuelve la administración.
class Reclamo {
  const Reclamo({
    required this.id,
    required this.motivo,
    required this.estado,
    required this.rolOrigen,
    required this.creadoEn,
    this.detalle,
    this.pedidoId,
    this.pedidoCodigo,
    this.envioId,
    this.envioCodigo,
    this.abiertoPorNombre,
    this.resolucion,
    this.resueltoEn,
  });

  final String id;
  final String motivo;
  final String? detalle;
  final EstadoReclamo estado;

  /// Con qué rol lo abrió. Lo pone el servidor (`completar_reclamo`), no la app.
  final RolUsuario rolOrigen;
  final DateTime creadoEn;

  final String? pedidoId;
  final String? pedidoCodigo;
  final String? envioId;
  final String? envioCodigo;

  /// Quién lo abrió. La administración lo ve; el resto solo ve el suyo.
  final String? abiertoPorNombre;

  /// Lo que le contestó la administración.
  final String? resolucion;
  final DateTime? resueltoEn;

  /// "el pedido P-123", "el envío MY-45" o nada: para armar una frase.
  String? get sobreQue {
    if (pedidoCodigo != null) return 'el pedido $pedidoCodigo';
    if (envioCodigo != null) return 'el envío $envioCodigo';
    if (pedidoId != null) return 'un pedido';
    if (envioId != null) return 'un envío';
    return null;
  }

  factory Reclamo.fromRow(Map<String, dynamic> f) => Reclamo(
        id: Fila.texto(f, 'id'),
        motivo: Fila.texto(f, 'motivo'),
        detalle: Fila.textoOpcional(f, 'detalle'),
        estado: EstadoReclamo.fromWire(f['estado'] as String?),
        rolOrigen: RolUsuario.fromWire(f['rol_origen'] as String?),
        creadoEn: Fila.fecha(f, 'creado_en'),
        pedidoId: Fila.textoOpcional(f, 'pedido_id'),
        pedidoCodigo: (f['pedidos'] as Map?)?['codigo'] as String?,
        envioId: Fila.textoOpcional(f, 'envio_id'),
        envioCodigo: (f['envios'] as Map?)?['codigo'] as String?,
        abiertoPorNombre: (f['perfiles'] as Map?)?['nombre'] as String?,
        resolucion: Fila.textoOpcional(f, 'resolucion'),
        resueltoEn: Fila.fechaOpcional(f, 'resuelto_en'),
      );
}

class ReclamosRepository {
  const ReclamosRepository();

  SupabaseClient get _db => Backend.db;

  /// `reclamos` tiene dos FK a `perfiles` (quién lo abrió y quién lo resolvió),
  /// así que el embed del nombre tiene que nombrar la que corresponde o
  /// PostgREST no sabe por cuál ir.
  static const _columnas =
      '*, pedidos(codigo), envios(codigo), perfiles!reclamos_abierto_por_fkey(nombre)';

  /// Los reclamos que puede ver el que está usando la app: los propios, o
  /// todos si es la administración. No hay dos consultas porque no hacen
  /// falta: lo decide `reclamos_leer` (0008:165).
  Stream<List<Reclamo>> watch() => enVivo(
        canal: 'reclamos',
        tablas: const ['reclamos'],
        leer: () async => (await _db
                .from('reclamos')
                .select(_columnas)
                .order('creado_en', ascending: false)
                .limit(200))
            .map(Reclamo.fromRow)
            .toList(),
      );

  /// Abre un reclamo. `abierto_por`, `rol_origen` y `estado` los pone el
  /// trigger `completar_reclamo`: la app no los puede escribir ni falsear.
  Future<void> abrir({
    required String motivo,
    String? detalle,
    String? pedidoId,
    String? envioId,
  }) =>
      intentar(() => _db.from('reclamos').insert({
            'motivo': motivo.trim(),
            'detalle': (detalle ?? '').trim().isEmpty ? null : detalle!.trim(),
            'pedido_id': pedidoId,
            'envio_id': envioId,
          }));

  /// La administración lo toma, lo responde, lo desestima o lo vuelve a abrir.
  Future<void> resolver(String id, EstadoReclamo estado, {String? resolucion}) =>
      intentar(() => _db.rpc('admin_resolver_reclamo', params: {
            'p_reclamo': id,
            'p_estado': estado.wire,
            'p_resolucion': (resolucion ?? '').trim().isEmpty ? null : resolucion!.trim(),
          }));
}
