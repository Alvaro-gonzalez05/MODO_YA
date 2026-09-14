import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'formulario_emergente.dart';

/// Cambiar la contraseña. Importa sobre todo a locales y riders, que arrancan
/// con la temporal que les generó la administración.
Future<void> mostrarCambiarPassword(BuildContext context, WidgetRef ref) async {
  final nueva = TextEditingController();
  final repetir = TextEditingController();
  final form = GlobalKey<FormState>();

  await mostrarFormularioEmergente(
    context,
    titulo: 'Cambiar contraseña',
    builder: (hoja) => Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyCampo(
            controller: nueva,
            label: 'Nueva contraseña',
            icon: Symbols.lock,
            ocultar: true,
            validar: (t) => t.length < 8 ? 'Mínimo 8 caracteres' : null,
          ),
          MyCampo(
            controller: repetir,
            label: 'Repetila',
            icon: Symbols.lock,
            ocultar: true,
            validar: (t) => t != nueva.text ? 'No coincide' : null,
          ),
          const SizedBox(height: MySpacing.xs),
          MyBotonAccion(
            label: 'Guardar',
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              try {
                await ref.read(authRepositoryProvider).cambiarPassword(nueva.text);
                if (hoja.mounted) {
                  Navigator.pop(hoja);
                  if (context.mounted) mostrarAviso(context, 'Contraseña actualizada');
                }
              } catch (e) {
                if (hoja.mounted) mostrarError(hoja, e);
              }
            },
          ),
        ],
      ),
    ),
  );
  nueva.dispose();
  repetir.dispose();
}
