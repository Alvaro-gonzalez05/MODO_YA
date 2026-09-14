/// Configuracion por entorno.
///
/// **Ninguna clave se escribe en el codigo.** Todo entra por
/// `--dart-define-from-file=env/dev.json` (el archivo esta en .gitignore y hay
/// un ejemplo en env/example.json).
///
/// Sobre las claves de Supabase:
/// - La **publishable key** (`sb_publishable_...`) es la que va en la app. Es
///   publica por diseno: cualquiera puede leerla del binario. Lo que protege
///   los datos es RLS, no el secreto de esta clave.
/// - La **secret key** (`sb_secret_...`) saltea RLS por completo. Solo vive en
///   Edge Functions. Nunca en una app ni en el repositorio.
abstract final class Entorno {
  /// `dev` o `prod`.
  static const flavor = String.fromEnvironment('MY_FLAVOR', defaultValue: 'dev');

  /// Version instalada. La pone el workflow de release desde el tag (v1.2.0 ->
  /// 1.2.0); en desarrollo queda vacia y no se buscan actualizaciones.
  static const version = String.fromEnvironment('MY_VERSION');

  /// Ultima version publicada (lo escribe el workflow de release).
  static const urlActualizaciones = String.fromEnvironment(
    'MY_URL_ACTUALIZACIONES',
    defaultValue: 'https://github.com/Alvaro-gonzalez05/MODO_YA/releases/latest/download/ultima.json',
  );

  static const supabaseUrl = String.fromEnvironment('MY_SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('MY_SUPABASE_KEY');

  static bool get tieneSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Falla en el arranque con un mensaje claro, en vez de con un error de red
  /// confuso la primera vez que se toca la base.
  static void validar() {
    if (!tieneSupabase) {
      throw StateError(
        'Falta la configuracion de Supabase. Corre la app con '
        '--dart-define-from-file=../../env/dev.json (ver env/example.json).',
      );
    }
  }
}
