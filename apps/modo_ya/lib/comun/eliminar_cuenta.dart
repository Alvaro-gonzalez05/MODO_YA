import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// El cliente elimina su cuenta desde la app (0073).
///
/// Dos pasos a propósito: el cartel cuenta qué se pierde y qué no, y después
/// hay que escribir ELIMINAR. Es lo único de la app que no tiene vuelta atrás,
/// y un toque de más en un celular no puede borrar una cuenta.
Future<void> eliminarMiCuenta(BuildContext context, WidgetRef ref) async {
  final seguir = await confirmar(
    context,
    titulo: 'Eliminar tu cuenta',
    mensaje: 'Se borran tu email, tu nombre, tu teléfono, tus direcciones y tus tarjetas '
        'guardadas. Si tenés MODO YA Plus, se da de baja y el mes pagado no se devuelve. '
        'Tus pedidos quedan registrados sin tus datos, porque son la facturación de los locales. '
        'No se puede deshacer.',
    aceptar: 'Continuar',
    peligroso: true,
  );
  if (!seguir || !context.mounted) return;

  final palabra = await pedirTexto(
    context,
    titulo: 'Confirmá que querés eliminarla',
    label: 'Escribí ELIMINAR',
    aceptar: 'Eliminar mi cuenta',
  );
  if (palabra == null || !context.mounted) return;
  if (palabra.trim().toUpperCase() != 'ELIMINAR') {
    mostrarError(context, 'No coincide: tu cuenta sigue como estaba.');
    return;
  }

  try {
    // Al terminar la sesión ya no existe y el router lleva solo a la entrada.
    await ref.read(authRepositoryProvider).eliminarMiCuenta();
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
  }
}

/// La administración da de baja a un cliente que lo pidió por la web
/// (/eliminar-cuenta). El pedido llega por correo, con el email de la cuenta.
Future<void> darDeBajaCliente(BuildContext context, WidgetRef ref) async {
  final email = await pedirTexto(
    context,
    titulo: 'Dar de baja a un cliente',
    label: 'Email de la cuenta',
    aceptar: 'Buscar y dar de baja',
    ayuda: 'Para los pedidos que llegan por el formulario de la web. Se borran sus datos '
        'y quedan sus pedidos, sin nombre ni dirección.',
  );
  if (email == null || email.trim().isEmpty || !context.mounted) return;

  final ok = await confirmar(
    context,
    titulo: 'Dar de baja a ${email.trim()}',
    mensaje: 'No se puede deshacer. Si tiene un pedido en curso, no se va a poder hasta que termine.',
    aceptar: 'Dar de baja',
    peligroso: true,
  );
  if (!ok || !context.mounted) return;

  try {
    await ref.read(cuentasRepositoryProvider).eliminarCliente(email);
    if (context.mounted) {
      await mostrarExito(
        context,
        titulo: 'Cuenta eliminada',
        mensaje: 'Contestale a ${email.trim()} que ya está hecho.',
        icono: Symbols.person_remove,
      );
    }
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
  }
}
