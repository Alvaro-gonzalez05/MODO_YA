import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/envio_tile.dart';

/// A11 - Historial de envios.
///
/// Con [soloActivos] en true es la pestana "Envios" del dock (lo que esta en
/// la calle ahora); en false, el historial completo con el resumen del periodo.
class HistorialPage extends ConsumerWidget {
  const HistorialPage({super.key, this.soloActivos = false});

  final bool soloActivos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enviosAsync = ref.watch(enviosDelComercioProvider);

    return Column(
      children: [
        MyTopBar(onPerfil: () => context.goNamed('comercioSuscripcion')),
        Expanded(
          child: enviosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (todos) {
              final envios = soloActivos
                  ? todos.where((e) => e.estado.esActivo).toList()
                  : todos;

              final entregados =
                  todos.where((e) => e.estado == EstadoEnvio.entregado);
              final gastado = entregados
                  .where((e) => e.quienPaga == QuienPaga.comercio)
                  .fold<int>(0, (sum, e) => sum + e.total);

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  MySpacing.screenEdge,
                  MySpacing.xs,
                  MySpacing.screenEdge,
                  MySpacing.dockClearance,
                ),
                children: [
                  Text(
                    soloActivos ? 'Envios en curso' : 'Historial',
                    style: MyType.headlineLg,
                  ),
                  const SizedBox(height: MySpacing.xxs),
                  Text(
                    soloActivos
                        ? 'Lo que esta en la calle ahora mismo'
                        : 'Todos tus envios, importes y comprobantes',
                    style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                  ),
                  const SizedBox(height: MySpacing.lg),

                  if (!soloActivos) ...[
                    MyStatRow(
                      tiles: [
                        MyStatTile(
                          icon: Symbols.package_2,
                          value: '${todos.length}',
                          label: 'Envios',
                        ),
                        MyStatTile(
                          icon: Symbols.check_circle,
                          value: '${entregados.length}',
                          label: 'Entregados',
                        ),
                        MyStatTile(
                          icon: Symbols.payments,
                          value: Formato.pesos(gastado),
                          label: 'Pagaste vos',
                        ),
                      ],
                    ),
                    const SizedBox(height: MySpacing.lg),
                  ],

                  if (envios.isEmpty)
                    MyEmptyState(
                      icon: Symbols.package_2,
                      title: soloActivos
                          ? 'No hay envios en curso'
                          : 'Todavia no hay envios',
                      message: soloActivos
                          ? 'Cuando pidas un cadete lo vas a ver aca.'
                          : 'Tu historial se arma solo a medida que pedis.',
                      action: FilledButton(
                        onPressed: () => context.goNamed('crearEnvio'),
                        child: const Text('Pedir un cadete'),
                      ),
                    )
                  else
                    for (final envio in envios) ...[
                      EnvioTile(
                        envio: envio,
                        onTap: () => context.goNamed(
                          'seguimiento',
                          pathParameters: {'id': envio.id},
                        ),
                      ),
                      const SizedBox(height: MySpacing.sm),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
