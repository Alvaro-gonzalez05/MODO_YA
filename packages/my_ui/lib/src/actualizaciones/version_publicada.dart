/// La última versión publicada, tal como la escribe el workflow de release en
/// `ultima.json` (un archivo más del Release de GitHub).
///
/// ```json
/// {
///   "version": "1.2.0",
///   "notas": "Pedidos con propina",
///   "obligatoria": false,
///   "archivos": {
///     "modo_ya-windows": "https://.../MODO_YA-Windows-Setup.exe",
///     "modo_ya-android-arm64": "https://.../MODO_YA-Android.apk",
///     "modo_ya-android-arm32": "https://.../MODO_YA-Android-32bits.apk",
///     "rider-android-arm64": "https://.../MODO_YA-Rider-Android.apk",
///     "rider-android-arm32": "https://.../MODO_YA-Rider-Android-32bits.apk"
///   }
/// }
/// ```
class VersionPublicada {
  const VersionPublicada({
    required this.version,
    required this.notas,
    required this.obligatoria,
    required this.archivos,
  });

  factory VersionPublicada.desdeJson(Map<String, dynamic> j) => VersionPublicada(
        version: (j['version'] as String? ?? '').trim(),
        notas: (j['notas'] as String? ?? '').trim(),
        obligatoria: j['obligatoria'] == true,
        archivos: {
          for (final e in (j['archivos'] as Map? ?? const {}).entries) '${e.key}': '${e.value}',
        },
      );

  final String version;
  final String notas;

  /// La app no deja seguir hasta actualizar. Para cuando cambia algo de la base
  /// que las versiones viejas ya no entienden.
  final bool obligatoria;

  /// Clave "app-plataforma" → URL del instalador.
  final Map<String, String> archivos;
}

/// Compara "mayor.menor.parche". Negativo si a < b.
int compararVersiones(String a, String b) {
  List<int> partes(String v) =>
      v.trim().replaceFirst(RegExp(r'^v'), '').split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final pa = partes(a);
  final pb = partes(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
