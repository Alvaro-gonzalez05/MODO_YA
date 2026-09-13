/// Configuracion por entorno.
///
/// **Ninguna clave se escribe en el codigo.** Todo entra por `--dart-define`
/// (o `--dart-define-from-file=env/dev.json`), asi el repositorio nunca tiene
/// secretos y cada flavor apunta a su propio proyecto de Supabase.
///
/// Ejemplo:
/// ```
/// flutter run --dart-define-from-file=env/dev.json
/// ```
///
/// Aclaracion importante sobre las claves de Supabase:
/// - La **publishable key** (`sb_publishable_...`) es la que va en la app.
///   Es publica por diseno: cualquiera puede leerla del binario. Lo que
///   protege los datos es RLS, no el secreto de esta clave.
/// - La **secret key** (`sb_secret_...`) equivale a `service_role`: saltea
///   RLS por completo. Solo puede vivir en Edge Functions o en el servidor,
///   nunca en una app de Flutter ni en el repositorio.
abstract final class Entorno {
  /// `dev`, `prod` o `demo`.
  static const flavor = String.fromEnvironment('MY_FLAVOR', defaultValue: 'demo');

  static const supabaseUrl = String.fromEnvironment('MY_SUPABASE_URL');

  /// Clave publishable (la que reemplaza a la vieja `anon key`).
  static const supabaseKey = String.fromEnvironment('MY_SUPABASE_KEY');

  /// Corre contra datos en memoria, sin tocar la red.
  static bool get esDemo => flavor == 'demo' || !tieneSupabase;

  static bool get tieneSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Verificacion temprana: si un flavor real arranca sin credenciales,
  /// preferimos fallar en el arranque y no con un error de red confuso.
  static void validar() {
    if (flavor == 'demo') return;
    if (!tieneSupabase) {
      throw StateError(
        'Falta configurar MY_SUPABASE_URL y MY_SUPABASE_KEY para el flavor '
        '"$flavor". Corre la app con '
        '--dart-define-from-file=env/$flavor.json',
      );
    }
  }
}
