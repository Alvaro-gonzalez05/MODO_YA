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
    required this.cargos,
    required this.total,
  });

  final String repartidorId;
  final String rider;
  final int envios;
  final int ganancias;
  final int efectivo;

  /// Positivo: MODO YA le paga. Negativo: el rider tiene que rendir plata.
  /// Lo que se le descuenta además del efectivo: bajadas, faltantes, ajustes.
  final int cargos;
  final int total;

  factory PendienteRider.fromRow(Map<String, dynamic> f) => PendienteRider(
        repartidorId: Fila.texto(f, 'repartidor_id'),
        rider: Fila.texto(f, 'rider'),
        envios: Fila.entero(f, 'envios'),
        ganancias: Fila.entero(f, 'ganancias'),
        efectivo: Fila.entero(f, 'efectivo'),
        cargos: Fila.entero(f, 'cargos'),
        total: Fila.entero(f, 'total'),
      );
}

/// Un envío que entra en la liquidación de un rider.
class RenglonDeRider {
  const RenglonDeRider({
    required this.envioId,
    required this.codigo,
    required this.entregado,
    required this.comercio,
    required this.destino,
    required this.ganancia,
    required this.efectivo,
  });

  final String envioId;
  final String codigo;
  final DateTime entregado;

  /// "Mandado" cuando no hay local de por medio.
  final String comercio;
  final String destino;
  final int ganancia;

  /// Lo que juntó en la puerta y tiene que rendir.
  final int efectivo;

  factory RenglonDeRider.fromRow(Map<String, dynamic> f) => RenglonDeRider(
        envioId: Fila.texto(f, 'envio_id'),
        codigo: Fila.texto(f, 'codigo'),
        entregado: Fila.fecha(f, 'entregado'),
        comercio: Fila.texto(f, 'comercio'),
        destino: Fila.texto(f, 'destino'),
        ganancia: Fila.entero(f, 'ganancia'),
        efectivo: Fila.entero(f, 'efectivo'),
      );
}

/// A qué corresponde un cargo de un rider.
enum ConceptoCargoRider {
  abandono('abandono', 'Se bajó del envío'),
  faltante('faltante', 'Faltante'),
  ajuste('ajuste', 'Ajuste');

  const ConceptoCargoRider(this.wire, this.rotulo);

  final String wire;
  final String rotulo;

  static ConceptoCargoRider fromWire(String? v) =>
      ConceptoCargoRider.values.firstWhere((e) => e.wire == v, orElse: () => ConceptoCargoRider.ajuste);
}

/// Lo que se le descuenta a un rider de lo que cobra. Lo carga la
/// administración: el sistema registra la bajada, pero no decide si se cobra.
class CargoRider {
  const CargoRider({
    required this.id,
    required this.repartidorId,
    required this.concepto,
    required this.detalle,
    required this.monto,
    required this.fecha,
    this.envioId,
    this.liquidado = false,
  });

  final String id;
  final String repartidorId;
  final ConceptoCargoRider concepto;
  final String detalle;

  /// Positivo: se le descuenta. Negativo: se le devuelve.
  final int monto;
  final DateTime fecha;
  final String? envioId;

  /// Ya entró en una liquidación: no se puede borrar.
  final bool liquidado;

  factory CargoRider.fromRow(Map<String, dynamic> f) => CargoRider(
        id: Fila.texto(f, 'id'),
        repartidorId: Fila.texto(f, 'repartidor_id'),
        concepto: ConceptoCargoRider.fromWire(f['concepto'] as String?),
        detalle: Fila.texto(f, 'detalle'),
        monto: Fila.entero(f, 'monto'),
        fecha: Fila.fecha(f, 'fecha'),
        envioId: Fila.textoOpcional(f, 'envio_id'),
        liquidado: f['liquidacion_id'] != null,
      );
}

/// Un rider que se bajó de un envío que ya había aceptado.
class AbandonoDeEnvio {
  const AbandonoDeEnvio({
    required this.id,
    required this.envioId,
    required this.repartidorId,
    required this.rider,
    required this.cuando,
    required this.yaCobrado,
    this.motivo,
    this.envioCodigo,
    this.comercioNombre,
    this.estadoAlBajarse,
  });

  final String id;
  final String envioId;
  final String repartidorId;
  final String rider;
  final DateTime cuando;

  /// Ya se le cargó algo por ese envío: no hay nada que decidir.
  final bool yaCobrado;
  final String? motivo;
  final String? envioCodigo;
  final String? comercioNombre;

  /// En qué estado estaba al bajarse: no es lo mismo plantar al local que
  /// bajarse apenas aceptó.
  final String? estadoAlBajarse;

  factory AbandonoDeEnvio.fromRow(Map<String, dynamic> f) => AbandonoDeEnvio(
        id: Fila.texto(f, 'id'),
        envioId: Fila.texto(f, 'envio_id'),
        repartidorId: Fila.texto(f, 'repartidor_id'),
        rider: Fila.textoOpcional(f, 'rider') ?? 'Rider',
        cuando: Fila.fecha(f, 'creado_en'),
        yaCobrado: Fila.booleano(f, 'ya_cobrado'),
        motivo: Fila.textoOpcional(f, 'motivo'),
        envioCodigo: Fila.textoOpcional(f, 'envio_codigo'),
        comercioNombre: Fila.textoOpcional(f, 'comercio_nombre'),
        estadoAlBajarse: Fila.textoOpcional(f, 'estado_al_bajarse'),
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
        tablas: const ['envios', 'liquidaciones', 'cargos_repartidor'],
        leer: () async {
          final r = await _db.rpc('pendiente_de_liquidar_riders', params: {
            'p_desde': _dia(desde),
            'p_hasta': _dia(hasta),
          });
          return (r as List).map((f) => PendienteRider.fromRow(Map<String, dynamic>.from(f as Map))).toList();
        },
      );

  /// Los envíos que entran en la liquidación de un rider, uno por uno.
  ///
  /// Sale de la base con el mismo filtro que el resumen: si el detalle se
  /// armara por otro lado, un día dirían cosas distintas.
  Future<List<RenglonDeRider>> detalleDeRider(
    String repartidorId,
    DateTime desde,
    DateTime hasta,
  ) =>
      intentar(() async {
        final r = await _db.rpc('detalle_de_liquidar_rider', params: {
          'p_rider': repartidorId,
          'p_desde': _dia(desde),
          'p_hasta': _dia(hasta),
        });
        return (r as List)
            .map((f) => RenglonDeRider.fromRow(Map<String, dynamic>.from(f as Map)))
            .toList();
      });

  /// Cargos de un rider: lo que se le descuenta de lo que cobra.
  Stream<List<CargoRider>> watchCargosRider(String repartidorId) => enVivo(
        canal: 'cargos-rider-$repartidorId',
        tablas: const ['cargos_repartidor'],
        leer: () async => (await _db
                .from('cargos_repartidor')
                .select()
                .eq('repartidor_id', repartidorId)
                .order('fecha', ascending: false))
            .map(CargoRider.fromRow)
            .toList(),
      );

  /// Los riders que se bajaron de un envío. La administración decide si cobra.
  Stream<List<AbandonoDeEnvio>> watchAbandonos({String? repartidorId}) => enVivo(
        canal: 'abandonos-${repartidorId ?? "todos"}',
        tablas: const ['abandonos_envio', 'cargos_repartidor'],
        leer: () async {
          var q = _db.from('v_abandonos').select();
          if (repartidorId != null) q = q.eq('repartidor_id', repartidorId);
          return (await q.order('creado_en', ascending: false).limit(60))
              .map(AbandonoDeEnvio.fromRow)
              .toList();
        },
      );

  /// Le carga algo a un rider. Solo la administración.
  Future<void> cargarARider({
    required String repartidorId,
    required ConceptoCargoRider concepto,
    required String detalle,
    required int monto,
    String? envioId,
  }) =>
      intentar(() => _db.rpc('admin_cargar_a_rider', params: {
            'p_rider': repartidorId,
            'p_concepto': concepto.wire,
            'p_detalle': detalle,
            'p_monto': monto,
            'p_envio': envioId,
          }));

  /// Solo mientras no esté liquidado.
  Future<void> borrarCargoRider(String id) =>
      intentar(() => _db.rpc('admin_borrar_cargo_rider', params: {'p_cargo': id}));

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
