import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Riders: alta, suspension y estado en vivo.
class AdminRepartidoresPage extends ConsumerWidget {
  const AdminRepartidoresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riders = ref.watch(todosLosRepartidoresProvider);

    return ListView(
      padding: const EdgeInsets.all(MySpacing.xl),
      children: [
        AdminPageHeader(
          titulo: 'Riders',
          bajada: 'Alta de cuentas, suspension y quien esta conectado ahora',
          acciones: [
            SizedBox(
              width: 180,
              child: FilledButton.icon(
                onPressed: () => context.push('/admin/alta/rider'),
                icon: const Icon(Symbols.person_add, size: 20),
                label: const Text('Nuevo rider'),
              ),
            ),
          ],
        ),
        MyAsync(
          valor: riders,
          onReintentar: () => ref.invalidate(todosLosRepartidoresProvider),
          datos: (lista) => lista.isEmpty
              ? const MyEmptyState(
                  icon: Symbols.sports_motorsports,
                  title: 'Todavia no hay riders',
                  message: 'Crea el primero con "Nuevo rider". Entra con esos datos en la app MODO YA Rider.',
                )
              : Column(
                  children: [
                    for (final r in lista) ...[
                      _FilaRider(rider: r),
                      const SizedBox(height: MySpacing.xs),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilaRider extends ConsumerWidget {
  const _FilaRider({required this.rider});

  final Repartidor rider;

  Future<void> _cambiar(BuildContext context, WidgetRef ref, EstadoAprobacion estado) async {
    String? motivo;
    if (estado == EstadoAprobacion.suspendido) {
      motivo = await pedirTexto(
        context,
        titulo: 'Suspender a ${rider.nombre}',
        label: 'Motivo',
        aceptar: 'Suspender',
      );
      if (motivo == null) return;
    }
    try {
      await ref.read(repartidoresRepositoryProvider).cambiarAprobacion(rider.id, estado, motivo: motivo);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operando = rider.aprobacion.puedeOperar;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: MySpacing.md,
        runSpacing: MySpacing.sm,
        children: [
          SizedBox(
            width: 300,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: rider.conectado ? MyColors.successContainer : MyColors.primaryFixed,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.sports_motorsports,
                    size: 23,
                    color: rider.conectado ? MyColors.success : MyColors.primary,
                  ),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rider.nombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${rider.vehiculo.label} - ${rider.telefono}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          MyBadge(rider.aprobacion.label, tone: tonoAprobacion(rider.aprobacion)),
          MyBadge(
            rider.ocupado ? 'En servicio' : (rider.conectado ? 'Conectado' : 'Desconectado'),
            tone: rider.ocupado
                ? MyBadgeTone.ember
                : (rider.conectado ? MyBadgeTone.success : MyBadgeTone.info),
            dot: true,
          ),
          Text('${rider.viajesCompletados} viajes', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          operando
              ? TextButton(
                  onPressed: () => _cambiar(context, ref, EstadoAprobacion.suspendido),
                  child: const Text('Suspender'),
                )
              : FilledButton(
                  onPressed: () => _cambiar(context, ref, EstadoAprobacion.aprobado),
                  style: FilledButton.styleFrom(minimumSize: const Size(120, 40), textStyle: MyType.labelLg),
                  child: Text(rider.aprobacion == EstadoAprobacion.pendiente ? 'Aprobar' : 'Reactivar'),
                ),
        ],
      ),
    );
  }
}
