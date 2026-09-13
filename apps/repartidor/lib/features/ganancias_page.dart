import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// B8 - Ganancias e historial del cadete.
class GananciasPage extends ConsumerWidget {
  const GananciasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repartidor = ref.watch(repartidorActualProvider).value;
    final id = ref.watch(sesionProvider).repartidorId;

    // Del set demo tomamos los envios que hizo este cadete. Con Supabase esto
    // va a ser una consulta filtrada por repartidor y rango de fechas.
    final todos = ref.watch(enviosActivosProvider).value ?? const <Envio>[];
    final mios = todos.where((e) => e.repartidorId == id).toList();
    final ganado = mios.fold<int>(
      0,
      (s, e) => s + e.cotizacion.gananciaRepartidor,
    );

    return Column(
      children: [
        const MyTopBar(zona: 'Malargue urbano'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MySpacing.screenEdge,
              MySpacing.xs,
              MySpacing.screenEdge,
              MySpacing.dockClearance,
            ),
            children: [
              Text('Mis ganancias', style: MyType.headlineLg),
              const SizedBox(height: MySpacing.lg),

              MyHeroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const MyBadge('EN CURSO', tone: MyBadgeTone.dark),
                        const Spacer(),
                        const Icon(Symbols.payments,
                            size: 24, color: Colors.white),
                      ],
                    ),
                    const SizedBox(height: MySpacing.md),
                    Text(
                      Formato.pesos(ganado),
                      style: MyType.displayLg.copyWith(color: Colors.white),
                    ),
                    Text(
                      'Pendiente de liquidacion',
                      style: MyType.bodyMd.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: MySpacing.md),
              MyStatRow(
                tiles: [
                  MyStatTile(
                    icon: Symbols.package_2,
                    value: '${repartidor?.viajesCompletados ?? 0}',
                    label: 'Viajes totales',
                  ),
                  MyStatTile(
                    icon: Symbols.star,
                    value: (repartidor?.reputacion ?? 5).toStringAsFixed(1),
                    label: 'Reputacion',
                  ),
                  MyStatTile(
                    icon: Symbols.local_shipping,
                    value: '${mios.length}',
                    label: 'En curso',
                  ),
                ],
              ),

              const SizedBox(height: MySpacing.lg),
              MyCard(
                color: MyColors.secondaryContainer,
                shadows: const [],
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Symbols.info, size: 22,
                        color: MyColors.secondary),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Text(
                        'La frecuencia y el metodo de liquidacion todavia se '
                        'estan definiendo con la administracion.',
                        style: MyType.bodySm
                            .copyWith(color: MyColors.onSecondaryFixed),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: MySpacing.lg),
              Text('Historial', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),

              if (mios.isEmpty)
                const MyEmptyState(
                  icon: Symbols.receipt_long,
                  title: 'Todavia no hiciste viajes',
                  message: 'Conectate para empezar a recibir ofertas.',
                )
              else
                for (final e in mios) ...[
                  MyCard(
                    padding: const EdgeInsets.all(MySpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            color: MyColors.primaryFixed,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Symbols.package_2,
                              size: 21, color: MyColors.primary),
                        ),
                        const SizedBox(width: MySpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${e.codigo}', style: MyType.labelLg),
                              Text(
                                '${e.comercioNombre} - '
                                '${Formato.haceCuanto(e.creadoEn)}',
                                style: MyType.bodySm
                                    .copyWith(color: MyColors.secondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Formato.pesos(e.cotizacion.gananciaRepartidor),
                          style: MyType.headlineSm
                              .copyWith(color: MyColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.xs),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
