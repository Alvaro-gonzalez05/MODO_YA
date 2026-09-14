import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'cambiar_password.dart';

/// Acciones del menú del usuario, iguales para los tres tipos de cuenta.
List<MyAccionUsuario> accionesDeUsuario(BuildContext context, WidgetRef ref) => [
      MyAccionUsuario(
        icon: Symbols.key,
        label: 'Cambiar contraseña',
        onTap: () => mostrarCambiarPassword(context, ref),
      ),
      MyAccionUsuario(
        icon: Symbols.logout,
        label: 'Cerrar sesión',
        peligrosa: true,
        onTap: () => cerrarSesion(context, ref),
      ),
    ];

Future<void> cerrarSesion(BuildContext context, WidgetRef ref) async {
  final ok = await confirmar(
    context,
    titulo: 'Cerrar sesión',
    mensaje: 'Vas a tener que volver a entrar con tu usuario y contraseña.',
    aceptar: 'Cerrar sesión',
    peligroso: true,
  );
  if (!ok) return;
  try {
    await ref.read(authRepositoryProvider).salir();
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
  }
}

/// Versión para mostrar al pie de la barra lateral.
String? get versionVisible => Entorno.version.isEmpty ? null : Entorno.version;
