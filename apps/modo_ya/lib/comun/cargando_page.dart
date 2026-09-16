import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'marca.dart';

/// Splash: pantalla negra de marca (la unica negra de la app, como en la
/// referencia) mientras se resuelve la sesion. Si la carga falla (sin
/// internet, por ejemplo), muestra el error con opcion de reintentar o salir.
class CargandoPage extends ConsumerWidget {
  const CargandoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionActualProvider);

    return Scaffold(
      backgroundColor: MyColors.dock,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MarcaGrande(oscura: true, tamano: 220),
                const SizedBox(height: MySpacing.xxl),
                if (sesion.hasError)
                  MyApareceEn(
                    child: Column(
                      children: [
                        Text('No pudimos conectarnos', style: MyType.headlineSm.copyWith(color: MyColors.inverseOnSurface)),
                        const SizedBox(height: MySpacing.xs),
                        Text(
                          '${sesion.error}',
                          textAlign: TextAlign.center,
                          style: MyType.bodySm.copyWith(color: MyColors.inverseOnSurface.withValues(alpha: 0.7)),
                        ),
                        const SizedBox(height: MySpacing.lg),
                        FilledButton.icon(
                          onPressed: () => ref.invalidate(sesionActualProvider),
                          icon: const Icon(Symbols.refresh, size: 20),
                          label: const Text('Reintentar'),
                        ),
                        const SizedBox(height: MySpacing.sm),
                        TextButton(
                          onPressed: () => ref.read(authRepositoryProvider).salir(),
                          style: TextButton.styleFrom(foregroundColor: MyColors.inverseOnSurface),
                          child: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                  )
                else
                  const MyCargando(size: 36, padding: EdgeInsets.zero, colorPunto: MyColors.inverseOnSurface),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
