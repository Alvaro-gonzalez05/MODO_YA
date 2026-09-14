import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/envio_tile.dart';

/// Inicio del local (A4): pedir un rider, pedidos por atender y envios de hoy.
class InicioComercioPage extends ConsumerWidget {
  const InicioComercioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercio = ref.watch(comercioActualProvider).value;
    final envios = ref.watch(enviosDelComercioProvider);
    final pedidos = ref.watch(pedidosDelComercioProvider).value ?? const <Pedido>[];
    final tarifario = ref.watch(tarifarioProvider).value;

    final nuevos = pedidos.where((p) => p.estado == EstadoPedido.pagado).length;
    final enCocina = pedidos.where((p) => p.estado.esParaElLocal && p.estado != EstadoPedido.pagado).length;

    return Column(
      children: [
        MyTopBar(zona: comercio?.nombre ?? 'Mi local', onPerfil: () => context.go('/local/cuenta')),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(comercioActualProvider);
              ref.invalidate(tarifarioProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance,
              ),
              children: [
                if (comercio != null) _EstadoLocal(comercio: comercio),
                const SizedBox(height: MySpacing.md),

                if (nuevos > 0 || enCocina > 0) ...[
                  MyCard(
                    onTap: () => context.go('/local/pedidos'),
                    color: nuevos > 0 ? MyColors.primaryFixed : MyColors.surfaceContainerLowest,
                    child: Row(
                      children: [
                        const Icon(Symbols.notifications_active, color: MyColors.primary, size: 28),
                        const SizedBox(width: MySpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nuevos > 0
                                    ? '$nuevos pedido${nuevos == 1 ? '' : 's'} nuevo${nuevos == 1 ? '' : 's'}'
                                    : '$enCocina en preparacion',
                                style: MyType.headlineSm,
                              ),
                              Text(
                                nuevos > 0 ? 'Aceptalos para que el cliente sepa que los estas preparando' : 'Marcalos listos para que salga el rider',
                                style: MyType.bodySm.copyWith(color: MyColors.secondary),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Symbols.chevron_right, color: MyColors.primary),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.md),
                ],

                MyHeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MyBadge('CADETERIA', tone: MyBadgeTone.dark, icon: Symbols.bolt),
                      const SizedBox(height: MySpacing.md),
                      Text('Pedir un rider', style: MyType.headlineLg.copyWith(color: Colors.white)),
                      Text(
                        'Para pedidos que te llegan por telefono o WhatsApp.',
                        style: MyType.bodyMd.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: MySpacing.md),
                      if (tarifario != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(Formato.pesos(tarifario.precioBase),
                                style: MyType.displayLg.copyWith(color: Colors.white)),
                            const SizedBox(width: MySpacing.xxs),
                            Text('hasta ${Formato.km(tarifario.kmIncluidos)}',
                                style: MyType.bodyMd.copyWith(color: Colors.white70)),
                          ],
                        ),
                      const SizedBox(height: MySpacing.md),
                      SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: (comercio?.puedePedirEnvios ?? false) ? () => context.push('/local/envio/nuevo') : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: MyColors.primary,
                            disabledBackgroundColor: Colors.white24,
                          ),
                          icon: const Text('Pedir ahora'),
                          label: const Icon(Symbols.arrow_forward, size: 20),
                        ),
                      ),
                      if (comercio != null && !comercio.direccion.tieneCoordenadas)
                        Padding(
                          padding: const EdgeInsets.only(top: MySpacing.xs),
                          child: Text(
                            'Primero marca la ubicacion del local en Cuenta.',
                            style: MyType.bodySm.copyWith(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: MySpacing.xl),
                MySectionHeader(
                  title: 'Envios de hoy',
                  subtitle: 'Se actualizan solos',
                  actionLabel: 'Ver historial',
                  onAction: () => context.push('/local/historial'),
                ),
                const SizedBox(height: MySpacing.md),
                MyAsync(
                  valor: envios,
                  datos: (lista) {
                    final hoy = DateTime.now();
                    final deHoy = lista
                        .where((e) =>
                            e.estado.esActivo ||
                            (e.creadoEn.year == hoy.year && e.creadoEn.month == hoy.month && e.creadoEn.day == hoy.day))
                        .toList();
                    if (deHoy.isEmpty) {
                      return const MyEmptyState(
                        icon: Symbols.package_2,
                        title: 'Sin envios hoy',
                        message: 'Los envios de la cadeteria y los de pedidos de la app aparecen aca.',
                      );
                    }
                    return Column(
                      children: [
                        for (final e in deHoy) ...[
                          EnvioTile(envio: e, onTap: () => context.push('/local/envio/${e.id}')),
                          const SizedBox(height: MySpacing.sm),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Abierto / pausado, con el interruptor a mano: es lo que mas se toca en un
/// dia de mucho trabajo.
class _EstadoLocal extends ConsumerWidget {
  const _EstadoLocal({required this.comercio});

  final Comercio comercio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyCard(
      padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: comercio.abierto ? MyColors.success : MyColors.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comercio.abierto ? 'Recibiendo pedidos' : 'Cerrado para la app', style: MyType.labelLg),
                Text(
                  comercio.aceptaPedidos
                      ? (comercio.abierto ? 'Los clientes te ven abierto' : 'Fuera de tu horario')
                      : 'Pausado a mano',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
          Switch(
            value: comercio.aceptaPedidos,
            onChanged: (v) async {
              try {
                await ref.read(comerciosRepositoryProvider).actualizar(comercio.id, aceptaPedidos: v);
                ref.invalidate(comercioActualProvider);
              } catch (e) {
                if (context.mounted) mostrarError(context, e);
              }
            },
          ),
        ],
      ),
    );
  }
}
