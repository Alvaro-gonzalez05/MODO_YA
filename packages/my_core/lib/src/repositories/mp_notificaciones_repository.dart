import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/models.dart';

/// Un aviso de Mercado Pago tal como llego (tabla `mp_notificaciones`, 0044).
///
/// Solo se lee: lo escribe la Edge Function `mp-webhook` con `service_role` y
/// el RLS se lo muestra unicamente a la administracion.
class AvisoMercadoPago {
  const AvisoMercadoPago({
    required this.id,
    required this.recibidoEn,
    required this.cuerpo,
    this.tipo,
    this.accion,
    this.recursoId,
    this.requestId,
    this.firmaValida,
    this.procesada = false,
    this.nota,
  });

  final String id;
  final DateTime recibidoEn;

  /// "payment", "order"…
  final String? tipo;

  /// La accion concreta: "payment.updated", "order.failed"…
  final String? accion;

  /// El id del pago o de la orden en Mercado Pago.
  final String? recursoId;

  /// Lo manda Mercado Pago y es el mismo cuando reintenta.
  final String? requestId;

  /// null = todavia no habia clave del webhook configurada cuando llego.
  final bool? firmaValida;

  /// El cron `procesar-avisos-mp` ya lo resolvio (0068). Lo que hizo queda en
  /// [nota]. En false quiere decir que todavia no le toco el turno, o que no se
  /// pudo resolver y se esta reintentando.
  final bool procesada;
  final String? nota;

  /// El JSON crudo del aviso.
  final Map<String, dynamic> cuerpo;

  /// Lo que dice el aviso del estado del recurso, si viene.
  String? get estado {
    final datos = cuerpo['data'];
    if (datos is Map && datos['status'] != null) return datos['status'].toString();
    return null;
  }

  /// El cuerpo indentado, para leerlo en pantalla.
  String get cuerpoLegible => const JsonEncoder.withIndent('  ').convert(cuerpo);

  factory AvisoMercadoPago.fromRow(Map<String, dynamic> f) => AvisoMercadoPago(
        id: Fila.texto(f, 'id'),
        recibidoEn: Fila.fecha(f, 'recibido_en'),
        tipo: Fila.textoOpcional(f, 'tipo'),
        accion: Fila.textoOpcional(f, 'accion'),
        recursoId: Fila.textoOpcional(f, 'recurso_id'),
        requestId: Fila.textoOpcional(f, 'request_id'),
        firmaValida: f['firma_valida'] as bool?,
        procesada: Fila.booleano(f, 'procesada'),
        nota: Fila.textoOpcional(f, 'nota'),
        cuerpo: f['cuerpo'] is Map
            ? Map<String, dynamic>.from(f['cuerpo'] as Map)
            : const <String, dynamic>{},
      );
}

/// El buzon de avisos de Mercado Pago. Solo lectura.
class MpNotificacionesRepository {
  const MpNotificacionesRepository();

  SupabaseClient get _db => Backend.db;

  /// Los ultimos avisos recibidos, el mas nuevo primero.
  Stream<List<AvisoMercadoPago>> watch({int limite = 100}) => enVivo(
        canal: 'mp-notificaciones',
        tablas: const ['mp_notificaciones'],
        leer: () async => (await _db
                .from('mp_notificaciones')
                .select()
                .order('recibido_en', ascending: false)
                .limit(limite))
            .map(AvisoMercadoPago.fromRow)
            .toList(),
      );
}
