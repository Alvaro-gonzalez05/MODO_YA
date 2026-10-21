import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/models.dart';

/// Un documento que se le exige a un rider según su vehículo.
///
/// La lista vive en `documentos_exigidos` y la sembró 0007: cambiar el
/// requisito es un insert o un delete, no una migración.
class DocumentoExigido {
  const DocumentoExigido({
    required this.vehiculo,
    required this.tipo,
    required this.obligatorio,
  });

  final Vehiculo vehiculo;
  final String tipo;
  final bool obligatorio;

  factory DocumentoExigido.fromRow(Map<String, dynamic> f) => DocumentoExigido(
        vehiculo: Vehiculo.fromWire(f['vehiculo'] as String?),
        tipo: Fila.texto(f, 'tipo'),
        obligatorio: Fila.booleano(f, 'obligatorio', true),
      );
}

/// Un archivo que el rider ya subió, con lo que decidió la administración.
class DocumentoRider {
  const DocumentoRider({
    required this.id,
    required this.repartidorId,
    required this.tipo,
    required this.estado,
    required this.actualizadoEn,
    this.archivo,
    this.venceEn,
    this.observacion,
    this.validadoEn,
  });

  final String id;
  final String repartidorId;
  final String tipo;
  final EstadoAprobacion estado;

  /// Ruta dentro del bucket privado `documentos`. No es una URL que se pueda
  /// abrir: para verla hay que pedir un link firmado ([DocumentacionRepository.link]).
  final String? archivo;

  /// Hasta cuándo vale (licencia, seguro). Null en los que no vencen.
  final DateTime? venceEn;

  /// Lo que la administración escribió al rechazarlo.
  final String? observacion;
  final DateTime? validadoEn;
  final DateTime actualizadoEn;

  bool get vencido {
    final v = venceEn;
    if (v == null) return false;
    final hoy = DateTime.now();
    return v.isBefore(DateTime(hoy.year, hoy.month, hoy.day));
  }

  /// Aprobado y sin vencer: no hay nada que hacer con este.
  bool get alDia => estado == EstadoAprobacion.aprobado && !vencido;

  factory DocumentoRider.fromRow(Map<String, dynamic> f) => DocumentoRider(
        id: Fila.texto(f, 'id'),
        repartidorId: Fila.texto(f, 'repartidor_id'),
        tipo: Fila.texto(f, 'tipo'),
        estado: EstadoAprobacion.fromWire(f['estado'] as String?),
        archivo: Fila.textoOpcional(f, 'archivo_url'),
        venceEn: Fila.fechaOpcional(f, 'vence_en'),
        observacion: Fila.textoOpcional(f, 'observacion'),
        validadoEn: Fila.fechaOpcional(f, 'validado_en'),
        actualizadoEn: Fila.fecha(f, 'actualizado_en'),
      );
}

/// Un renglón de la carpeta: qué se le pide y, si lo subió, cómo está.
class RenglonDeCarpeta {
  const RenglonDeCarpeta({
    required this.tipo,
    required this.obligatorio,
    this.documento,
  });

  final String tipo;
  final bool obligatorio;

  /// Null si todavía no subió nada de este tipo.
  final DocumentoRider? documento;

  bool get subido => documento != null;
  bool get alDia => documento?.alDia ?? false;
  bool get rechazado => documento?.estado == EstadoAprobacion.rechazado;
  bool get enRevision => documento?.estado == EstadoAprobacion.pendiente;
  bool get vencido => documento?.vencido ?? false;

  /// Le toca mover algo al rider: no lo subió, se lo rechazaron o vencio.
  bool get leFaltaAlRider => !subido || rechazado || vencido;
}

/// La carpeta completa de un rider: los documentos que se le exigen por su
/// vehículo más los que subió alguna vez y hoy ya no se le piden (cambió de
/// vehículo, o la administración sacó el requisito).
class CarpetaRider {
  const CarpetaRider(this.renglones);

  final List<RenglonDeCarpeta> renglones;

  /// Solo los que se le exigen hoy. Es lo que decide si la carpeta está lista.
  Iterable<RenglonDeCarpeta> get exigidos => renglones.where((r) => r.obligatorio);

  int get total => exigidos.length;
  int get alDia => exigidos.where((r) => r.alDia).length;
  int get enRevision => exigidos.where((r) => r.enRevision).length;
  int get rechazados => exigidos.where((r) => r.rechazado).length;
  int get faltantes => exigidos.where((r) => !r.subido).length;
  int get vencidos => exigidos.where((r) => r.vencido).length;

  bool get completa => total > 0 && alDia == total;

  /// La administración tiene algo nuevo para mirar.
  bool get esperaRevision => enRevision > 0;

  /// Una línea para la ficha y para la pantalla del rider, igual en las dos.
  String get titular {
    if (total == 0) return 'No se le pide documentación para su vehículo';
    if (completa) return 'Documentación completa';
    if (vencidos > 0) return vencidos == 1 ? 'Tiene 1 documento vencido' : 'Tiene $vencidos documentos vencidos';
    if (rechazados > 0) return rechazados == 1 ? 'Le rechazamos 1 documento' : 'Le rechazamos $rechazados documentos';
    if (faltantes > 0) return faltantes == 1 ? 'Falta 1 documento' : 'Faltan $faltantes documentos';
    return enRevision == 1 ? '1 documento esperando revisión' : '$enRevision documentos esperando revisión';
  }

  /// Arma la carpeta cruzando lo exigido con lo subido.
  factory CarpetaRider.armar({
    required Vehiculo vehiculo,
    required List<DocumentoExigido> exigidos,
    required List<DocumentoRider> subidos,
  }) {
    final delVehiculo = exigidos.where((e) => e.vehiculo == vehiculo).toList();
    final porTipo = {for (final d in subidos) d.tipo: d};

    final renglones = [
      for (final e in delVehiculo)
        RenglonDeCarpeta(tipo: e.tipo, obligatorio: e.obligatorio, documento: porTipo[e.tipo]),
      // Los que subió y hoy no se le piden se muestran igual, pero no cuentan
      // para "completa": si cambió de moto a bicicleta, la cédula verde que ya
      // tenía no puede dejarle la carpeta trabada ni para siempre aprobada.
      for (final d in subidos)
        if (!delVehiculo.any((e) => e.tipo == d.tipo))
          RenglonDeCarpeta(tipo: d.tipo, obligatorio: false, documento: d),
    ];
    return CarpetaRider(renglones);
  }
}

/// Documentación de los riders: la sube el rider, la valida la administración.
class DocumentacionRepository {
  const DocumentacionRepository();

  SupabaseClient get _db => Backend.db;

  /// Privado (0017:370): acá va la documentación y nadie la ve por CDN.
  static const _bucket = 'documentos';

  /// Qué se le exige a cada vehículo. No cambia seguido, así que se lee de una
  /// sola vez y se cruza en memoria.
  Future<List<DocumentoExigido>> exigidos() => intentar(() async =>
      (await _db.from('documentos_exigidos').select().order('tipo'))
          .map(DocumentoExigido.fromRow)
          .toList());

  /// Lo subido. Sin [repartidorId] trae todo lo que el RLS permita: la
  /// administración ve todas las carpetas, un rider solo la suya
  /// (`documentos_repartidor_propios`, 0008:241).
  Stream<List<DocumentoRider>> watch({String? repartidorId}) => enVivo(
        canal: 'documentos-${repartidorId ?? 'todos'}',
        tablas: const ['documentos_repartidor'],
        leer: () async {
          var q = _db.from('documentos_repartidor').select();
          if (repartidorId != null) q = q.eq('repartidor_id', repartidorId);
          return (await q.order('tipo')).map(DocumentoRider.fromRow).toList();
        },
      );

  /// Sube (o reemplaza) el archivo de un documento y deja la fila apuntándolo.
  ///
  /// El estado no se manda: lo pone la base. En un alta queda 'pendiente' por
  /// el default de la columna, y en un reemplazo lo vuelve a 'pendiente' el
  /// trigger `documentos_repartidor_a_revision` (0066), porque `estado` no es
  /// una columna que el rider pueda escribir.
  Future<void> subir({
    required String repartidorId,
    required String tipo,
    required Uint8List bytes,
    required String extension,
    DateTime? venceEn,
  }) =>
      intentar(() async {
        // El nombre lleva la extensión, así que reemplazar un JPG por un PDF
        // deja el archivo viejo colgado en el bucket. Se vive con eso: Storage
        // no tiene política de delete para `documentos` (0017:402-421) y no
        // vale la pena abrirle una al rider para limpiar un archivo que nadie
        // puede ver.
        final ruta = '$repartidorId/${_archivo(tipo)}.$extension';
        await _db.storage.from(_bucket).uploadBinary(
              ruta,
              bytes,
              fileOptions: FileOptions(upsert: true, contentType: _mime(extension)),
            );

        // `unique (repartidor_id, tipo)` obliga a insertar o actualizar, y no
        // se puede usar upsert: el rider tiene permiso de update solo sobre
        // archivo_url y vence_en (0016:43-47), y un upsert escribiria todas las
        // columnas que manda.
        final existente = await _db
            .from('documentos_repartidor')
            .select('id')
            .eq('repartidor_id', repartidorId)
            .eq('tipo', tipo)
            .maybeSingle();

        final datos = {
          'archivo_url': ruta,
          'vence_en': venceEn == null ? null : _soloFecha(venceEn),
        };
        if (existente == null) {
          await _db.from('documentos_repartidor').insert({
            'repartidor_id': repartidorId,
            'tipo': tipo,
            ...datos,
          });
        } else {
          await _db.from('documentos_repartidor').update(datos).eq('id', existente['id'] as String);
        }
      });

  /// Cambia solo la fecha de vencimiento. No vuelve el documento a revisión:
  /// el archivo es el mismo.
  Future<void> fijarVencimiento(String documentoId, DateTime? venceEn) =>
      intentar(() => _db
          .from('documentos_repartidor')
          .update({'vence_en': venceEn == null ? null : _soloFecha(venceEn)})
          .eq('id', documentoId));

  /// Link para abrir el archivo, válido una hora. El bucket es privado: el
  /// RLS de Storage deja mirarlo al propio rider y a la administración.
  Future<String> link(String archivo) =>
      intentar(() => _db.storage.from(_bucket).createSignedUrl(archivo, 3600));

  /// La administración lo aprueba o lo rechaza. Con 'rechazado' la observación
  /// es lo que el rider lee para saber qué volver a subir.
  Future<void> validar(String documentoId, EstadoAprobacion estado, {String? observacion}) =>
      intentar(() => _db.rpc('admin_validar_documento', params: {
            'p_documento': documentoId,
            'p_estado': estado.wire,
            'p_observacion': (observacion ?? '').trim().isEmpty ? null : observacion!.trim(),
          }));

  /// "Licencia de conducir" -> "Licencia_de_conducir": sin espacios ni acentos,
  /// que Storage no acepta en el nombre del objeto.
  static String _archivo(String tipo) => tipo
      .replaceAll(RegExp('[áÁ]'), 'a')
      .replaceAll(RegExp('[éÉ]'), 'e')
      .replaceAll(RegExp('[íÍ]'), 'i')
      .replaceAll(RegExp('[óÓ]'), 'o')
      .replaceAll(RegExp('[úÚ]'), 'u')
      .replaceAll(RegExp('[^A-Za-z0-9]+'), '_');

  static String _mime(String ext) => switch (ext) {
        'png' => 'image/png',
        'pdf' => 'application/pdf',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  /// `vence_en` es `date`: mandarle un timestamp con zona lo corre un día.
  static String _soloFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
