import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/estados_ui.dart';

/// Pedidos del cliente: los que están en curso arriba, después el historial.
class MisPedidosPage extends ConsumerWidget {
  const MisPedidosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosDelClienteProvider);

    return MyPagina(
      rotulo: 'Historial',
      titulo: 'Mis pedidos',
      bajada: 'Tocá uno para seguirlo o ver el detalle',
      onRefresh: () => ref.refresh(pedidosDelClienteProvider.future),
      children: [
        MyAsync(
          valor: pedidos,
          onReintentar: () => ref.invalidate(pedidosDelClienteProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.receipt_long,
                  title: 'Todavía no hiciste pedidos',
                  message: 'Cuando pidas algo, lo vas a poder seguir desde acá.',
                  action: MyBoton(label: 'Ver locales', icon: Symbols.storefront, onPressed: () => context.go('/cliente')),
                ),
              );
            }
            final enCurso = lista.where((p) => !p.estado.esFinal).toList();
            final cerrados = lista.where((p) => p.estado.esFinal).toList();

            Widget bloque(String titulo, List<Pedido> ps) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(titulo, style: MyType.headlineMd),
                    const SizedBox(height: MySpacing.sm),
                    if (context.esMovil)
                      for (final p in ps) ...[_Tarjeta(pedido: p), const SizedBox(height: MySpacing.sm)]
                    else
                      MyTabla(
                        columnas: const [
                          MyColumna('Local', flex: 3),
                          MyColumna('Pedido', flex: 2),
                          MyColumna('Total', alDerecha: true),
                          MyColumna('Estado', flex: 2, alDerecha: true),
                        ],
                        filas: [
                          for (final p in ps)
                            MyFila(
                              onTap: () => context.go('/cliente/pedidos/${p.id}'),
                              celdas: [
                                MyCeldaDoble(
                                  p.comercioNombre,
                                  inicio: MyImagen(url: p.comercioLogoUrl, ancho: 44, alto: 44, icono: Symbols.storefront),
                                ),
                                MyCeldaDoble(p.codigo, bajada: '${Formato.fechaCorta(p.creadoEn)} ${Formato.hora(p.creadoEn)}'),
                                Text(Formato.pesos(p.total), style: MyType.labelLg),
                                _Estado(pedido: p),
                              ],
                            ),
                        ],
                      ),
                  ],
                );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (enCurso.isNotEmpty) ...[bloque('En curso', enCurso), const SizedBox(height: MySpacing.xl)],
                if (cerrados.isNotEmpty) bloque('Anteriores', cerrados),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final e = pedido.estado;
    return MyBadge(
      e == EstadoPedido.pagado ? 'Enviado al local' : e.label,
      tone: e.esFinal ? tonoPedido(e) : MyBadgeTone.ember,
      dot: !e.esFinal,
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      onTap: () => context.go('/cliente/pedidos/${p.id}'),
      child: Row(
        children: [
          MyImagen(url: p.comercioLogoUrl, ancho: 56, alto: 56, icono: Symbols.storefront),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.comercioNombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${p.codigo} · ${Formato.fechaCorta(p.creadoEn)} ${Formato.hora(p.creadoEn)}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
                const SizedBox(height: MySpacing.xxs),
                _Estado(pedido: p),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.xs),
          Text(Formato.pesos(p.total), style: MyType.labelLg),
        ],
      ),
    );
  }
}
