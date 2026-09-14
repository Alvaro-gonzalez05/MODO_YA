import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// Formulario corto que se abre encima de la pantalla: hoja inferior en el
/// celular, ventana centrada en la PC (una hoja de 1400 px de ancho no se lee).
Future<void> mostrarFormularioEmergente(
  BuildContext context, {
  required String titulo,
  required WidgetBuilder builder,
}) {
  if (context.esMovil) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (hoja) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(hoja).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MySpacing.screenEdge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titulo, style: MyType.headlineMd),
              const SizedBox(height: MySpacing.md),
              builder(hoja),
            ],
          ),
        ),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (dialogo) => Dialog(
      backgroundColor: MyColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MySpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(titulo, style: MyType.headlineMd)),
                  IconButton(onPressed: () => Navigator.pop(dialogo), icon: const Icon(Symbols.close), tooltip: 'Cerrar'),
                ],
              ),
              const SizedBox(height: MySpacing.md),
              builder(dialogo),
            ],
          ),
        ),
      ),
    ),
  );
}
