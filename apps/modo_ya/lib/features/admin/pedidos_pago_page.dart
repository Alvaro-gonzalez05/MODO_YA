import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'avisos_mp.dart';

/// Los pedidos cuyo cobro quedó sin registrar.
///
/// La pantalla es de antes de que en la app se pagara **solo con tarjeta**
/// (0058). Hoy el cobro entra solo, así que acá no cae ningún pedido nuevo:
/// quedan los de antes que nunca se registraron, y cualquiera cuyo pago quedó
/// colgado con el pedido ya en la cocina. Lo normal es que esté vacía.
///
/// Sigue existiendo porque `marcar_pedido_pagado` es la única forma de cerrar
/// esos cobros sin entrar a la base a mano, y porque es el único lugar del
/// panel desde donde la administración puede cancelar un pedido.
class PedidosPagoPage extends ConsumerWidget {
  const PedidosPagoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosPendientesDePagoProvider);

    return MyPagina(
      rotulo: 'Cobros',
      titulo: 'Cobros sin registrar',
      bajada: 'Los pedidos de antes del pago con tarjeta que quedaron sin cerrar',
      acciones: [
        // Lo que guarda el webhook no lo veía nadie (hallazgo 11). Se mira
        // justo acá: cuando un cobro no cerró, lo primero es qué dijo
        // Mercado Pago.
        MyBoton(
          label: 'Avisos de Mercado Pago',
          icon: Symbols.inbox,
          tipo: MyBotonTipo.secundario,
          onPressed: () => mostrarAvisosDeMercadoPago(context),
        ),
      ],
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
                  'En la app se paga solo con tarjeta y el cobro se acredita solo: un pedido '
                  'nuevo no pasa por acá. Lo que aparece es un cobro viejo que quedó abierto.',
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
                  title: 'Nada sin registrar',
                  message: 'Los pedidos con tarjeta se acreditan solos. Si acá aparece alguno, '
                      'es uno viejo o uno al que le falló el cobro.',
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

  /// Con qué se puede registrar el cobro de este pedido.
  ///
  /// Antes se ofrecía `MetodoPago.values` entero, con efectivo y transferencia
  /// adentro — los dos que 0058 sacó. Elegir efectivo acá no es un dato
  /// administrativo: el trigger `copiar_cobro_del_pedido` le pone al envío
  /// `cobrar_al_entregar = total` y el rider sale a cobrar en la puerta. Así
  /// que solo se ofrece lo que el cliente había elegido (estos pedidos son de
  /// antes y lo tienen cargado) y "Otro" para lo que entró por fuera.
  List<MetodoPago> get _metodos => [
        if (pedido.metodoPago != null && pedido.metodoPago != MetodoPago.otro) pedido.metodoPago!,
        MetodoPago.otro,
      ];

  Future<void> _confirmar(BuildContext context, WidgetRef ref) async {
    final metodo = await showDialog<MetodoPago>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('¿Cómo cobraste ${pedido.codigo}?'),
        children: [
          for (final m in _metodos)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
                child: Text(
                  switch (m) {
                    MetodoPago.otro => 'Otro (entró por fuera de la app)',
                    _ when m == pedido.metodoPago => '${m.label} (lo que eligió el cliente)',
                    _ => m.label,
                  },
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
