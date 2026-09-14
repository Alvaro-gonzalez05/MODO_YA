import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'marca.dart';

/// Pantalla de espera mientras se resuelve la sesion. Si la carga falla (sin
/// internet, por ejemplo), muestra el error con opcion de reintentar o salir.
class CargandoPage extends ConsumerWidget {
  const CargandoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionActualProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MarcaGrande(),
                const SizedBox(height: MySpacing.xxl),
                if (sesion.hasError) ...[
                  MyEmptyState(
                    icon: Symbols.cloud_off,
                    title: 'No pudimos conectarnos',
                    message: '${sesion.error}',
                  ),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(sesionActualProvider),
                    icon: const Icon(Symbols.refresh, size: 20),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(height: MySpacing.sm),
                  TextButton(
                    onPressed: () => ref.read(authRepositoryProvider).salir(),
                    child: const Text('Cerrar sesion'),
                  ),
                ] else
                  const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
