import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Splash del rider: pantalla negra de marca con el logo MODO YA RIDERS
/// mientras se resuelve la sesion.
class CargandoPage extends ConsumerWidget {
  const CargandoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionActualProvider);
    return Scaffold(
      backgroundColor: MyColors.dock,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(MySpacing.screenEdge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutBack,
                builder: (context, t, hijo) => Opacity(
                  opacity: t.clamp(0, 1),
                  child: Transform.scale(scale: 0.85 + 0.15 * t, child: hijo),
                ),
                child: const MyLogoMark(size: 220, variant: MyLogoVariant.riders),
              ),
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
                    ],
                  ),
                )
              else
                MyCargando(size: 36, padding: EdgeInsets.zero, colorPunto: MyColors.inverseOnSurface),
            ],
          ),
        ),
      ),
    );
  }
}
