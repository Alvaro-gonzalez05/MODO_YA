import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Listado de servicios del cadete: lo que tiene en curso y lo que ya cerro.
class ServiciosPage extends ConsumerWidget {
  const ServiciosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(sesionProvider).repartidorId;
    final todos = ref.watch(enviosActivosProvider).value ?? const <Envio>[];
    final mios = todos.where((e) => e.repartidorId == id).toList();

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
              Text('Mis servicios', style: MyType.headlineLg),
              const SizedBox(height: MySpacing.xxs),
              Text(
                'Lo que tenes asignado ahora mismo',
                style: MyType.bodyMd.copyWith(color: MyColors.secondary),
              ),
              const SizedBox(height: MySpacing.lg),

              if (mios.isEmpty)
                const MyEmptyState(
                  icon: Symbols.local_shipping,
                  title: 'No tenes servicios asignados',
                  message:
                      'Cuando aceptes una oferta, el servicio va a aparecer '
                      'aca con todos sus pasos.',
                )
              else
                for (final e in mios) ...[
                  MyCard(
                    onTap: () => context.goNamed(
                      'servicio',
                      pathParameters: {'id': e.id},
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            MyOverline('Pedido #${e.codigo}'),
                            const Spacer(),
                            MyBadge(e.estado.label),
                          ],
                        ),
                        const SizedBox(height: MySpacing.sm),
                        MyRouteTimeline(
                          padding: const EdgeInsets.all(MySpacing.sm),
                          stops: [
                            MyRouteStop(
                              overline: 'Retiro',
                              title: e.comercioNombre,
                              subtitle: e.origen.calle,
                              icon: Symbols.restaurant,
                            ),
                            MyRouteStop(
                              overline: 'Entrega',
                              title: e.destino.calle,
                              icon: Symbols.home,
                              iconBackground: MyColors.dock,
                            ),
                          ],
                        ),
                        const SizedBox(height: MySpacing.sm),
                        Row(
                          children: [
                            Text(
                              'Tu ganancia',
                              style: MyType.labelMd
                                  .copyWith(color: MyColors.secondary),
                            ),
                            const Spacer(),
                            Text(
                              Formato.pesos(e.cotizacion.gananciaRepartidor),
                              style: MyType.headlineSm
                                  .copyWith(color: MyColors.primary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.sm),
                ],
            ],
          ),
        ),
      ],
    );
  }
}
