import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/models.dart';

/// Un rider tal como lo elige un local para sus envíos.
class RiderParaElegir {
  const RiderParaElegir({
    required this.id,
    required this.nombre,
    required this.vehiculo,
    this.conectado = false,
    this.esMio = false,
  });

  final String id;
  final String nombre;
  final Vehiculo vehiculo;
  final bool conectado;

  /// Si este local ya lo tiene en su lista.
  final bool esMio;

  factory RiderParaElegir.fromRow(Map<String, dynamic> f) => RiderParaElegir(
        id: Fila.texto(f, 'repartidor_id'),
        nombre: Fila.texto(f, 'nombre'),
        vehiculo: Vehiculo.fromWire(f['vehiculo'] as String?),
        conectado: Fila.booleano(f, 'conectado'),
        esMio: Fila.booleano(f, 'es_mio'),
      );
}

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

  /// Los riders que el local puede sumar a los suyos, y cuáles ya sumó.
  ///
  /// Se relee cuando cambia el vínculo o cuando un rider se conecta, así el
  /// local ve al toque si el suyo está disponible.
  Stream<List<RiderParaElegir>> watchParaElegir() => enVivo(
        canal: 'riders-del-local',
        tablas: const ['comercio_riders', 'repartidores'],
        leer: () async => ((await _db.rpc('riders_para_elegir')) as List)
            .map((e) => RiderParaElegir.fromRow(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Suma o saca un rider de la lista del local.
  Future<void> marcarComoMio(String comercioId, String repartidorId, {required bool mio}) =>
      intentar(() async {
        if (mio) {
          await _db.from('comercio_riders').insert({
            'comercio_id': comercioId,
            'repartidor_id': repartidorId,
          });
        } else {
          await _db
              .from('comercio_riders')
              .delete()
              .eq('comercio_id', comercioId)
              .eq('repartidor_id', repartidorId);
        }
      });

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
