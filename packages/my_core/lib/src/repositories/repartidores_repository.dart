import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/models.dart';

/// Riders.
class RepartidoresRepository {
  const RepartidoresRepository();

  SupabaseClient get _db => Backend.db;

  Stream<List<Repartidor>> watchTodos() => enVivo(
        canal: 'riders',
        tablas: const ['repartidores'],
        leer: () async => (await _db.from('v_repartidores').select().order('nombre', ascending: true))
            .map(Repartidor.fromRow)
            .toList(),
      );

  Stream<Repartidor?> watchPorId(String id) => enVivo(
        canal: 'rider-$id',
        tablas: const ['repartidores'],
        leer: () async {
          final f = await _db.from('v_repartidores').select().eq('id', id).maybeSingle();
          return f == null ? null : Repartidor.fromRow(f);
        },
      );

  Future<void> setConectado(bool conectado) =>
      intentar(() => _db.rpc('set_conectado', params: {'p_conectado': conectado}));

  Future<void> actualizarUbicacion(double lat, double lng) => intentar(
        () => _db.rpc('actualizar_ubicacion', params: {'p_lat': lat, 'p_lng': lng}),
      );

  Future<void> cambiarAprobacion(String repartidorId, EstadoAprobacion estado, {String? motivo}) =>
      intentar(() => _db.rpc('admin_aprobacion_repartidor', params: {
            'p_repartidor': repartidorId,
            'p_estado': estado.wire,
            'p_motivo': motivo,
          }));
}
