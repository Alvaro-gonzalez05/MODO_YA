import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/models.dart';

/// Lo que hay para liquidarle a un local en un período: lo que vendió menos
/// la mensualidad, la publicidad y los ajustes.
class PendienteComercio {
  const PendienteComercio({
    required this.comercioId,
    required this.comercio,
    required this.pedidos,
    required this.ventas,
    required this.cargos,
    required this.total,
  });

  final String comercioId;
  final String comercio;
  final int pedidos;
  final int ventas;
  final int cargos;

  /// Positivo: MODO YA le paga. Negativo: el local debe.
  final int total;

  factory PendienteComercio.fromRow(Map<String, dynamic> f) => PendienteComercio(
        comercioId: Fila.texto(f, 'comercio_id'),
        comercio: Fila.texto(f, 'comercio'),
        pedidos: Fila.entero(f, 'pedidos'),
        ventas: Fila.entero(f, 'ventas'),
        cargos: Fila.entero(f, 'cargos'),
        total: Fila.entero(f, 'total'),
      );
}

/// Lo que hay para liquidarle a un rider: lo que ganó menos el efectivo que
/// juntó en la calle y todavía no rindió.
class PendienteRider {
  const PendienteRider({
    required this.repartidorId,
    required this.rider,
    required this.envios,
    required this.ganancias,
    required this.efectivo,
    required this.total,
  });

  final String repartidorId;
  final String rider;
  final int envios;
  final int ganancias;
  final int efectivo;

  /// Positivo: MODO YA le paga. Negativo: el rider tiene que rendir plata.
  final int total;

  factory PendienteRider.fromRow(Map<String, dynamic> f) => PendienteRider(
        repartidorId: Fila.texto(f, 'repartidor_id'),
        rider: Fila.texto(f, 'rider'),
        envios: Fila.entero(f, 'envios'),
        ganancias: Fila.entero(f, 'ganancias'),
        efectivo: Fila.entero(f, 'efectivo'),
        total: Fila.entero(f, 'total'),
      );
}

/// Un cargo de un local: la mensualidad del plan, un espacio de publicidad o
/// un ajuste.
class CargoComercio {
  const CargoComercio({
    required this.id,
    required this.comercioId,
    required this.concepto,
    required this.detalle,
    required this.monto,
    required this.fecha,
    this.liquidado = false,
  });

  final String id;
  final String comercioId;

  /// mensualidad, publicidad o ajuste.
  final String concepto;
  final String detalle;
  final int monto;
  final DateTime fecha;
  final bool liquidado;

  factory CargoComercio.fromRow(Map<String, dynamic> f) => CargoComercio(
        id: Fila.texto(f, 'id'),
        comercioId: Fila.texto(f, 'comercio_id'),
        concepto: Fila.texto(f, 'concepto'),
        detalle: Fila.texto(f, 'detalle'),
        monto: Fila.entero(f, 'monto'),
        fecha: Fila.fecha(f, 'fecha'),
        liquidado: f['liquidacion_id'] != null,
      );
}

/// Una liquidación ya cerrada (de un local o de un rider).
class Liquidacion {
  const Liquidacion({
    required this.id,
    required this.nombre,
    required this.desde,
    required this.hasta,
    required this.aFavor,
    required this.enContra,
    required this.total,
    required this.pagada,
    required this.esComercio,
    this.observacion,
  });

  final String id;
  final String nombre;
  final DateTime desde;
  final DateTime hasta;

  /// Ventas (local) o ganancias (rider).
  final int aFavor;

  /// Cargos (local) o efectivo cobrado (rider).
  final int enContra;
  final int total;
  final bool pagada;
  final bool esComercio;
  final String? observacion;

  factory Liquidacion.deComercio(Map<String, dynamic> f) => Liquidacion(
        id: Fila.texto(f, 'id'),
        nombre: Fila.textoOpcional(f, 'comercio_nombre') ?? 'Local',
        desde: Fila.fecha(f, 'periodo_desde'),
        hasta: Fila.fecha(f, 'periodo_hasta'),
        aFavor: Fila.entero(f, 'ventas'),
        enContra: Fila.entero(f, 'cargos'),
        total: Fila.entero(f, 'total'),
        pagada: Fila.texto(f, 'estado') == 'acreditado',
        observacion: Fila.textoOpcional(f, 'observacion'),
        esComercio: true,
      );

  factory Liquidacion.deRider(Map<String, dynamic> f) => Liquidacion(
        id: Fila.texto(f, 'id'),
        nombre: Fila.textoOpcional(f, 'rider_nombre') ?? 'Rider',
        desde: Fila.fecha(f, 'periodo_desde'),
        hasta: Fila.fecha(f, 'periodo_hasta'),
        aFavor: Fila.entero(f, 'ganancias'),
        enContra: Fila.entero(f, 'efectivo_cobrado'),
        total: Fila.entero(f, 'total'),
        pagada: Fila.texto(f, 'estado') == 'acreditado',
        observacion: Fila.textoOpcional(f, 'observacion'),
        esComercio: false,
      );
}

/// Liquidaciones: lo que MODO YA le debe a cada local y a cada rider.
///
/// La plata la cobra MODO YA (tarjeta) o la junta el rider (efectivo); acá se
/// arma el reparto. Todo esto lo usa solo la administración.
class LiquidacionesRepository {
  const LiquidacionesRepository();

  SupabaseClient get _db => Backend.db;

  String _dia(DateTime d) => d.toIso8601String().substring(0, 10);

  Stream<List<PendienteComercio>> watchPendientesComercios(DateTime desde, DateTime hasta) => enVivo(
        canal: 'liq-comercios-${_dia(desde)}-${_dia(hasta)}',
        tablas: const ['pedidos', 'cargos_comercio', 'liquidaciones_comercio'],
        leer: () async {
          final r = await _db.rpc('pendiente_de_liquidar_comercios', params: {
            'p_desde': _dia(desde),
            'p_hasta': _dia(hasta),
          });
          return (r as List).map((f) => PendienteComercio.fromRow(Map<String, dynamic>.from(f as Map))).toList();
        },
      );

  Stream<List<PendienteRider>> watchPendientesRiders(DateTime desde, DateTime hasta) => enVivo(
        canal: 'liq-riders-${_dia(desde)}-${_dia(hasta)}',
        tablas: const ['envios', 'liquidaciones'],
        leer: () async {
          final r = await _db.rpc('pendiente_de_liquidar_riders', params: {
            'p_desde': _dia(desde),
            'p_hasta': _dia(hasta),
          });
          return (r as List).map((f) => PendienteRider.fromRow(Map<String, dynamic>.from(f as Map))).toList();
        },
      );

  /// Cargos de un local (mensualidad, publicidad, ajustes).
  Stream<List<CargoComercio>> watchCargos(String comercioId) => enVivo(
        canal: 'cargos-$comercioId',
        tablas: const ['cargos_comercio'],
        leer: () async => (await _db
                .from('cargos_comercio')
                .select()
                .eq('comercio_id', comercioId)
                .order('fecha', ascending: false))
            .map(CargoComercio.fromRow)
            .toList(),
      );

  Future<void> agregarCargo({
    required String comercioId,
    required String concepto,
    required String detalle,
    required int monto,
    DateTime? fecha,
  }) =>
      intentar(() => _db.from('cargos_comercio').insert({
            'comercio_id': comercioId,
            'concepto': concepto,
            'detalle': detalle,
            'monto': monto,
            if (fecha != null) 'fecha': _dia(fecha),
          }));

  Future<void> borrarCargo(String id) =>
      intentar(() => _db.from('cargos_comercio').delete().eq('id', id));

  Future<void> cerrarComercio(String comercioId, DateTime desde, DateTime hasta, {String? observacion}) =>
      intentar(() => _db.rpc('cerrar_liquidacion_comercio', params: {
            'p_comercio': comercioId,
            'p_desde': _dia(desde),
            'p_hasta': _dia(hasta),
            'p_observacion': observacion,
          }));

  Future<void> cerrarRider(String riderId, DateTime desde, DateTime hasta, {String? observacion}) =>
      intentar(() => _db.rpc('cerrar_liquidacion_rider', params: {
            'p_rider': riderId,
            'p_desde': _dia(desde),
            'p_hasta': _dia(hasta),
            'p_observacion': observacion,
          }));

  Future<void> marcarPagada(Liquidacion l) =>
      intentar(() => _db.rpc('marcar_liquidacion_pagada', params: {
            'p_liquidacion': l.id,
            'p_es_comercio': l.esComercio,
          }));

  /// Historial de liquidaciones cerradas, locales y riders juntos.
  Stream<List<Liquidacion>> watchHistorial() => enVivo(
        canal: 'liquidaciones-historial',
        tablas: const ['liquidaciones_comercio', 'liquidaciones'],
        leer: () async {
          final comercios = await _db
              .from('liquidaciones_comercio')
              .select('*, comercios(nombre)')
              .order('creado_en', ascending: false)
              .limit(50);
          final riders = await _db
              .from('liquidaciones')
              .select('*, repartidores(nombre)')
              .order('creado_en', ascending: false)
              .limit(50);

          final lista = [
            for (final f in comercios)
              Liquidacion.deComercio({...f, 'comercio_nombre': (f['comercios'] as Map?)?['nombre']}),
            for (final f in riders)
              Liquidacion.deRider({...f, 'rider_nombre': (f['repartidores'] as Map?)?['nombre']}),
          ];
          lista.sort((a, b) => b.hasta.compareTo(a.hasta));
          return lista;
        },
      );
}
