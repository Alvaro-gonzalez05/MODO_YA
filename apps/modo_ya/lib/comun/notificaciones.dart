import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Campanita con el globito de las no leídas. Abre la bandeja.
class MiCampanita extends ConsumerWidget {
  const MiCampanita({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sinLeer = ref.watch(noLeidasProvider);

    return MyPressable(
      onTap: () => mostrarMisNotificaciones(context, ref),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                color: MyColors.surfaceContainerLowest,
                shape: BoxShape.circle,
                border: Border.all(color: MyColors.outlineVariant),
              ),
            ),
            Icon(Symbols.notifications, size: size * 0.55, color: MyColors.onSurface, fill: sinLeer > 0 ? 1 : 0),
            if (sinLeer > 0)
              Positioned(
                top: -2,
                right: -2,
                child: MyPop(
                  disparador: sinLeer,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MyColors.error,
                      borderRadius: BorderRadius.circular(MyRadius.full),
                      border: Border.all(color: MyColors.surface, width: 1.5),
                    ),
                    child: Text(
                      sinLeer > 9 ? '9+' : '$sinLeer',
                      style: MyType.labelSm.copyWith(color: MyColors.onError, height: 1.1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// La bandeja: lo que le mandó la administración, lo no leído arriba en negrita.
Future<void> mostrarMisNotificaciones(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _Bandeja(),
  );
}

class _Bandeja extends ConsumerWidget {
  const _Bandeja();

  Future<void> _abrir(BuildContext context, WidgetRef ref, MiNotificacion n) async {
    if (!n.leida) {
      // Que no se pueda marcar no tiene que impedir leerla.
      try {
        await ref.read(notificacionesRepositoryProvider).marcarLeida(n.envioId);
        ref.invalidate(misNotificacionesProvider);
      } catch (_) {}
    }
    if (!context.mounted) return;
    final ruta = n.ruta;
    Navigator.of(context).pop();
    if (ruta != null) context.go(ruta);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notis = ref.watch(misNotificacionesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: MyColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(MyRadius.hero)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(MySpacing.lg),
          children: [
            Text('Novedades', style: MyType.headlineSm),
            const SizedBox(height: MySpacing.md),
            MyAsync(
              valor: notis,
              onReintentar: () => ref.invalidate(misNotificacionesProvider),
              datos: (lista) {
                if (lista.isEmpty) {
                  return const MyCard(
                    child: MyEmptyState(
                      icon: Symbols.notifications,
                      title: 'No hay novedades',
                      message: 'Acá te van a aparecer los avisos de MODO YA.',
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final n in lista) ...[
                      _Fila(notificacion: n, onTap: () => _abrir(context, ref, n)),
                      const SizedBox(height: MySpacing.xs),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: MySpacing.md),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.notificacion, required this.onTap});

  final MiNotificacion notificacion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notificacion;
    return MyCard(
      onTap: onTap,
      padding: const EdgeInsets.all(MySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: n.leida ? MyColors.surfaceContainerLowest : MyColors.primary,
              borderRadius: BorderRadius.circular(MyRadius.card),
            ),
            child: Icon(
              Symbols.notifications,
              fill: n.leida ? 0 : 1,
              size: 20,
              color: n.leida ? MyColors.secondary : MyColors.onPrimary,
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.titulo,
                  style: n.leida ? MyType.labelLg.copyWith(color: MyColors.secondary) : MyType.labelLg,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  n.cuerpo,
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 4,
                ),
                if (n.creadoEn != null) ...[
                  const SizedBox(height: MySpacing.xs),
                  Text(
                    Formato.fechaCorta(n.creadoEn!),
                    style: MyType.bodySm.copyWith(color: MyColors.outline),
                  ),
                ],
              ],
            ),
          ),
          if (n.ruta != null) Icon(Symbols.chevron_right, color: MyColors.outline),
        ],
      ),
    );
  }
}
