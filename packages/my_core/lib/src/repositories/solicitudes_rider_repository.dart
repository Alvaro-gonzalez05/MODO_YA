import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/models.dart';

enum EstadoSolicitudRider {
  pendiente('pendiente', 'En revisión'),
  aprobada('aprobada', 'Aprobada'),
  rechazada('rechazada', 'Rechazada');

  const EstadoSolicitudRider(this.wire, this.label);

  final String wire;
  final String label;

  static EstadoSolicitudRider fromWire(String? v) =>
      values.firstWhere((e) => e.wire == v, orElse: () => EstadoSolicitudRider.pendiente);
}

/// Un local pide el alta de un rider nuevo (0055). La administración la
/// revisa con la documentación y, si la aprueba, se crea la cuenta y queda
/// vinculado al local.
class SolicitudRider {
  const SolicitudRider({
    required this.id,
    required this.comercioId,
    required this.nombre,
    required this.telefono,
    required this.vehiculo,
    required this.estado,
    required this.creadoEn,
    this.comercioNombre,
    this.nota,
    this.motivoRechazo,
    this.repartidorId,
  });

  final String id;
  final String comercioId;
  final String? comercioNombre;
  final String nombre;
  final String telefono;
  final Vehiculo vehiculo;
  final EstadoSolicitudRider estado;
  final DateTime creadoEn;
  final String? nota;
  final String? motivoRechazo;
  final String? repartidorId;

  factory SolicitudRider.fromRow(Map<String, dynamic> f) => SolicitudRider(
        id: Fila.texto(f, 'id'),
        comercioId: Fila.texto(f, 'comercio_id'),
        comercioNombre: (f['comercios'] as Map?)?['nombre'] as String?,
        nombre: Fila.texto(f, 'nombre'),
        telefono: Fila.texto(f, 'telefono'),
        vehiculo: Vehiculo.fromWire(f['vehiculo'] as String?),
        estado: EstadoSolicitudRider.fromWire(f['estado'] as String?),
        creadoEn: Fila.fecha(f, 'creado_en'),
        nota: Fila.textoOpcional(f, 'nota'),
        motivoRechazo: Fila.textoOpcional(f, 'motivo_rechazo'),
        repartidorId: Fila.textoOpcional(f, 'repartidor_id'),
      );
}

/// Un archivo de la documentación de una solicitud, con un link temporal.
class DocumentoSolicitud {
  const DocumentoSolicitud({required this.tipo, required this.url});

  final String tipo;
  final String url;
}

class SolicitudesRiderRepository {
  const SolicitudesRiderRepository();

  SupabaseClient get _db => Backend.db;

  static const _bucket = 'documentos';
  static String _carpeta(String solicitudId) => 'solicitudes/$solicitudId';

  /// Las del local de la sesión, o todas si es la administración (el RLS
  /// decide). Las más nuevas primero.
  Stream<List<SolicitudRider>> watch() => enVivo(
        canal: 'solicitudes-rider',
        tablas: const ['solicitudes_rider'],
        leer: () async => (await _db
                .from('solicitudes_rider')
                .select('*, comercios(nombre)')
                .order('creado_en', ascending: false)
                .limit(100))
            .map(SolicitudRider.fromRow)
            .toList(),
      );

  /// Qué documentación se le pide a un rider según su vehículo.
  Future<List<String>> documentosExigidos(Vehiculo vehiculo) => intentar(() async =>
      (await _db.from('documentos_exigidos').select('tipo').eq('vehiculo', vehiculo.wire).order('tipo'))
          .map((f) => f['tipo'] as String)
          .toList());

  /// Crea la solicitud y sube la documentación. [documentos] va por tipo
  /// ("DNI") con los bytes y la extensión del archivo.
  ///
  /// Si una foto no sube, la solicitud se retira: una a medias no le sirve a
  /// la administración para decidir.
  Future<void> solicitar({
    required String comercioId,
    required String nombre,
    required String telefono,
    required Vehiculo vehiculo,
    required Map<String, (Uint8List, String)> documentos,
    String? nota,
  }) =>
      intentar(() async {
        final f = await _db
            .from('solicitudes_rider')
            .insert({
              'comercio_id': comercioId,
              'nombre': nombre.trim(),
              'telefono': telefono.trim(),
              'vehiculo': vehiculo.wire,
              'nota': (nota ?? '').trim().isEmpty ? null : nota!.trim(),
            })
            .select('id')
            .single();
        final id = f['id'] as String;
        try {
          for (final MapEntry(key: tipo, value: (bytes, ext)) in documentos.entries) {
            await _db.storage.from(_bucket).uploadBinary(
                  '${_carpeta(id)}/${_archivo(tipo)}.$ext',
                  bytes,
                  fileOptions: FileOptions(upsert: true, contentType: _mime(ext)),
                );
          }
        } catch (_) {
          await _db.from('solicitudes_rider').delete().eq('id', id);
          rethrow;
        }
      });

  /// La documentación de una solicitud, con links que vencen en una hora.
  Future<List<DocumentoSolicitud>> documentosDe(String solicitudId) => intentar(() async {
        final archivos = await _db.storage.from(_bucket).list(path: _carpeta(solicitudId));
        final docs = <DocumentoSolicitud>[];
        for (final a in archivos) {
          final url = await _db.storage
              .from(_bucket)
              .createSignedUrl('${_carpeta(solicitudId)}/${a.name}', 3600);
          docs.add(DocumentoSolicitud(tipo: _tipo(a.name), url: url));
        }
        return docs;
      });

  /// El local la retira mientras está en revisión.
  Future<void> retirar(String id) =>
      intentar(() => _db.from('solicitudes_rider').delete().eq('id', id));

  /// La administración la rechaza y le dice al local por qué.
  Future<void> rechazar(String id, String motivo) => intentar(() => _db.rpc(
        'admin_rechazar_solicitud_rider',
        params: {'p_solicitud': id, 'p_motivo': motivo},
      ));

  /// "Licencia de conducir" -> "Licencia_de_conducir": sin espacios ni
  /// acentos, que Storage no acepta en el nombre.
  static String _archivo(String tipo) => tipo
      .replaceAll(RegExp('[áÁ]'), 'a')
      .replaceAll(RegExp('[éÉ]'), 'e')
      .replaceAll(RegExp('[íÍ]'), 'i')
      .replaceAll(RegExp('[óÓ]'), 'o')
      .replaceAll(RegExp('[úÚ]'), 'u')
      .replaceAll(RegExp('[^A-Za-z0-9]+'), '_');

  static String _tipo(String archivo) => archivo.split('.').first.replaceAll('_', ' ');

  static String _mime(String ext) => switch (ext) {
        'png' => 'image/png',
        'pdf' => 'application/pdf',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
