import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Pedidos esperando que se registre el pago.
///
/// PROVISORIO: existe porque todavía no está decidido cómo se cobra (efectivo,
/// pasarela o ambos). Mientras tanto, un pedido no le llega al local hasta que
/// la administración confirma el pago acá. Cuando haya pasarela, la
/// confirmación la va a hacer el webhook y esta pantalla queda para casos
/// excepcionales.
class PedidosPagoPage extends ConsumerWidget {
  const PedidosPagoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosPendientesDePagoProvider);

    return MyPagina(
      rotulo: 'Cobros',
      titulo: 'Pedidos por cobrar',
      bajada: 'No le llegan al local hasta que confirmás el pago',
      children: [
        MyCard(
          color: MyColors.primaryFixed,
          shadows: const [],
          padding: const EdgeInsets.all(MySpacing.md),
          child: Row(
            children: [
              const Icon(Symbols.info, size: 20, color: MyColors.onPrimaryFixedVariant),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  'Provisorio hasta definir cómo se cobra. Por ahora cada pago se confirma a mano desde acá.',
                  style: MyType.bodySm.copyWith(color: MyColors.onPrimaryFixedVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.lg),
        MyAsync(
          valor: pedidos,
          onReintentar: () => ref.invalidate(pedidosPendientesDePagoProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return const MyCard(
                child: MyEmptyState(
                  icon: Symbols.task_alt,
                  title: 'Nada pendiente',
                  message: 'Cuando un cliente confirme un pedido, aparece acá.',
                ),
              );
            }
            if (context.esMovil) {
              return Column(
                children: [
                  for (final p in lista) ...[
                    _TarjetaPedido(pedido: p),
                    const SizedBox(height: MySpacing.sm),
                  ],
                ],
              );
            }
            return MyTabla(
              columnas: const [
                MyColumna('Pedido'),
                MyColumna('Local', flex: 2),
                MyColumna('Cliente', flex: 2),
                MyColumna('Productos', flex: 2),
                MyColumna('Total', alDerecha: true),
                MyColumna('', flex: 3, alDerecha: true),
              ],
              filas: [
                for (final p in lista)
                  MyFila(
                    celdas: [
                      MyCeldaDoble(p.codigo, bajada: Formato.haceCuanto(p.creadoEn)),
                      Text(p.comercioNombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                      MyCeldaDoble(p.clienteNombre ?? 'Cliente', bajada: p.clienteTelefono),
                      Text(
                        p.items.map((i) => '${i.cantidad}× ${i.nombreProducto}').join(', '),
                        style: MyType.bodySm,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(Formato.pesos(p.total), style: MyType.headlineSm.copyWith(color: MyColors.primary)),
                      _Acciones(pedido: p),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TarjetaPedido extends StatelessWidget {
  const _TarjetaPedido({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MyBadge(pedido.codigo, tone: MyBadgeTone.dark),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: Text(
                  Formato.haceCuanto(pedido.creadoEn),
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ),
              Text(Formato.pesos(pedido.total), style: MyType.headlineSm.copyWith(color: MyColors.primary)),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          Text(pedido.comercioNombre, style: MyType.headlineSm),
          Text(
            '${pedido.clienteNombre ?? 'Cliente'} · ${pedido.clienteTelefono ?? ''}',
            style: MyType.bodyMd,
          ),
          Text(pedido.entrega.calle, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          const SizedBox(height: MySpacing.xs),
          for (final i in pedido.items) Text('${i.cantidad}× ${i.nombreProducto}', style: MyType.bodySm),
          const SizedBox(height: MySpacing.md),
          _Acciones(pedido: pedido),
        ],
      ),
    );
  }
}

class _Acciones extends ConsumerWidget {
  const _Acciones({required this.pedido});

  final Pedido pedido;

  Future<void> _confirmar(BuildContext context, WidgetRef ref) async {
    final metodo = await showDialog<MetodoPago>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('¿Cómo pagó ${pedido.codigo}?'),
        children: [
          for (final m in MetodoPago.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
                child: Text(m.label, style: MyType.labelLg),
              ),
            ),
        ],
      ),
    );
    if (metodo == null) return;
    try {
      await ref.read(pedidosRepositoryProvider).marcarPagado(pedido.id, metodo);
      if (context.mounted) mostrarAviso(context, 'Pago registrado. El pedido ya le llegó al local.');
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Cancelar ${pedido.codigo}',
      label: 'Motivo',
      aceptar: 'Cancelar pedido',
    );
    if (motivo == null) return;
    try {
      await ref.read(pedidosRepositoryProvider).cancelar(pedido.id, motivo);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: MySpacing.xs,
      runSpacing: MySpacing.xs,
      children: [
        MyBoton(label: 'Cancelar', tipo: MyBotonTipo.texto, onPressed: () => _cancelar(context, ref)),
        MyBoton(label: 'Confirmar pago', icon: Symbols.payments, onPressed: () => _confirmar(context, ref)),
      ],
    );
  }
}
