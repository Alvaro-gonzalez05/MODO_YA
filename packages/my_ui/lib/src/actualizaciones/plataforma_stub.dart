import 'version_publicada.dart';

/// Web: no hay instaladores. La versión web se actualiza sola al recargar.
Future<VersionPublicada?> leerManifiesto(String url) async => null;

Future<String?> plataformaActual() async => null;

Future<void> instalarVersion(String url, String version, void Function(double? progreso) alProgresar) async {}
