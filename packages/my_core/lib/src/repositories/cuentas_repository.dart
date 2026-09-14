import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/marketplace.dart';

/// Direcciones del cliente y alta de cuentas por la administracion.
class DireccionesRepository {
  const DireccionesRepository();

  SupabaseClient get _db => Backend.db;

  Future<List<DireccionCliente>> mias() => intentar(() async => (await _db
          .from('v_direcciones')
          .select()
          .order('predeterminada', ascending: false)
          .order('creado_en', ascending: true))
      .map(DireccionCliente.fromRow)
      .toList());

  Future<String> agregar({
    required String alias,
    required String calle,
    required double lat,
    required double lng,
    String? referencia,
    bool predeterminada = false,
  }) =>
      intentar(() async {
        final id = await _db.rpc('agregar_direccion', params: {
          'p_alias': alias.trim().isEmpty ? 'Casa' : alias.trim(),
          'p_calle': calle.trim(),
          'p_lat': lat,
          'p_lng': lng,
          'p_referencia': (referencia ?? '').trim().isEmpty ? null : referencia!.trim(),
          'p_predeterminada': predeterminada,
        });
        return id as String;
      });

  Future<void> hacerPredeterminada(String id) => intentar(() async {
        // Primero se desmarca la actual: hay un indice unico que no admite dos.
        await _db.from('direcciones_cliente').update({'predeterminada': false}).eq('predeterminada', true);
        await _db.from('direcciones_cliente').update({'predeterminada': true}).eq('id', id);
      });

  Future<void> borrar(String id) => intentar(() => _db.from('direcciones_cliente').delete().eq('id', id));
}

class CuentasRepository {
  const CuentasRepository();

  SupabaseClient get _db => Backend.db;

  Future<AltaCuenta> _alta(Map<String, dynamic> cuerpo) => intentar(() async {
        final r = await _db.functions.invoke('admin-crear-usuario', body: cuerpo);
        final data = Map<String, dynamic>.from(r.data as Map);
        return AltaCuenta(
          email: data['email'] as String,
          passwordTemporal: data['password_temporal'] as String?,
        );
      });

  Future<AltaCuenta> crearComercio({
    required String email,
    required String nombre,
    required String telefono,
    required String calle,
    required double lat,
    required double lng,
    String? rubroId,
    String? referencia,
  }) =>
      _alta({
        'rol': 'comercio',
        'email': email.trim(),
        'nombre': nombre.trim(),
        'telefono': telefono.trim(),
        'calle': calle.trim(),
        'referencia': referencia,
        'rubro_id': rubroId,
        'lat': lat,
        'lng': lng,
      });

  Future<AltaCuenta> crearRepartidor({
    required String email,
    required String nombre,
    required String telefono,
    required Vehiculo vehiculo,
  }) =>
      _alta({
        'rol': 'repartidor',
        'email': email.trim(),
        'nombre': nombre.trim(),
        'telefono': telefono.trim(),
        'vehiculo': vehiculo.wire,
      });
}
