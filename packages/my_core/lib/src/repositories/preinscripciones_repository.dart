import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/models.dart';

enum TipoPreinscripcion {
  local('local', 'Local'),
  rider('rider', 'Rider');

  const TipoPreinscripcion(this.wire, this.label);

  final String wire;
  final String label;

  static TipoPreinscripcion fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => TipoPreinscripcion.local);
}

enum EstadoPreinscripcion {
  pendiente('pendiente', 'Sin contactar'),
  contactada('contactada', 'Contactada'),
  descartada('descartada', 'Descartada');

  const EstadoPreinscripcion(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoPreinscripcion fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => EstadoPreinscripcion.pendiente);
}

/// Un formulario de la landing (0057): un local o un rider que quiere
/// sumarse antes del lanzamiento. La administración lo contacta por WhatsApp.
class Preinscripcion {
  const Preinscripcion({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.whatsapp,
    required this.datos,
    required this.estado,
    required this.creadoEn,
    this.email,
  });

  final String id;
  final TipoPreinscripcion tipo;

  /// El nombre del local o el del rider, según [tipo].
  final String nombre;
  final String whatsapp;
  final String? email;

  /// El resto del formulario tal cual llegó ("rubro", "horario"...).
  final Map<String, String> datos;
  final EstadoPreinscripcion estado;
  final DateTime creadoEn;

  factory Preinscripcion.fromRow(Map<String, dynamic> f) => Preinscripcion(
        id: Fila.texto(f, 'id'),
        tipo: TipoPreinscripcion.fromWire(f['tipo'] as String?),
        nombre: Fila.texto(f, 'nombre'),
        whatsapp: Fila.texto(f, 'whatsapp'),
        email: Fila.textoOpcional(f, 'email'),
        datos: {
          for (final MapEntry(:key, :value) in ((f['datos'] as Map?) ?? const {}).entries) '$key': '$value',
        },
        estado: EstadoPreinscripcion.fromWire(f['estado'] as String?),
        creadoEn: Fila.fecha(f, 'creado_en'),
      );
}

class PreinscripcionesRepository {
  const PreinscripcionesRepository();

  SupabaseClient get _db => Backend.db;

  /// Todas, las más nuevas primero. Solo la administración las ve (RLS).
  Stream<List<Preinscripcion>> watch() => enVivo(
        canal: 'preinscripciones',
        tablas: const ['preinscripciones'],
        leer: () async => (await _db
                .from('preinscripciones')
                .select()
                .order('creado_en', ascending: false)
                .limit(200))
            .map(Preinscripcion.fromRow)
            .toList(),
      );

  Future<void> marcar(String id, EstadoPreinscripcion estado) => intentar(() => _db.rpc(
        'admin_marcar_preinscripcion',
        params: {'p_id': id, 'p_estado': estado.wire},
      ));
}
