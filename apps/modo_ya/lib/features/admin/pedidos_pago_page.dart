import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Pedidos esperando que se registre el pago.
///
/// PROVISORIO: existe porque todavia no esta decidido como se cobra (efectivo,
/// pasarela o ambos). Mientras tanto, un pedido no le llega al local hasta que
/// la administracion confirma el pago aca. Cuando haya pasarela, la confirmacion
/// la va a hacer el webhook y esta pantalla queda para casos excepcionales.
class PedidosPagoPage extends ConsumerWidget {
  const PedidosPagoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosPendientesDePagoProvider);

    return ListView(
      padding: const EdgeInsets.all(MySpacing.xl),
      children: [
        const AdminPageHeader(
          titulo: 'Pedidos por cobrar',
          bajada: 'No le llegan al local hasta que se confirma el pago',
        ),
        MyCard(
          color: MyColors.primaryFixed,
          shadows: const [],
          padding: const EdgeInsets.all(MySpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Symbols.info, size: 20, color: MyColors.onPrimaryFixedVariant),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  'Provisorio hasta definir con la clienta como se cobra. Por ahora el pago '
                  'se confirma a mano desde esta pantalla.',
                  style: MyType.bodySm.copyWith(color: MyColors.onPrimaryFixedVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.lg),
        MyAsync(
          valor: pedidos,
          datos: (lista) => lista.isEmpty
              ? const MyEmptyState(
                  icon: Symbols.task_alt,
                  title: 'Nada pendiente',
                  message: 'Cuando un cliente confirme un pedido, aparece aca.',
                )
              : Column(
                  children: [
                    for (final p in lista) ...[
                      _PedidoPorCobrar(pedido: p),
                      const SizedBox(height: MySpacing.sm),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PedidoPorCobrar extends ConsumerWidget {
  const _PedidoPorCobrar({required this.pedido});

  final Pedido pedido;

  Future<void> _marcar(BuildContext context, WidgetRef ref) async {
    final metodo = await showDialog<MetodoPago>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Como pago ${pedido.codigo}?'),
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
      if (context.mounted) mostrarAviso(context, 'Pago registrado. El pedido ya le llego al local.');
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MyBadge(pedido.codigo, tone: MyBadgeTone.dark),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  '${pedido.comercioNombre} - ${Formato.haceCuanto(pedido.creadoEn)}',
                  style: MyType.labelLg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(Formato.pesos(pedido.total), style: MyType.headlineSm.copyWith(color: MyColors.primary)),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          Text(
            '${pedido.clienteNombre ?? 'Cliente'} - ${pedido.clienteTelefono ?? ''}',
            style: MyType.bodyMd,
          ),
          Text(pedido.entrega.calle, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          const SizedBox(height: MySpacing.xs),
          for (final i in pedido.items)
            Text('${i.cantidad}x ${i.nombreProducto}', style: MyType.bodySm),
          const SizedBox(height: MySpacing.md),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () async {
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
                  },
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                flex: 2,
                child: MyBotonAccion(
                  label: 'Confirmar pago',
                  icon: Symbols.payments,
                  onPressed: () => _marcar(context, ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
