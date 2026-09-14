import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'version_publicada.dart';

const _canal = MethodChannel('modoya/actualizaciones');

/// Lee `ultima.json`. Nunca tira: sin internet o sin archivo, la app sigue.
Future<VersionPublicada?> leerManifiesto(String url) async {
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    // El parámetro evita que alguna caché devuelva una copia vieja.
    final uri = Uri.parse(url).replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
    final respuesta = await (await cliente.getUrl(uri)).close().timeout(const Duration(seconds: 15));
    if (respuesta.statusCode != 200) return null;
    final cuerpo = await respuesta.transform(utf8.decoder).join();
    return VersionPublicada.desdeJson(jsonDecode(cuerpo) as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    cliente.close(force: true);
  }
}

/// "windows", "android-arm64" o "android-arm32". Null si no hay instalador.
Future<String?> plataformaActual() async {
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) {
    try {
      final abi = await _canal.invokeMethod<String>('abi');
      return (abi ?? '').contains('armeabi') ? 'android-arm32' : 'android-arm64';
    } catch (_) {
      return 'android-arm64';
    }
  }
  return null;
}

/// Baja el instalador y lo abre.
///
/// - Windows: lo ejecuta en silencio y cierra la app; el instalador reemplaza
///   los archivos y la vuelve a abrir.
/// - Android: abre el instalador del sistema, que pide confirmación.
Future<void> instalarVersion(String url, String version, void Function(double? progreso) alProgresar) async {
  final extension = Platform.isWindows ? 'exe' : 'apk';
  final destino = File('${Directory.systemTemp.path}${Platform.pathSeparator}MODO_YA-$version.$extension');

  final cliente = HttpClient();
  try {
    final respuesta = await (await cliente.getUrl(Uri.parse(url))).close();
    if (respuesta.statusCode != 200) {
      throw HttpException('El servidor respondió ${respuesta.statusCode}');
    }
    final total = respuesta.contentLength;
    var recibidos = 0;
    final salida = destino.openWrite();
    try {
      await for (final bloque in respuesta) {
        salida.add(bloque);
        recibidos += bloque.length;
        alProgresar(total > 0 ? recibidos / total : null);
      }
    } finally {
      await salida.close();
    }
  } finally {
    cliente.close();
  }

  if (Platform.isWindows) {
    await Process.start(
      destino.path,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/FORCECLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    // El instalador necesita la app cerrada para pisar el ejecutable.
    exit(0);
  }

  await _canal.invokeMethod<bool>('instalarApk', {'ruta': destino.path});
}
