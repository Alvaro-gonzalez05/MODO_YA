import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/models.dart';

/// A qué le pega el descuento.
enum AlcancePromocion {
  todo('todo', 'Todo el menú'),
  secciones('secciones', 'Menús elegidos'),
  productos('productos', 'Productos sueltos');

  const AlcancePromocion(this.wire, this.rotulo);

  final String wire;
  final String rotulo;

  static AlcancePromocion fromWire(String? v) =>
      AlcancePromocion.values.firstWhere((e) => e.wire == v, orElse: () => AlcancePromocion.todo);
}

/// Un descuento que arma el local sobre su propio menú.
///
/// El precio con descuento lo calcula la base: acá solo se administra la regla.
class Promocion {
  const Promocion({
    required this.id,
    required this.comercioId,
    required this.nombre,
    required this.porcentaje,
    this.alcance = AlcancePromocion.todo,
    this.dias = const [],
    this.desde,
    this.hasta,
    this.activa = true,
    this.secciones = 0,
    this.productos = 0,
    this.vigente = false,
  });

  final String id;
  final String comercioId;
  final String nombre;
  final int porcentaje;
  final AlcancePromocion alcance;

  /// Vacío = todos los días. 0 = domingo, 6 = sábado.
  final List<int> dias;
  final DateTime? desde;
  final DateTime? hasta;
  final bool activa;

  /// Cuántas secciones o productos abarca (según el alcance).
  final int secciones;
  final int productos;

  /// Si hoy, en este momento, el descuento está rigiendo.
  final bool vigente;

  /// Cómo se explica el alcance en una línea.
  String get detalle => switch (alcance) {
        AlcancePromocion.todo => 'Todo el menú',
        AlcancePromocion.secciones =>
          secciones == 1 ? '1 menú' : '$secciones menús',
        AlcancePromocion.productos =>
          productos == 1 ? '1 producto' : '$productos productos',
      };

  /// "Todos los días" o "Lun, Mar y Mié".
  String get cuando {
    if (dias.isEmpty) return 'Todos los días';
    const cortos = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
    final nombres = ([...dias]..sort()).map((d) => cortos[d]).toList();
    if (nombres.length == 1) return nombres.first;
    return '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
  }

  factory Promocion.fromRow(Map<String, dynamic> f) => Promocion(
        id: Fila.texto(f, 'id'),
        comercioId: Fila.texto(f, 'comercio_id'),
        nombre: Fila.texto(f, 'nombre'),
        porcentaje: Fila.entero(f, 'porcentaje'),
        alcance: AlcancePromocion.fromWire(f['alcance'] as String?),
        dias: ((f['dias'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        desde: Fila.fechaOpcional(f, 'desde'),
        hasta: Fila.fechaOpcional(f, 'hasta'),
        activa: Fila.booleano(f, 'activa', true),
        secciones: Fila.entero(f, 'secciones'),
        productos: Fila.entero(f, 'productos'),
        vigente: Fila.booleano(f, 'vigente'),
      );
}

/// El descuento que hoy tiene un producto.
class PrecioPromocional {
  const PrecioPromocional({
    required this.productoId,
    required this.precio,
    required this.precioLista,
    required this.porcentaje,
    required this.promocion,
  });

  final String productoId;
  final int precio;
  final int precioLista;
  final int porcentaje;
  final String promocion;

  factory PrecioPromocional.fromRow(Map<String, dynamic> f) => PrecioPromocional(
        productoId: Fila.texto(f, 'producto_id'),
        precio: Fila.entero(f, 'precio'),
        precioLista: Fila.entero(f, 'precio_lista'),
        porcentaje: Fila.entero(f, 'porcentaje'),
        promocion: Fila.texto(f, 'promocion'),
      );
}

/// Promociones del local: el descuento lo absorbe el local, no MODO YA.
class PromocionesRepository {
  const PromocionesRepository();

  SupabaseClient get _db => Backend.db;

  /// Las promociones del local, para su panel.
  Stream<List<Promocion>> watchDelComercio(String comercioId) => enVivo(
        canal: 'promos-$comercioId',
        tablas: const ['promociones', 'promocion_secciones', 'promocion_productos'],
        leer: () async => (await _db
                .from('v_promociones')
                .select()
                .eq('comercio_id', comercioId)
                .order('creado_en', ascending: false))
            .map(Promocion.fromRow)
            .toList(),
      );

  /// Los precios con descuento de un local, calculados por la base.
  Future<List<PrecioPromocional>> preciosDe(String comercioId) => intentar(() async =>
      (await _db.rpc('promociones_del_local', params: {'p_comercio': comercioId}) as List)
          .map((e) => PrecioPromocional.fromRow(Map<String, dynamic>.from(e as Map)))
          .toList());

  /// Qué secciones y qué productos abarca una promoción, para poder editarla.
  Future<({List<String> secciones, List<String> productos})> alcanceDe(String id) =>
      intentar(() async {
        final s = await _db.from('promocion_secciones').select('seccion_id').eq('promocion_id', id);
        final p = await _db.from('promocion_productos').select('producto_id').eq('promocion_id', id);
        return (
          secciones: s.map((f) => f['seccion_id'] as String).toList(),
          productos: p.map((f) => f['producto_id'] as String).toList(),
        );
      });

  /// Crea o actualiza una promoción con su alcance.
  ///
  /// El alcance se reemplaza entero en cada guardado: es una lista corta y así
  /// no quedan secciones sueltas de una versión anterior.
  Future<String> guardar({
    required String comercioId,
    required String nombre,
    required int porcentaje,
    String? id,
    AlcancePromocion alcance = AlcancePromocion.todo,
    List<int> dias = const [],
    DateTime? desde,
    DateTime? hasta,
    bool activa = true,
    List<String> secciones = const [],
    List<String> productos = const [],
  }) =>
      intentar(() async {
        final datos = {
          'comercio_id': comercioId,
          'nombre': nombre.trim(),
          'porcentaje': porcentaje,
          'alcance': alcance.wire,
          'dias': dias,
          if (desde != null) 'desde': _dia(desde),
          'hasta': hasta == null ? null : _dia(hasta),
          'activa': activa,
        };

        final String promoId;
        if (id == null) {
          final f = await _db.from('promociones').insert(datos).select('id').single();
          promoId = f['id'] as String;
        } else {
          await _db.from('promociones').update(datos).eq('id', id);
          promoId = id;
        }

        await _db.from('promocion_secciones').delete().eq('promocion_id', promoId);
        await _db.from('promocion_productos').delete().eq('promocion_id', promoId);

        if (alcance == AlcancePromocion.secciones && secciones.isNotEmpty) {
          await _db.from('promocion_secciones').insert([
            for (final s in secciones) {'promocion_id': promoId, 'seccion_id': s},
          ]);
        }
        if (alcance == AlcancePromocion.productos && productos.isNotEmpty) {
          await _db.from('promocion_productos').insert([
            for (final p in productos) {'promocion_id': promoId, 'producto_id': p},
          ]);
        }

        return promoId;
      });

  Future<void> pausar(String id, {required bool activa}) =>
      intentar(() => _db.from('promociones').update({'activa': activa}).eq('id', id));

  Future<void> borrar(String id) =>
      intentar(() => _db.from('promociones').delete().eq('id', id));

  static String _dia(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
