import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/entorno.dart';

/// Acceso a Supabase.
abstract final class Backend {
  static Future<void> inicializar() async {
    Entorno.validar();
    await Supabase.initialize(
      url: Entorno.supabaseUrl,
      publishableKey: Entorno.supabaseKey,
    );
  }

  static SupabaseClient get db => Supabase.instance.client;
}

/// Error listo para mostrarle al usuario.
class ErrorModoYa implements Exception {
  const ErrorModoYa(this.mensaje, {this.codigo});

  final String mensaje;

  /// SQLSTATE o codigo de Auth, para decidir en la UI sin leer el texto.
  final String? codigo;

  @override
  String toString() => mensaje;
}

/// Traduce cualquier excepcion del backend a un mensaje en castellano.
///
/// Los errores de negocio llegan con SQLSTATE propios (MY0xx, ver
/// supabase/README.md); el texto del mensaje ya viene redactado para el usuario
/// desde la base, asi que se usa tal cual.
ErrorModoYa traducirError(Object e) {
  if (e is ErrorModoYa) return e;

  if (e is PostgrestException) {
    final codigo = e.code;
    if (codigo != null && (codigo.startsWith('MY') || codigo == '42501')) {
      return ErrorModoYa(e.message, codigo: codigo);
    }
    if (codigo == 'PGRST301' || codigo == 'PGRST303') {
      return ErrorModoYa('Tu sesion vencio. Volve a entrar.', codigo: codigo);
    }
    if (codigo == '23505') {
      return ErrorModoYa('Ya existe un registro con esos datos.', codigo: codigo);
    }
    return ErrorModoYa('No pudimos completar la operacion (${e.message}).', codigo: codigo);
  }

  if (e is AuthException) {
    final c = e.code ?? '';
    final m = e.message.toLowerCase();
    final mensaje = switch (c) {
      'invalid_credentials' => 'Email o contrasena incorrectos.',
      'email_not_confirmed' => 'Tenes que confirmar tu email antes de entrar.',
      'user_already_exists' || 'email_exists' => 'Ya hay una cuenta con ese email.',
      'weak_password' => 'La contrasena es muy debil. Usa al menos 8 caracteres.',
      'over_email_send_rate_limit' =>
        'No pudimos mandar el mail de confirmacion. Probalo de nuevo mas tarde.',
      'email_address_invalid' => 'Ese email no es valido.',
      'signup_disabled' => 'El registro de cuentas esta deshabilitado.',
      _ when m.contains('invalid login') => 'Email o contrasena incorrectos.',
      _ => 'No pudimos iniciar sesion (${e.message}).',
    };
    return ErrorModoYa(mensaje, codigo: c);
  }

  if (e is FunctionException) {
    final detalles = e.details;
    if (detalles is Map && detalles['error'] is Map) {
      final err = detalles['error'] as Map;
      return ErrorModoYa('${err['mensaje']}', codigo: '${err['codigo']}');
    }
    return ErrorModoYa('No pudimos completar la operacion (HTTP ${e.status}).');
  }

  if (e is StorageException) {
    return ErrorModoYa('No pudimos subir el archivo (${e.message}).', codigo: e.statusCode);
  }

  // Sin dart:io, que no existe en la compilacion web: se reconoce por nombre.
  final tipo = e.runtimeType.toString();
  if (e is TimeoutException || tipo.contains('SocketException') || tipo.contains('ClientException')) {
    return const ErrorModoYa('Sin conexion. Revisa internet y volve a intentar.');
  }

  return ErrorModoYa('Algo salio mal: $e');
}

/// Ejecuta una llamada al backend traduciendo el error.
Future<T> intentar<T>(Future<T> Function() accion) async {
  try {
    return await accion();
  } catch (e) {
    throw traducirError(e);
  }
}

/// Stream "en vivo": lee una vez y vuelve a leer cada vez que cambia alguna de
/// las [tablas].
///
/// Se escucha el cambio en la tabla y se relee la VISTA, en vez de usar el
/// payload del evento, por dos razones: las vistas traen lat/lng y nombres
/// resueltos que el payload crudo no tiene, y Realtime no emite eventos sobre
/// vistas. Postgres Changes respeta RLS, asi que cada uno recibe solo lo suyo.
///
/// Los cambios que llegan juntos se agrupan (250 ms) para no releer diez veces
/// cuando una sola operacion toca varias filas.
Stream<T> enVivo<T>({
  required String canal,
  required List<String> tablas,
  required Future<T> Function() leer,
}) {
  late final StreamController<T> ctrl;
  RealtimeChannel? canalRt;
  Timer? agrupador;
  var cerrado = false;

  Future<void> refrescar() async {
    try {
      final valor = await leer();
      if (!cerrado) ctrl.add(valor);
    } catch (e, st) {
      if (!cerrado) ctrl.addError(traducirError(e), st);
    }
  }

  ctrl = StreamController<T>(
    onListen: () {
      refrescar();
      final db = Backend.db;
      var c = db.channel('$canal-${DateTime.now().microsecondsSinceEpoch}');
      for (final t in tablas) {
        c = c.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: t,
          callback: (_) {
            agrupador?.cancel();
            agrupador = Timer(const Duration(milliseconds: 250), refrescar);
          },
        );
      }
      canalRt = c..subscribe();
    },
    onCancel: () async {
      cerrado = true;
      agrupador?.cancel();
      final c = canalRt;
      if (c != null) await Backend.db.removeChannel(c);
      await ctrl.close();
    },
  );

  return ctrl.stream;
}
