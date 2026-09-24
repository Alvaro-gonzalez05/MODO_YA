import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/models.dart';

/// En qué invierte un local: publicidad (aparece destacado) o MODO YA Plus
/// (les regala el envío a los clientes con Plus).
enum TipoCampania {
  publicidad('publicidad', 'Publicidad'),
  plus('plus', 'MODO YA Plus');

  const TipoCampania(this.wire, this.label);

  final String wire;
  final String label;

  static TipoCampania fromWire(String? w) =>
      values.firstWhere((t) => t.wire == w, orElse: () => publicidad);
}

enum EstadoCampania {
  activa('activa', 'Activa'),
  pausada('pausada', 'En pausa'),
  sinFondo('sin_fondo', 'Sin fondo'),
  finalizada('finalizada', 'Finalizada');

  const EstadoCampania(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoCampania fromWire(String? w) =>
      values.firstWhere((e) => e.wire == w, orElse: () => activa);
}

/// Una campaña del local, con lo que lleva gastado y lo que le queda.
class Campania {
  const Campania({
    required this.id,
    required this.comercioId,
    required this.tipo,
    required this.estado,
    required this.presupuesto,
    required this.gastado,
    required this.disponible,
    required this.desde,
    this.presupuestoDiario,
    this.hasta,
  });

  final String id;
  final String comercioId;
  final TipoCampania tipo;
  final EstadoCampania estado;

  /// Tope de la campaña: lo máximo que está dispuesto a gastar.
  final int presupuesto;
  final int gastado;
  final int disponible;

  /// Solo publicidad: cuánto gasta por día.
  final int? presupuestoDiario;
  final DateTime desde;
  final DateTime? hasta;

  bool get enMarcha => estado == EstadoCampania.activa && disponible > 0;

  /// 0 a 1, para la barra de progreso del fondo.
  double get consumido => presupuesto == 0 ? 0 : (gastado / presupuesto).clamp(0, 1);

  factory Campania.fromRow(Map<String, dynamic> f) => Campania(
        id: Fila.texto(f, 'id'),
        comercioId: Fila.texto(f, 'comercio_id'),
        tipo: TipoCampania.fromWire(f['tipo'] as String?),
        estado: EstadoCampania.fromWire(f['estado'] as String?),
        presupuesto: Fila.entero(f, 'presupuesto'),
        gastado: Fila.entero(f, 'gastado'),
        disponible: Fila.entero(f, 'disponible'),
        presupuestoDiario: Fila.enteroOpcional(f, 'presupuesto_diario'),
        desde: Fila.fecha(f, 'desde'),
        hasta: Fila.fechaOpcional(f, 'hasta'),
      );
}

/// Lo que rindió una campaña: lo mismo que muestran las apps grandes.
class RendimientoCampania {
  const RendimientoCampania({
    required this.ingresos,
    required this.pedidos,
    required this.costo,
    required this.retorno,
  });

  /// Lo que vendió en productos.
  final int ingresos;
  final int pedidos;

  /// Lo que gastó la campaña.
  final int costo;

  /// Cuántas veces recuperó lo invertido (ingresos ÷ costo).
  final double retorno;

  /// Para mostrarlo como "7,93x".
  String get retornoTexto => '${retorno.toStringAsFixed(2).replaceAll('.', ',')}x';

  /// Igual que en las apps grandes: un semáforo simple.
  String get calificacion => switch (retorno) {
        >= 5 => 'Excelente',
        >= 3 => 'Muy bueno',
        >= 1.5 => 'Bueno',
        > 0 => 'Bajo',
        _ => 'Sin datos',
      };

  factory RendimientoCampania.fromRow(Map<String, dynamic> f) => RendimientoCampania(
        ingresos: Fila.entero(f, 'ingresos'),
        pedidos: Fila.entero(f, 'pedidos'),
        costo: Fila.entero(f, 'costo'),
        retorno: Fila.decimal(f, 'retorno'),
      );
}

/// Un gasto de la campaña: el día de publicidad o un envío regalado.
class GastoCampania {
  const GastoCampania({required this.fecha, required this.detalle, required this.monto});

  final DateTime fecha;
  final String detalle;
  final int monto;

  factory GastoCampania.fromRow(Map<String, dynamic> f) => GastoCampania(
        fecha: Fila.fecha(f, 'fecha'),
        detalle: Fila.texto(f, 'detalle'),
        monto: Fila.entero(f, 'monto'),
      );
}

/// Campañas del local. El local no paga por adelantado: lo que gasta se le
/// descuenta de sus ventas en la liquidación.
class CampaniasRepository {
  const CampaniasRepository();

  SupabaseClient get _db => Backend.db;

  Stream<List<Campania>> watchDelComercio(String comercioId) => enVivo(
        canal: 'campanias-$comercioId',
        tablas: const ['campanias', 'campania_gastos'],
        leer: () async => (await _db
                .from('v_campanias')
                .select()
                .eq('comercio_id', comercioId)
                .order('creado_en', ascending: false))
            .map(Campania.fromRow)
            .toList(),
      );

  Future<void> crear({
    required String comercioId,
    required TipoCampania tipo,
    required int presupuesto,
    int? presupuestoDiario,
    DateTime? hasta,
  }) =>
      intentar(() => _db.from('campanias').insert({
            'comercio_id': comercioId,
            'tipo': tipo.wire,
            'presupuesto': presupuesto,
            'presupuesto_diario': tipo == TipoCampania.publicidad ? presupuestoDiario : null,
            'hasta': ?hasta?.toIso8601String().substring(0, 10),
          }));

  Future<void> cambiarEstado(String id, EstadoCampania estado) =>
      intentar(() => _db.from('campanias').update({'estado': estado.wire}).eq('id', id));

  /// Sumarle plata al fondo (o bajarle el tope).
  Future<void> cambiarPresupuesto(String id, int presupuesto, {int? diario}) =>
      intentar(() => _db.from('campanias').update({
            'presupuesto': presupuesto,
            'presupuesto_diario': ?diario,
            'estado': EstadoCampania.activa.wire,
          }).eq('id', id));

  Future<RendimientoCampania> rendimiento(String id, {DateTime? desde, DateTime? hasta}) =>
      intentar(() async {
        final r = await _db.rpc('rendimiento_campania', params: {
          'p_campania': id,
          'p_desde': desde?.toIso8601String().substring(0, 10),
          'p_hasta': hasta?.toIso8601String().substring(0, 10),
        });
        final fila = (r as List).firstOrNull;
        if (fila == null) {
          return const RendimientoCampania(ingresos: 0, pedidos: 0, costo: 0, retorno: 0);
        }
        return RendimientoCampania.fromRow(Map<String, dynamic>.from(fila as Map));
      });

  Stream<List<GastoCampania>> watchGastos(String campaniaId) => enVivo(
        canal: 'gastos-$campaniaId',
        tablas: const ['campania_gastos'],
        leer: () async => (await _db
                .from('campania_gastos')
                .select()
                .eq('campania_id', campaniaId)
                .order('fecha', ascending: false)
                .limit(60))
            .map(GastoCampania.fromRow)
            .toList(),
      );
}
