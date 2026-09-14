import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Hoja para cambiar la contrasena. Importa sobre todo a locales y riders, que
/// arrancan con la temporal que les genero la administracion.
Future<void> mostrarCambiarPassword(BuildContext context, WidgetRef ref) async {
  final nueva = TextEditingController();
  final repetir = TextEditingController();
  final form = GlobalKey<FormState>();

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (s) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(s).bottom),
      child: Form(
        key: form,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(MySpacing.screenEdge),
          children: [
            Text('Cambiar contrasena', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.md),
            MyCampo(
              controller: nueva,
              label: 'Nueva contrasena',
              ocultar: true,
              validar: (t) => t.length < 8 ? 'Minimo 8 caracteres' : null,
            ),
            MyCampo(
              controller: repetir,
              label: 'Repetila',
              ocultar: true,
              validar: (t) => t != nueva.text ? 'No coincide' : null,
            ),
            MyBotonAccion(
              label: 'Guardar',
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                try {
                  await ref.read(authRepositoryProvider).cambiarPassword(nueva.text);
                  if (s.mounted) {
                    Navigator.pop(s);
                    mostrarAviso(context, 'Contrasena actualizada');
                  }
                } catch (e) {
                  if (s.mounted) mostrarError(s, e);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
  nueva.dispose();
  repetir.dispose();
}
