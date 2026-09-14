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
        () => _auth.signInWithPassword(email: email.trim(), password: password),
      );

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
