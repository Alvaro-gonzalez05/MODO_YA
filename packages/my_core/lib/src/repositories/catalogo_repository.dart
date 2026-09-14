import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/marketplace.dart';

/// Rubros y menu de cada local.
///
/// Las fotos van al bucket publico `catalogo`, en la carpeta del propio local:
/// la base no deja escribir en la carpeta de otro.
class CatalogoRepository {
  const CatalogoRepository();

  SupabaseClient get _db => Backend.db;

  Future<List<Rubro>> rubros() => intentar(() async =>
      (await _db.from('rubros').select().eq('activo', true).order('orden', ascending: true)).map(Rubro.fromRow).toList());

  Future<Menu> menu(String comercioId, {bool soloDisponibles = false}) => intentar(() async {
        final secciones = (await _db
                .from('secciones_menu')
                .select()
                .eq('comercio_id', comercioId)
                .order('orden', ascending: true)
                .order('nombre', ascending: true))
            .map(SeccionMenu.fromRow)
            .toList();

        var q = _db
            .from('productos')
            .select('*, opciones_producto(*, opcion_items(*))')
            .eq('comercio_id', comercioId);
        if (soloDisponibles) q = q.eq('disponible', true);
        final productos = (await q.order('orden', ascending: true).order('nombre', ascending: true)).map(Producto.fromRow).toList();

        return Menu(
          secciones: soloDisponibles ? secciones.where((s) => s.activa).toList() : secciones,
          productos: productos,
        );
      });

  // ---- Secciones -------------------------------------------------------------

  Future<void> guardarSeccion({
    required String comercioId,
    required String nombre,
    String? id,
    int orden = 0,
  }) =>
      intentar(() async {
        final datos = {'comercio_id': comercioId, 'nombre': nombre.trim(), 'orden': orden};
        if (id == null) {
          await _db.from('secciones_menu').insert(datos);
        } else {
          await _db.from('secciones_menu').update(datos).eq('id', id);
        }
      });

  /// Los productos de la seccion no se borran: quedan "sin seccion".
  Future<void> borrarSeccion(String id) =>
      intentar(() => _db.from('secciones_menu').delete().eq('id', id));

  // ---- Productos -------------------------------------------------------------

  /// Crea o actualiza un producto con su foto y sus opciones.
  ///
  /// Las opciones se reemplazan enteras en cada guardado. No se pierde nada:
  /// los pedidos viejos guardan una copia del nombre y el precio de cada opcion
  /// elegida (pedido_item_opciones), no una referencia viva.
  Future<String> guardarProducto({
    required String comercioId,
    required String nombre,
    required int precio,
    String? id,
    String? seccionId,
    String? descripcion,
    bool disponible = true,
    List<OpcionProducto> opciones = const [],
    Uint8List? foto,
    String fotoExtension = 'jpg',
  }) =>
      intentar(() async {
        final datos = {
          'comercio_id': comercioId,
          'seccion_id': seccionId,
          'nombre': nombre.trim(),
          'descripcion': (descripcion ?? '').trim().isEmpty ? null : descripcion!.trim(),
          'precio': precio,
          'disponible': disponible,
        };

        final String productoId;
        if (id == null) {
          final f = await _db.from('productos').insert(datos).select('id').single();
          productoId = f['id'] as String;
        } else {
          await _db.from('productos').update(datos).eq('id', id);
          productoId = id;
        }

        if (foto != null) {
          final ruta = '$comercioId/productos/$productoId.$fotoExtension';
          await _db.storage.from('catalogo').uploadBinary(
                ruta,
                foto,
                fileOptions: FileOptions(
                  upsert: true,
                  contentType: fotoExtension == 'png' ? 'image/png' : 'image/jpeg',
                ),
              );
          final url = '${_db.storage.from('catalogo').getPublicUrl(ruta)}'
              '?v=${DateTime.now().millisecondsSinceEpoch}';
          await _db.from('productos').update({'foto_url': url}).eq('id', productoId);
        }

        await _db.from('opciones_producto').delete().eq('producto_id', productoId);
        for (var i = 0; i < opciones.length; i++) {
          final o = opciones[i];
          if (o.nombre.trim().isEmpty || o.items.isEmpty) continue;
          final grupo = await _db
              .from('opciones_producto')
              .insert({
                'producto_id': productoId,
                'nombre': o.nombre.trim(),
                'tipo': o.tipo.wire,
                'obligatoria': o.obligatoria,
                'min_selecciones': o.obligatoria ? 1 : 0,
                'max_selecciones': o.maxSelecciones,
                'orden': i,
              })
              .select('id')
              .single();
          await _db.from('opcion_items').insert([
            for (var j = 0; j < o.items.length; j++)
              if (o.items[j].nombre.trim().isNotEmpty)
                {
                  'opcion_id': grupo['id'],
                  'nombre': o.items[j].nombre.trim(),
                  'precio_extra': o.items[j].precioExtra,
                  'orden': j,
                },
          ]);
        }

        return productoId;
      });

  Future<void> setDisponible(String productoId, bool disponible) =>
      intentar(() => _db.from('productos').update({'disponible': disponible}).eq('id', productoId));

  Future<void> borrarProducto(Producto p) => intentar(() async {
        await _db.from('productos').delete().eq('id', p.id);
        // La foto se borra despues y sin frenar si falla: un archivo huerfano
        // no rompe nada, un producto que no se puede borrar si.
        try {
          await _db.storage.from('catalogo').remove([
            '${p.comercioId}/productos/${p.id}.jpg',
            '${p.comercioId}/productos/${p.id}.png',
          ]);
        } catch (_) {}
      });
}
