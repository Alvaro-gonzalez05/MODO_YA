import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/marketplace.dart';
import '../models/models.dart';

/// Locales: vidriera, datos del propio local, horarios y aprobacion.
class ComerciosRepository {
  const ComerciosRepository();

  SupabaseClient get _db => Backend.db;

  List<Comercio> _lista(List<Map<String, dynamic>> f) => f.map(Comercio.fromRow).toList();

  /// Todos los locales (administracion).
  Future<List<Comercio>> todos() =>
      intentar(() async => _lista(await _db.from('v_comercios').select().order('nombre', ascending: true)));

  /// Lo que ve el cliente: locales aprobados, abiertos primero.
  Future<List<Comercio>> vidriera({String? rubroId}) => intentar(() async {
        var q = _db.from('v_comercios').select().eq('estado_aprobacion', 'aprobado');
        if (rubroId != null) q = q.eq('rubro_id', rubroId);
        final lista = _lista(await q.order('nombre', ascending: true));
        // Abiertos primero y, entre ellos, los que pagan publicidad.
        lista.sort((a, b) {
          final abierto = (b.abierto ? 1 : 0) - (a.abierto ? 1 : 0);
          if (abierto != 0) return abierto;
          return (b.destacado ? 1 : 0) - (a.destacado ? 1 : 0);
        });
        return lista;
      });

  Future<Comercio?> porId(String id) => intentar(() async {
        final f = await _db.from('v_comercios').select().eq('id', id).maybeSingle();
        return f == null ? null : Comercio.fromRow(f);
      });

  /// Datos de la vidriera que puede editar el propio local. La base solo le da
  /// permiso sobre estas columnas (migracion 0016).
  Future<void> actualizar(
    String comercioId, {
    String? nombre,
    String? telefono,
    String? calle,
    String? referencia,
    Rubro? rubro,
    int? demoraEstimadaMin,
    bool? aceptaPedidos,
  }) =>
      intentar(() async {
        final cambios = <String, dynamic>{
          if (nombre != null) 'nombre': nombre.trim(),
          if (telefono != null) 'telefono': telefono.trim(),
          if (calle != null) 'calle': calle.trim(),
          if (referencia != null) 'referencia': referencia.trim().isEmpty ? null : referencia.trim(),
          if (rubro != null) ...{'rubro_id': rubro.id, 'rubro': rubro.nombre},
          'demora_estimada_min': ?demoraEstimadaMin,
          'acepta_pedidos': ?aceptaPedidos,
        };
        if (cambios.isEmpty) return;
        await _db.from('comercios').update(cambios).eq('id', comercioId);
      });

  Future<void> setUbicacion(double lat, double lng) => intentar(
        () => _db.rpc('set_ubicacion_comercio', params: {'p_lat': lat, 'p_lng': lng}),
      );

  /// Sube el logo (cuadrado) a `catalogo/<comercio_id>/marca.<ext>`.
  ///
  /// No es `logo.<ext>`: ahí quedó la portada de los locales que cargaron una
  /// sola foto antes de que existiera la portada (ver 0025).
  Future<void> subirLogo(String comercioId, Uint8List bytes, {String extension = 'jpg'}) =>
      _subirImagen(comercioId, 'marca', 'logo_url', bytes, extension);

  /// Sube la portada (foto ancha de la tarjeta) a `catalogo/<comercio_id>/portada.<ext>`.
  Future<void> subirPortada(String comercioId, Uint8List bytes, {String extension = 'jpg'}) =>
      _subirImagen(comercioId, 'portada', 'portada_url', bytes, extension);

  Future<void> _subirImagen(String comercioId, String nombre, String columna, Uint8List bytes, String extension) =>
      intentar(() async {
        final ruta = '$comercioId/$nombre.$extension';
        await _db.storage.from('catalogo').uploadBinary(
              ruta,
              bytes,
              fileOptions: FileOptions(upsert: true, contentType: _mime(extension)),
            );
        // El parametro v evita que la app muestre la foto vieja desde cache
        // cuando se reemplaza con el mismo nombre.
        final url = '${_db.storage.from('catalogo').getPublicUrl(ruta)}'
            '?v=${DateTime.now().millisecondsSinceEpoch}';
        await _db.from('comercios').update({columna: url}).eq('id', comercioId);
      });

  Future<List<Horario>> horarios(String comercioId) => intentar(() async {
        final f = await _db
            .from('horarios_comercio')
            .select()
            .eq('comercio_id', comercioId)
            .order('dia', ascending: true)
            .order('abre', ascending: true);
        return f.map(Horario.fromRow).toList();
      });

  Future<void> guardarHorarios(List<Horario> horarios) => intentar(
        () => _db.rpc('guardar_horarios', params: {
          'p_horarios': horarios.map((h) => h.toJson()).toList(),
        }),
      );

  Future<void> cambiarAprobacion(String comercioId, EstadoAprobacion estado, {String? motivo}) =>
      intentar(() => _db.rpc('admin_aprobacion_comercio', params: {
            'p_comercio': comercioId,
            'p_estado': estado.wire,
            'p_motivo': motivo,
          }));

  static String _mime(String ext) => switch (ext.toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
