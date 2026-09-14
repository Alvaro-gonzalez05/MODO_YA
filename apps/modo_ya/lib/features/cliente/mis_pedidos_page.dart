import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

class MisPedidosPage extends ConsumerWidget {
  const MisPedidosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosDelClienteProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Mis pedidos'),
        Expanded(
          child: MyAsync(
            valor: pedidos,
            onReintentar: () => ref.invalidate(pedidosDelClienteProvider),
            datos: (lista) => lista.isEmpty
                ? const MyEmptyState(
                    icon: Symbols.receipt_long,
                    title: 'Todavia no hiciste pedidos',
                    message: 'Cuando pidas algo, lo vas a poder seguir desde aca.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance,
                    ),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const SizedBox(height: MySpacing.sm),
                    itemBuilder: (_, i) {
                      final p = lista[i];
                      final activo = !p.estado.esFinal;
                      return MyCard(
                        onTap: () => context.push('/cliente/pedido/${p.id}'),
                        child: Row(
                          children: [
                            MyImagen(url: p.comercioLogoUrl, ancho: 52, alto: 52, icono: Symbols.storefront),
                            const SizedBox(width: MySpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.comercioNombre, style: MyType.headlineSm),
                                  Text(
                                    '${p.codigo} - ${Formato.fechaCorta(p.creadoEn)} ${Formato.hora(p.creadoEn)}',
                                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                                  ),
                                  const SizedBox(height: MySpacing.xxs),
                                  MyBadge(
                                    p.estado == EstadoPedido.pagado ? 'Enviado al local' : p.estado.label,
                                    tone: activo
                                        ? MyBadgeTone.ember
                                        : (p.estado == EstadoPedido.entregado ? MyBadgeTone.success : MyBadgeTone.danger),
                                    dot: activo,
                                  ),
                                ],
                              ),
                            ),
                            Text(Formato.pesos(p.total), style: MyType.labelLg),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
