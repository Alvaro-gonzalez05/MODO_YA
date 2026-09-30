import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Los riders de confianza del local.
///
/// Marcar a alguien acá solo cambia **a quién se le ofrece primero** el envío.
/// Lo que se cobra y lo que cobra el rider no cambia en nada, y si el elegido
/// no contesta el envío sigue buscando entre los demás: el local no se queda
/// esperando porque su cadete dejó el celular en la mochila.
class MisRidersPage extends ConsumerWidget {
  const MisRidersPage({super.key});

  Future<void> _marcar(
    BuildContext context,
    WidgetRef ref,
    RiderParaElegir rider,
    bool mio,
  ) async {
    final comercioId = ref.read(sesionProvider).comercioId;
    if (comercioId == null) return;
    try {
      await ref
          .read(repartidoresRepositoryProvider)
          .marcarComoMio(comercioId, rider.id, mio: mio);
      ref.invalidate(ridersParaElegirProvider);
      if (context.mounted) {
        mostrarInfo(
          context,
          mio ? '${rider.nombre} ahora hace tus envíos primero' : '${rider.nombre} salió de tu lista',
        );
      }
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riders = ref.watch(ridersParaElegirProvider);

    return MyPagina(
      volver: () => context.go('/local/cuenta'),
      rotulo: 'Mi local',
      titulo: 'Mis riders',
      bajada: 'A los que marques acá se les ofrece primero tu envío.',
      anchoMaximo: 700,
      onRefresh: () async => ref.invalidate(ridersParaElegirProvider),
      children: [
        MyAsync(
          valor: riders,
          onReintentar: () => ref.invalidate(ridersParaElegirProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return const MyCard(
                child: MyEmptyState(
                  icon: Symbols.sports_motorsports,
                  title: 'Todavía no hay riders en Malargüe',
                  message: 'Cuando la administración apruebe riders, vas a poder '
                      'elegir cuáles hacen tus envíos.',
                ),
              );
            }

            final mios = lista.where((r) => r.esMio).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyCard(
                  padding: const EdgeInsets.all(MySpacing.sm),
                  child: Row(
                    children: [
                      Icon(Symbols.info, color: MyColors.tertiary),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Text(
                          mios.isEmpty
                              ? 'Hoy tus envíos los toma el rider libre más cercano.'
                              : mios.length == 1
                                  ? 'Tus envíos se le ofrecen primero a ${mios.first.nombre}. '
                                      'Si no puede, los toma cualquier otro.'
                                  : 'Tus envíos se les ofrecen primero a los ${mios.length} que marcaste. '
                                      'Si no pueden, los toma cualquier otro.',
                          style: MyType.bodySm.copyWith(color: MyColors.secondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.lg),
                for (final r in lista) ...[
                  _FilaRider(rider: r, onCambiar: (v) => _marcar(context, ref, r, v)),
                  const SizedBox(height: MySpacing.xs),
                ],
                const SizedBox(height: MySpacing.md),
                Text(
                  'Marcar un rider no cambia lo que cobrás ni lo que cobra él: el '
                  'envío se paga igual que siempre.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FilaRider extends StatelessWidget {
  const _FilaRider({required this.rider, required this.onCambiar});

  final RiderParaElegir rider;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      child: Row(
        children: [
          MyAvatar(nombre: rider.nombre, size: 40),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rider.nombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${rider.vehiculo.label} · ${rider.conectado ? "conectado" : "desconectado"}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
          if (rider.conectado) ...[
            const MyPulso(size: 8),
            const SizedBox(width: MySpacing.sm),
          ],
          Switch(value: rider.esMio, onChanged: onCambiar),
        ],
      ),
    );
  }
}
