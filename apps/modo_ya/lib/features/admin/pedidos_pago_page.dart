import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Cobros pendientes de los pedidos.
///
/// El pedido le llega al local apenas el cliente lo confirma (0027): esta
/// pantalla no frena nada. Sirve para llevar la cuenta de lo que falta cobrar
/// (el efectivo que trae el rider, el posnet, las transferencias) y marcarlo
/// cuando entra la plata.
class PedidosPagoPage extends ConsumerWidget {
  const PedidosPagoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosPendientesDePagoProvider);

    return MyPagina(
      rotulo: 'Cobros',
      titulo: 'Pedidos por cobrar',
      bajada: 'Los pedidos ya le llegaron al local: acá registrás lo que se cobró',
      children: [
        MyCard(
          color: MyColors.primaryFixed,
          shadows: const [],
          padding: const EdgeInsets.all(MySpacing.md),
          child: Row(
            children: [
              Icon(Symbols.info, size: 20, color: MyColors.onPrimaryFixedVariant),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  'El cliente elige con qué paga y el local recibe el pedido en el momento. '
                  'Cuando entra la plata (efectivo, posnet o transferencia), marcalo como cobrado.',
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
                  title: 'Nada por cobrar',
                  message: 'Cada pedido nuevo aparece acá hasta que registres el cobro.',
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
                MyColumna('Paga con'),
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
                      MyCeldaDoble(p.metodoPago?.label ?? 'Sin elegir', bajada: p.estado.label),
                      Text(Formato.pesos(p.total), style: MyType.headlineSm.copyWith(color: MyColors.tertiary)),
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
              Text(Formato.pesos(pedido.total), style: MyType.headlineSm.copyWith(color: MyColors.tertiary)),
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
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              MyBadge('Paga con ${pedido.metodoPago?.label.toLowerCase() ?? 'sin elegir'}', tone: MyBadgeTone.info),
              MyBadge(pedido.estado.label, tone: MyBadgeTone.neutral),
            ],
          ),
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
        title: Text('¿Cómo cobraste ${pedido.codigo}?'),
        children: [
          // Primero lo que eligió el cliente: es lo más probable.
          for (final m in [
            if (pedido.metodoPago != null) pedido.metodoPago!,
            ...MetodoPago.values.where((m) => m != pedido.metodoPago),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
                child: Text(
                  m == pedido.metodoPago ? '${m.label} (lo que eligió el cliente)' : m.label,
                  style: MyType.labelLg,
                ),
              ),
            ),
        ],
      ),
    );
    if (metodo == null) return;
    try {
      await ref.read(pedidosRepositoryProvider).marcarPagado(pedido.id, metodo);
      if (context.mounted) mostrarAviso(context, 'Cobro registrado.');
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
        MyBoton(label: 'Cobrado', icon: Symbols.payments, onPressed: () => _confirmar(context, ref)),
      ],
    );
  }
}
