import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Usuario (email) con el que entra un local o un rider. Solo admin.
final usuarioDeCuentaProvider = FutureProvider.autoDispose.family<String?, ({String? comercio, String? rider})>(
  (ref, cuenta) => ref.read(cuentasRepositoryProvider).usuarioDe(
        comercioId: cuenta.comercio,
        repartidorId: cuenta.rider,
      ),
);

/// Muestra el usuario y la contraseña temporal de una cuenta recién creada o
/// restablecida, con botones para copiarlos o mandarlos por WhatsApp.
///
/// La contraseña se ve una sola vez: no queda guardada en ningún lado.
Future<void> mostrarCredenciales(
  BuildContext context, {
  required String titulo,
  required AltaCuenta alta,
  required bool esRider,
  String? telefono,
}) {
  final app = esRider ? 'MODO YA Rider' : 'MODO YA';
  final mensaje = 'Tus datos para entrar a $app:\n'
      'Usuario: ${alta.email}\n'
      'Contraseña: ${alta.passwordTemporal ?? ''}\n'
      'Cuando entres, cambiá la contraseña desde tu cuenta.';

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      icon: const Icon(Symbols.check_circle, color: MyColors.success, size: 44, fill: 1),
      title: Text(titulo),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pasale estos datos. La contraseña se muestra una sola vez: copiala o mandala ahora.',
              style: MyType.bodyMd,
            ),
            const SizedBox(height: MySpacing.md),
            Container(
              padding: const EdgeInsets.all(MySpacing.md),
              decoration: BoxDecoration(
                color: MyColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(MyRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MyOverline('Usuario'),
                  const SizedBox(height: 2),
                  SelectableText(alta.email, style: MyType.labelLg),
                  const SizedBox(height: MySpacing.sm),
                  const MyOverline('Contraseña temporal'),
                  const SizedBox(height: 2),
                  SelectableText(
                    alta.passwordTemporal ?? '',
                    style: MyType.headlineMd.copyWith(color: MyColors.tertiary, letterSpacing: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MySpacing.sm),
            Text(
              esRider ? 'El rider entra con estos datos en la app MODO YA Rider.' : 'El local entra con estos datos en la app MODO YA.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        Wrap(
          spacing: MySpacing.xs,
          children: [
            MyBoton(
              label: 'Copiar',
              icon: Symbols.content_copy,
              tipo: MyBotonTipo.secundario,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: mensaje));
                if (c.mounted) mostrarAviso(c, 'Copiado');
              },
            ),
            MyBoton(
              label: 'WhatsApp',
              icon: Symbols.chat,
              tipo: MyBotonTipo.secundario,
              onPressed: () {
                final numero = (telefono ?? '').replaceAll(RegExp(r'\D'), '');
                final destino = numero.isEmpty ? '' : (numero.startsWith('54') ? numero : '549$numero');
                launchUrl(
                  Uri.parse('https://wa.me/$destino?text=${Uri.encodeComponent(mensaje)}'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
          ],
        ),
        MyBoton(label: 'Listo', onPressed: () => Navigator.pop(c)),
      ],
    ),
  );
}

/// Bloque "Datos de acceso" de las fichas de local y rider: usuario y botón
/// para generar una contraseña nueva.
class DatosDeAcceso extends ConsumerWidget {
  const DatosDeAcceso({super.key, this.comercioId, this.repartidorId, required this.nombre, this.telefono});

  final String? comercioId;
  final String? repartidorId;
  final String nombre;
  final String? telefono;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuario = ref.watch(usuarioDeCuentaProvider((comercio: comercioId, rider: repartidorId)));

    return Container(
      padding: const EdgeInsets.all(MySpacing.md),
      decoration: BoxDecoration(
        color: MyColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MyRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MyOverline('Datos de acceso'),
          const SizedBox(height: MySpacing.xs),
          Row(
            children: [
              const Icon(Symbols.alternate_email, size: 18, color: MyColors.secondary),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: SelectableText(
                  usuario.value ?? (usuario.hasError ? 'No se pudo leer' : '…'),
                  style: MyType.labelLg,
                ),
              ),
              if (usuario.value != null)
                IconButton(
                  tooltip: 'Copiar usuario',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Symbols.content_copy, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: usuario.value!));
                    if (context.mounted) mostrarAviso(context, 'Usuario copiado');
                  },
                ),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: MyBoton(
              label: 'Nueva contraseña',
              icon: Symbols.lock_reset,
              tipo: MyBotonTipo.oscuro,
              onPressed: () async {
                final ok = await confirmar(
                  context,
                  titulo: 'Generar contraseña nueva',
                  mensaje: 'La contraseña actual de $nombre deja de funcionar. '
                      'Vas a tener que pasarle la nueva.',
                  aceptar: 'Generar',
                );
                if (!ok) return;
                try {
                  final alta = await ref.read(cuentasRepositoryProvider).restablecerPassword(
                        comercioId: comercioId,
                        repartidorId: repartidorId,
                      );
                  if (context.mounted) {
                    await mostrarCredenciales(
                      context,
                      titulo: 'Contraseña nueva',
                      alta: alta,
                      esRider: repartidorId != null,
                      telefono: telefono,
                    );
                  }
                } catch (e) {
                  if (context.mounted) mostrarError(context, e);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
