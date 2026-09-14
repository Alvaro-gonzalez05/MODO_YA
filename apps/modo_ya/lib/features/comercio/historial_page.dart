import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/envio_tile.dart';

/// Historial de envios del local (A11).
class HistorialPage extends ConsumerWidget {
  const HistorialPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envios = ref.watch(enviosDelComercioProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Symbols.arrow_back), onPressed: () => context.pop()),
        title: const Text('Historial de envios'),
      ),
      body: MyAsync(
        valor: envios,
        onReintentar: () => ref.invalidate(enviosDelComercioProvider),
        datos: (todos) {
          final entregados = todos.where((e) => e.estado == EstadoEnvio.entregado).toList();
          final pagueYo = entregados
              .where((e) => e.quienPaga == QuienPaga.comercio && e.pedidoId == null)
              .fold<int>(0, (s, e) => s + e.total);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(MySpacing.screenEdge),
                children: [
                  MyStatRow(tiles: [
                    MyStatTile(icon: Symbols.package_2, value: '${todos.length}', label: 'Envios'),
                    MyStatTile(icon: Symbols.check_circle, value: '${entregados.length}', label: 'Entregados'),
                    MyStatTile(icon: Symbols.payments, value: Formato.pesos(pagueYo), label: 'Pagaste vos'),
                  ]),
                  const SizedBox(height: MySpacing.sm),
                  Text(
                    'Ultimos 100 envios.',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  ),
                  const SizedBox(height: MySpacing.md),
                  if (todos.isEmpty)
                    const MyEmptyState(
                      icon: Symbols.receipt_long,
                      title: 'Todavia no hay envios',
                      message: 'Se arma solo a medida que pedis riders.',
                    )
                  else
                    for (final e in todos) ...[
                      EnvioTile(envio: e, onTap: () => context.push('/local/envio/${e.id}')),
                      const SizedBox(height: MySpacing.sm),
                    ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
