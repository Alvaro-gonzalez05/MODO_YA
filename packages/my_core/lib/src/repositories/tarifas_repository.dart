import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/models.dart';

/// Tarifario. Versionado en la base: cambiarlo crea uno nuevo.
class TarifasRepository {
  const TarifasRepository();

  SupabaseClient get _db => Backend.db;

  Future<Tarifario?> vigente() => intentar(() async {
        final f = await _db
            .from('tarifarios')
            .select()
            .eq('servicio', 'delivery')
            .isFilter('vigente_hasta', null)
            .order('vigente_desde', ascending: false)
            .limit(1)
            .maybeSingle();
        return f == null ? null : Tarifario.fromRow(f);
      });

  /// Cierra el tarifario vigente y abre uno nuevo, en una sola operacion.
  Future<void> reemplazar(Tarifario t) => intentar(() async {
        final ciudad = t.ciudadId;
        if (ciudad == null) throw const ErrorModoYa('El tarifario no tiene ciudad.');
        await _db.rpc('admin_nuevo_tarifario', params: {
          'p_ciudad': ciudad,
          'p_ganancia_repartidor_base': t.gananciaRepartidorBase,
          'p_comision_modo_ya': t.comisionModoYa,
          'p_precio_km_adicional': t.precioKmAdicional,
          'p_km_incluidos': t.kmIncluidos,
          'p_radio_busqueda_km': t.radioBusquedaKm,
          'p_segundos_para_aceptar': t.segundosParaAceptar,
          'p_precio_suscripcion_mensual': t.precioSuscripcionMensual,
        });
      });
}
