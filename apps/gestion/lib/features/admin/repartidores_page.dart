import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// C4 - Gestion y validacion de cadetes.
class AdminRepartidoresPage extends ConsumerWidget {
  const AdminRepartidoresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repartidores = ref.watch(todosLosRepartidoresProvider);

    return repartidores.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (lista) => ListView(
        padding: const EdgeInsets.all(MySpacing.xl),
        children: [
          const AdminPageHeader(
            titulo: 'Cadetes',
            bajada:
                'Validacion de documentacion, aprobacion y control de desempeno',
          ),
          for (final r in lista) ...[
            _FilaRepartidor(repartidor: r),
            const SizedBox(height: MySpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _FilaRepartidor extends ConsumerWidget {
  const _FilaRepartidor({required this.repartidor});

  final Repartidor repartidor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendiente = repartidor.aprobacion == EstadoAprobacion.pendiente;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: MyColors.primaryFixed,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Symbols.sports_motorsports,
                        size: 23, color: MyColors.primary),
                  ),
                  if (repartidor.conectado)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: MyColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MyColors.surfaceContainerLowest,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(repartidor.nombre, style: MyType.headlineSm),
                    Text(
                      '${repartidor.vehiculo.label} - ${repartidor.telefono}',
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Symbols.star,
                        size: 17, color: MyColors.primary, fill: 1),
                    const SizedBox(width: MySpacing.xxs),
                    Text(
                      repartidor.reputacion.toStringAsFixed(1),
                      style: MyType.labelLg,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  '${repartidor.viajesCompletados} viajes',
                  style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                ),
              ),
              MyBadge(
                repartidor.conectado ? 'Conectado' : 'Desconectado',
                tone: repartidor.conectado
                    ? MyBadgeTone.success
                    : MyBadgeTone.info,
                dot: true,
              ),
              const SizedBox(width: MySpacing.sm),
              MyBadge(
                repartidor.aprobacion.label,
                tone: repartidor.aprobacion.puedeOperar
                    ? MyBadgeTone.success
                    : MyBadgeTone.danger,
              ),
              const SizedBox(width: MySpacing.sm),
              if (pendiente)
                FilledButton(
                  onPressed: () => ref
                      .read(repartidoresRepositoryProvider)
                      .actualizarAprobacion(
                        repartidor.id,
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
                      .read(repartidoresRepositoryProvider)
                      .actualizarAprobacion(
                        repartidor.id,
                        repartidor.aprobacion == EstadoAprobacion.suspendido
                            ? EstadoAprobacion.aprobado
                            : EstadoAprobacion.suspendido,
                      ),
                  child: Text(
                    repartidor.aprobacion == EstadoAprobacion.suspendido
                        ? 'Reactivar'
                        : 'Suspender',
                  ),
                ),
            ],
          ),
          if (pendiente) ...[
            const Divider(height: MySpacing.xl),
            Row(
              children: [
                const Icon(Symbols.description,
                    size: 18, color: MyColors.secondary),
                const SizedBox(width: MySpacing.xs),
                Text(
                  'Documentacion a validar: ',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
                Expanded(
                  child: Wrap(
                    spacing: MySpacing.xs,
                    runSpacing: MySpacing.xxs,
                    children: [
                      for (final doc
                          in repartidor.vehiculo.documentacionRequerida)
                        MyBadge(doc, tone: MyBadgeTone.info),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
