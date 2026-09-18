import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/marketplace.dart';

/// Carteles del inicio del cliente. Los edita la administracion desde el
/// panel; el cliente ve solo los activos, en orden.
class CartelesRepository {
  const CartelesRepository();

  SupabaseClient get _db => Backend.db;

  Future<List<Cartel>> todos() => intentar(() async =>
      (await _db.from('carteles').select().order('orden', ascending: true).order('creado_en', ascending: true))
          .map(Cartel.fromRow)
          .toList());

  Future<List<Cartel>> activos() => intentar(() async => (await _db
          .from('carteles')
          .select()
          .eq('activo', true)
          .order('orden', ascending: true)
          .order('creado_en', ascending: true))
      .map(Cartel.fromRow)
      .toList());

  /// El home del cliente: se actualiza solo cuando la administracion edita.
  Stream<List<Cartel>> watchActivos() => enVivo(canal: 'carteles', tablas: ['carteles'], leer: activos);

  Future<Cartel> crear({String titulo = 'Nuevo cartel', String subtitulo = '', int orden = 0}) =>
      intentar(() async => Cartel.fromRow(await _db
          .from('carteles')
          .insert({'titulo': titulo, 'subtitulo': subtitulo, 'orden': orden})
          .select()
          .single()));

  /// Guarda los campos que cambiaron. Se llama al escribir (con espera), asi
  /// que no vuelve a leer nada: la pantalla ya tiene el texto.
  Future<void> guardar(String id, {String? titulo, String? subtitulo, bool? activo, int? orden}) => intentar(() async {
        final datos = <String, dynamic>{
          'titulo': ?titulo,
          'subtitulo': ?subtitulo,
          'activo': ?activo,
          'orden': ?orden,
        };
        if (datos.isEmpty) return;
        await _db.from('carteles').update(datos).eq('id', id);
      });

  Future<void> borrar(String id) => intentar(() => _db.from('carteles').delete().eq('id', id));
}
