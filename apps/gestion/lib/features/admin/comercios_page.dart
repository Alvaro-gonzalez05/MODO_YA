import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// C3 - Gestion de comercios: aprobar, suspender y revisar suscripcion.
class AdminComerciosPage extends ConsumerWidget {
  const AdminComerciosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercios = ref.watch(todosLosComerciosProvider);

    return comercios.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (lista) {
        final pendientes = lista
            .where((c) => c.aprobacion == EstadoAprobacion.pendiente)
            .toList();
        final resto = lista
            .where((c) => c.aprobacion != EstadoAprobacion.pendiente)
            .toList();

        return ListView(
          padding: const EdgeInsets.all(MySpacing.xl),
          children: [
            const AdminPageHeader(
              titulo: 'Comercios',
              bajada: 'Alta, aprobacion, suspension y estado de suscripcion',
            ),
            if (pendientes.isNotEmpty) ...[
              Text('Esperando aprobacion', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),
              for (final c in pendientes) ...[
                _FilaComercio(comercio: c),
                const SizedBox(height: MySpacing.xs),
              ],
              const SizedBox(height: MySpacing.lg),
            ],
            Text('Todos los comercios', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.sm),
            for (final c in resto) ...[
              _FilaComercio(comercio: c),
              const SizedBox(height: MySpacing.xs),
            ],
          ],
        );
      },
    );
  }
}

class _FilaComercio extends ConsumerWidget {
  const _FilaComercio({required this.comercio});

  final Comercio comercio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendiente = comercio.aprobacion == EstadoAprobacion.pendiente;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: MyColors.secondaryContainer,
              borderRadius: BorderRadius.circular(MyRadius.md),
            ),
            child: const Icon(Symbols.storefront,
                size: 23, color: MyColors.primary),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comercio.nombre, style: MyType.headlineSm),
                Text(
                  '${comercio.rubro} - ${comercio.direccion.calle}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              '${comercio.enviosDelMes} envios',
              style: MyType.bodyMd.copyWith(color: MyColors.secondary),
            ),
          ),
          MyBadge(
            comercio.suscripcion.label,
            tone: switch (comercio.suscripcion) {
              EstadoSuscripcion.activa => MyBadgeTone.success,
              EstadoSuscripcion.porVencer => MyBadgeTone.ember,
              _ => MyBadgeTone.danger,
            },
          ),
          const SizedBox(width: MySpacing.sm),
          MyBadge(
            comercio.aprobacion.label,
            tone: comercio.aprobacion.puedeOperar
                ? MyBadgeTone.success
                : MyBadgeTone.danger,
          ),
          const SizedBox(width: MySpacing.sm),
          if (pendiente)
            FilledButton(
              onPressed: () => ref
                  .read(comerciosRepositoryProvider)
                  .actualizarAprobacion(
                    comercio.id,
                    EstadoAprobacion.aprobado,
                  ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(110, 40),
                textStyle: MyType.labelLg,
              ),
              child: const Text('Aprobar'),
            )
          else
            TextButton(
              onPressed: () => ref
                  .read(comerciosRepositoryProvider)
                  .actualizarAprobacion(
                    comercio.id,
                    comercio.aprobacion == EstadoAprobacion.suspendido
                        ? EstadoAprobacion.aprobado
                        : EstadoAprobacion.suspendido,
                  ),
              child: Text(
                comercio.aprobacion == EstadoAprobacion.suspendido
                    ? 'Reactivar'
                    : 'Suspender',
              ),
            ),
        ],
      ),
    );
  }
}
