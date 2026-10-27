import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend.dart';
import 'models/estados.dart';
import 'models/models.dart';

/// Quien entro. Sale de la RPC `mi_sesion`, que resuelve todo en una llamada.
class Sesion {
  const Sesion({
    required this.usuarioId,
    required this.rol,
    required this.nombre,
    this.email,
    this.telefono,
    this.comercioId,
    this.repartidorId,
    this.clienteId,
    this.ciudadId,
    this.aprobacion,
  });

  final String usuarioId;
  final RolUsuario? rol;
  final String nombre;
  final String? email;
  final String? telefono;
  final String? comercioId;
  final String? repartidorId;
  final String? clienteId;
  final String? ciudadId;

  /// Solo para locales y riders.
  final EstadoAprobacion? aprobacion;

  /// Sin sesion. Las pantallas nunca deberian verla: el router no deja entrar.
  static const vacia = Sesion(usuarioId: '', rol: null, nombre: '');

  bool get puedeOperar => aprobacion == null || aprobacion!.puedeOperar;

  factory Sesion.fromJson(Map<String, dynamic> f, {String? email}) => Sesion(
        usuarioId: Fila.texto(f, 'usuario_id'),
        rol: RolUsuario.fromWire(f['rol'] as String?),
        nombre: Fila.texto(f, 'nombre'),
        email: email,
        telefono: Fila.textoOpcional(f, 'telefono'),
        comercioId: Fila.textoOpcional(f, 'comercio_id'),
        repartidorId: Fila.textoOpcional(f, 'repartidor_id'),
        clienteId: Fila.textoOpcional(f, 'cliente_id'),
        ciudadId: Fila.textoOpcional(f, 'ciudad_id'),
        aprobacion: f['estado_aprobacion'] == null
            ? null
            : EstadoAprobacion.fromWire(f['estado_aprobacion'] as String),
      );
}

/// Entrar, registrarse y salir.
class AuthRepository {
  const AuthRepository();

  GoTrueClient get _auth => Backend.db.auth;

  Future<void> entrar(String email, String password) => intentar(
        () => _auth.signInWithPassword(email: usuarioActual(email), password: password),
      );

  /// Los usuarios de locales y riders eran `@modoya.com` hasta 0074, y alguno
  /// lo puede tener anotado así. Se acepta y se traduce al de ahora.
  static String usuarioActual(String email) {
    final e = email.trim();
    return e.toLowerCase().endsWith('@modoya.com') ? '${e.substring(0, e.length - 11)}@modoya.app' : e;
  }

  /// Si es un usuario generado por la administración (local o rider): no tiene
  /// casilla, así que el mail de recuperar la contraseña no le llegaría.
  static bool esUsuarioGenerado(String email) {
    final e = usuarioActual(email).toLowerCase();
    return e.endsWith('@modoya.app');
  }

  /// Registro de un cliente. Devuelve `true` si ya quedo con sesion iniciada y
  /// `false` si el proyecto exige confirmar el email primero.
  ///
  /// El nombre y el telefono viajan en user_metadata. El rol NO: la base lo
  /// ignora ahi a proposito y cualquier registro queda como cliente.
  Future<bool> registrarCliente({
    required String nombre,
    required String telefono,
    required String email,
    required String password,
  }) =>
      intentar(() async {
        final r = await _auth.signUp(
          email: email.trim(),
          password: password,
          data: {'nombre': nombre.trim(), 'telefono': telefono.trim()},
        );
        return r.session != null;
      });

  /// Manda el mail para elegir una contraseña nueva.
  ///
  /// El link no vuelve a la app sino a la página `nueva-clave` de la web
  /// (la plantilla del mail lo arma con `{{ .TokenHash }}`): así sirve igual si
  /// el mail se abre en otro dispositivo, y no depende de que la app sepa
  /// abrir links.
  Future<void> recuperarPassword(String email) =>
      intentar(() => _auth.resetPasswordForEmail(email.trim()));

  /// Elimina la cuenta del cliente que está usando la app (0073) y cierra la
  /// sesión. Los pedidos quedan, sin sus datos, para las liquidaciones.
  ///
  /// Las tarjetas guardadas se borran antes en Mercado Pago, una por una y sin
  /// frenar si alguna falla: la base las borra igual, y una tarjeta que quedó
  /// en el customer de Mercado Pago no se puede usar sin la cuenta.
  Future<void> eliminarMiCuenta() => intentar(() async {
        final tarjetas = await Backend.db.from('tarjetas_guardadas').select('id');
        for (final t in tarjetas) {
          try {
            await Backend.db.functions.invoke('pagar-pedido', body: {
              'accion': 'borrar_tarjeta',
              'tarjeta_id': t['id'],
            });
          } catch (_) {}
        }
        await Backend.db.rpc('eliminar_mi_cuenta');
        // El usuario ya no existe en el servidor: cerrar la sesión allá puede
        // fallar, y lo que importa es que el celular la olvide.
        try {
          await _auth.signOut(scope: SignOutScope.local);
        } catch (_) {}
      });

  Future<void> salir() => intentar(() => _auth.signOut());

  Future<void> cambiarPassword(String nueva) =>
      intentar(() => _auth.updateUser(UserAttributes(password: nueva)));
}

final authRepositoryProvider = Provider<AuthRepository>((_) => const AuthRepository());

/// Id del usuario logueado. Cambia solo cuando alguien entra o sale, no con
/// cada renovacion del token (que ocurre sola cada hora).
final usuarioIdProvider = StreamProvider<String?>((ref) {
  final auth = Backend.db.auth;
  return auth.onAuthStateChange
      .map((e) => e.session?.user.id)
      .distinct();
});

/// La sesion completa: rol, local o rider asociado, estado de aprobacion.
final sesionActualProvider = FutureProvider<Sesion?>((ref) async {
  final uid = await ref.watch(usuarioIdProvider.future);
  if (uid == null) return null;

  final r = await intentar(() => Backend.db.rpc('mi_sesion'));
  if (r == null) {
    // Hay usuario de Auth pero no perfil: no deberia pasar (lo crea un
    // trigger). Se cierra la sesion en vez de dejar la app en un estado raro.
    await Backend.db.auth.signOut();
    return null;
  }
  return Sesion.fromJson(
    Map<String, dynamic>.from(r as Map),
    email: Backend.db.auth.currentUser?.email,
  );
});

/// Atajo sincronico para pantallas que solo se muestran con sesion.
final sesionProvider = Provider<Sesion>(
  (ref) => ref.watch(sesionActualProvider).value ?? Sesion.vacia,
);
