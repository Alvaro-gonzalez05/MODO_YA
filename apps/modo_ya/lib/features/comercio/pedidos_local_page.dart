import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Pedidos de la app que le llegan al local, en vivo.
///
/// Flujo: Nuevo -> Aceptar -> En preparacion -> Listo (sale a buscar rider) ->
/// el rider lo retira y el resto lo sigue el cliente.
class PedidosLocalPage extends ConsumerStatefulWidget {
  const PedidosLocalPage({super.key});

  @override
  ConsumerState<PedidosLocalPage> createState() => _PedidosLocalPageState();
}

enum _Filtro {
  activos('Por atender'),
  enCamino('En camino'),
  cerrados('Cerrados');

  const _Filtro(this.label);
  final String label;

  bool incluye(Pedido p) => switch (this) {
        activos => p.estado.esParaElLocal,
        enCamino => p.estado == EstadoPedido.enCamino,
        cerrados => p.estado.esFinal,
      };
}

class _PedidosLocalPageState extends ConsumerState<PedidosLocalPage> {
  var _filtro = _Filtro.activos;

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosDelComercioProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Pedidos'),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.screenEdge, vertical: MySpacing.xxs),
            children: [
              for (final f in _Filtro.values) ...[
                MyChip(f.label, selected: f == _filtro, onTap: () => setState(() => _filtro = f)),
                const SizedBox(width: MySpacing.xs),
              ],
            ],
          ),
        ),
        Expanded(
          child: MyAsync(
            valor: pedidos,
            onReintentar: () => ref.invalidate(pedidosDelComercioProvider),
            datos: (lista) {
              final visibles = lista.where(_filtro.incluye).toList();
              if (_filtro == _Filtro.activos) {
                // Los nuevos primero, y dentro de cada grupo el mas viejo arriba:
                // es el que el cliente lleva mas tiempo esperando.
                visibles.sort((a, b) {
                  final orden = a.estado.index.compareTo(b.estado.index);
                  return orden != 0 ? orden : a.creadoEn.compareTo(b.creadoEn);
                });
              }
              if (visibles.isEmpty) {
                return MyEmptyState(
                  icon: Symbols.receipt_long,
                  title: _filtro == _Filtro.activos ? 'No hay pedidos por atender' : 'Nada por aca',
                  message: _filtro == _Filtro.activos
                      ? 'Cuando un cliente te haga un pedido va a sonar aca y en el inicio.'
                      : 'Los pedidos aparecen aca a medida que avanzan.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  MySpacing.screenEdge, MySpacing.sm, MySpacing.screenEdge, MySpacing.dockClearance,
                ),
                itemCount: visibles.length,
                separatorBuilder: (_, _) => const SizedBox(height: MySpacing.sm),
                itemBuilder: (_, i) => _TarjetaPedido(pedido: visibles[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TarjetaPedido extends ConsumerWidget {
  const _TarjetaPedido({required this.pedido});

  final Pedido pedido;

  Future<void> _hacer(BuildContext context, Future<void> Function() accion) async {
    try {
      await accion();
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(pedidosRepositoryProvider);
    final esNuevo = pedido.estado == EstadoPedido.pagado;

    return MyCard(
      color: esNuevo ? MyColors.primaryFixed : MyColors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MyBadge(pedido.codigo, tone: MyBadgeTone.dark),
              const SizedBox(width: MySpacing.xs),
              MyBadge(pedido.estado.label, tone: esNuevo ? MyBadgeTone.ember : MyBadgeTone.info, dot: esNuevo),
              const Spacer(),
              Text(Formato.haceCuanto(pedido.creadoEn), style: MyType.bodySm.copyWith(color: MyColors.secondary)),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          Text(pedido.clienteNombre ?? 'Cliente', style: MyType.headlineSm),
          Text(
            [pedido.entrega.calle, if (pedido.entrega.referencia != null) pedido.entrega.referencia!].join(' - '),
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          const Divider(height: MySpacing.lg),
          for (final item in pedido.items)
            Padding(
              padding: const EdgeInsets.only(bottom: MySpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 32, child: Text('${item.cantidad}x', style: MyType.labelLg.copyWith(color: MyColors.primary))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.nombreProducto, style: MyType.labelLg),
                        for (final o in item.opciones)
                          Text(o, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                        if (item.nota != null)
                          Text('"${item.nota}"', style: MyType.bodySm.copyWith(fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  Text(Formato.pesos(item.subtotal), style: MyType.labelMd),
                ],
              ),
            ),
          if (pedido.nota != null) ...[
            const SizedBox(height: MySpacing.xxs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MySpacing.sm),
              decoration: BoxDecoration(
                color: MyColors.secondaryContainer,
                borderRadius: BorderRadius.circular(MyRadius.md),
              ),
              child: Text('Nota: ${pedido.nota}', style: MyType.bodySm),
            ),
          ],
          const SizedBox(height: MySpacing.sm),
          Row(
            children: [
              Text('Total', style: MyType.labelLg),
              const Spacer(),
              Text(Formato.pesos(pedido.subtotal), style: MyType.headlineSm.copyWith(color: MyColors.primary)),
            ],
          ),
          Text(
            'Productos. El envio (${Formato.pesos(pedido.costoEnvio)}) lo cobra MODO YA.',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),

          if (!pedido.estado.esFinal && pedido.estado != EstadoPedido.enCamino) ...[
            const SizedBox(height: MySpacing.md),
            switch (pedido.estado) {
              EstadoPedido.pagado => Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final motivo = await pedirTexto(
                            context,
                            titulo: 'Rechazar ${pedido.codigo}',
                            label: 'Motivo (se lo decimos al cliente)',
                            aceptar: 'Rechazar',
                          );
                          if (motivo != null && context.mounted) {
                            await _hacer(context, () => repo.rechazar(pedido.id, motivo));
                          }
                        },
                        child: const Text('Rechazar'),
                      ),
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      flex: 2,
                      child: MyBotonAccion(
                        label: 'Aceptar pedido',
                        icon: Symbols.check,
                        onPressed: () => _hacer(context, () => repo.aceptar(pedido.id)),
                      ),
                    ),
                  ],
                ),
              EstadoPedido.aceptado => MyBotonAccion(
                  label: 'Empezar a preparar',
                  icon: Symbols.skillet,
                  onPressed: () => _hacer(context, () => repo.avanzar(pedido.id, EstadoPedido.enPreparacion)),
                ),
              EstadoPedido.enPreparacion => MyBotonAccion(
                  label: 'Listo: llamar rider',
                  icon: Symbols.sports_motorsports,
                  onPressed: () => _hacer(context, () => repo.avanzar(pedido.id, EstadoPedido.listo)),
                ),
              EstadoPedido.listo => pedido.envioId == null
                  ? const SizedBox.shrink()
                  : OutlinedButton.icon(
                      onPressed: () => context.push('/local/envio/${pedido.envioId}'),
                      icon: const Icon(Symbols.near_me, size: 20),
                      label: const Text('Ver el rider'),
                    ),
              _ => const SizedBox.shrink(),
            },
          ],
          if (pedido.estado == EstadoPedido.enCamino && pedido.envioId != null) ...[
            const SizedBox(height: MySpacing.sm),
            TextButton.icon(
              onPressed: () => context.push('/local/envio/${pedido.envioId}'),
              icon: const Icon(Symbols.near_me, size: 18),
              label: const Text('Seguir el envio'),
            ),
          ],
        ],
      ),
    );
  }
}
