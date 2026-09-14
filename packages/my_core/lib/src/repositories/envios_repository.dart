import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/models.dart';

/// Envios (el tramo con rider).
///
/// Todo lo que cambia estado va por RPC: la base valida las transiciones y
/// calcula el precio. Aca no se escribe `envios` directamente nunca.
class EnviosRepository {
  const EnviosRepository();

  SupabaseClient get _db => Backend.db;

  static const _activos = [
    'buscando_repartidor', 'asignado', 'en_local', 'retirado', 'en_camino',
  ];

  List<Envio> _lista(List<Map<String, dynamic>> filas) => filas.map(Envio.fromRow).toList();

  Stream<List<Envio>> watchDelComercio(String comercioId) => enVivo(
        canal: 'envios-comercio',
        tablas: const ['envios'],
        leer: () async => _lista(await _db
            .from('v_envios')
            .select()
            .eq('comercio_id', comercioId)
            .order('creado_en', ascending: false)
            .limit(100)),
      );

  Stream<List<Envio>> watchActivos() => enVivo(
        canal: 'envios-activos',
        tablas: const ['envios'],
        leer: () async => _lista(await _db
            .from('v_envios')
            .select()
            .inFilter('estado', _activos)
            .order('creado_en', ascending: false)),
      );

  Stream<List<Envio>> watchDelRepartidor(String repartidorId) => enVivo(
        canal: 'envios-rider',
        tablas: const ['envios'],
        leer: () async => _lista(await _db
            .from('v_envios')
            .select()
            .eq('repartidor_id', repartidorId)
            .order('creado_en', ascending: false)
            .limit(100)),
      );

  Stream<Envio?> watchPorId(String id) => enVivo(
        canal: 'envio-$id',
        tablas: const ['envios'],
        leer: () async {
          final f = await _db.from('v_envios').select().eq('id', id).maybeSingle();
          return f == null ? null : Envio.fromRow(f);
        },
      );

  /// Ofertas abiertas para el rider logueado. RLS ya filtra las suyas.
  Stream<List<OfertaServicio>> watchOfertas() => enVivo(
        canal: 'ofertas',
        tablas: const ['ofertas'],
        leer: () async => (await _db.from('ofertas_abiertas').select().order('ofrecida_en', ascending: true))
            .map(OfertaServicio.fromRow)
            .toList(),
      );

  /// Cotiza un envio de cadeteria desde el local hasta un punto.
  Future<Cotizacion> cotizar({required double lat, required double lng}) => intentar(() async {
        final r = await _db.rpc('cotizar_desde_mi_comercio', params: {'p_lat': lat, 'p_lng': lng});
        return Cotizacion.fromJson(Map<String, dynamic>.from(r as Map));
      });

  /// Crea el envio y arranca la busqueda de rider.
  Future<String> crearYBuscar({
    required String calle,
    required double lat,
    required double lng,
    required String clienteNombre,
    required String clienteTelefono,
    required QuienPaga paga,
    String? referencia,
    String? indicaciones,
  }) =>
      intentar(() async {
        final creado = await _db.rpc('crear_envio', params: {
          'p_destino_calle': calle,
          'p_destino_lat': lat,
          'p_destino_lng': lng,
          'p_cliente_nombre': clienteNombre,
          'p_cliente_telefono': clienteTelefono,
          'p_paga': paga.wire,
          'p_destino_referencia': referencia,
          'p_cliente_indicaciones': indicaciones,
        });
        final id = (creado as Map)['id'] as String;
        await _db.rpc('confirmar_envio', params: {'p_envio': id});
        return id;
      });

  Future<void> responderOferta(String ofertaId, {required bool acepta}) => intentar(
        () => _db.rpc('responder_oferta', params: {'p_oferta': ofertaId, 'p_acepta': acepta}),
      );

  Future<void> avanzar(String envioId, EstadoEnvio nuevo) => intentar(
        () => _db.rpc('avanzar_estado', params: {'p_envio': envioId, 'p_nuevo': nuevo.wire}),
      );

  Future<void> confirmarEntrega(String envioId, String codigo) => intentar(
        () => _db.rpc('confirmar_entrega', params: {'p_envio': envioId, 'p_codigo': codigo}),
      );

  Future<void> cancelar(String envioId, String motivo) => intentar(
        () => _db.rpc('cancelar_envio', params: {'p_envio': envioId, 'p_motivo': motivo}),
      );
}
