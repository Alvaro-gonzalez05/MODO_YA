import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/estados_ui.dart';
import '../../comun/reclamos.dart';

/// Lo que se pidió y cuánto salió: los productos, el envío, el total y a dónde
/// se llevó. Es el mismo bloque en el seguimiento y en el detalle de un pedido
/// terminado, para que los dos digan lo mismo con las mismas palabras.
class DetalleDelPedido extends StatelessWidget {
  const DetalleDelPedido({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in pedido.items)
          Padding(
            padding: const EdgeInsets.only(bottom: MySpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${i.cantidad}× ', style: MyType.labelLg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.nombreProducto, style: MyType.bodyMd),
                      for (final o in i.opciones)
                        Text(o, style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
                      if (i.nota != null)
                        Text('"${i.nota}"', style: MyType.bodySm.copyWith(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                const SizedBox(width: MySpacing.xs),
                Text(Formato.pesos(i.subtotal), style: MyType.labelMd),
              ],
            ),
          ),
        const Divider(),
        LineaDelPedido('Productos', Formato.pesos(pedido.subtotal)),
        // "$0" es cierto pero no se entiende: la pantalla de pago ya le dice
        // por qué no paga el envío, y acá también tiene que decirlo.
        LineaDelPedido('Envío', pedido.envioLoPoneElLocal ? 'Gratis con Plus' : Formato.pesos(pedido.costoEnvio)),
        LineaDelPedido('Total', Formato.pesos(pedido.total), destacado: true),
        const SizedBox(height: MySpacing.xs),
        LineaDelPedido('Entrega', pedido.entrega.calle),
        if (pedido.nota != null && pedido.nota!.trim().isNotEmpty) LineaDelPedido('Nota', pedido.nota!),
      ],
    );
  }
}

/// Concepto a la izquierda y valor a la derecha; el valor largo (una calle)
/// pasa de renglón en vez de empujar al concepto.
class LineaDelPedido extends StatelessWidget {
  const LineaDelPedido(this.label, this.valor, {super.key, this.destacado = false});

  final String label;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MySpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: MyType.bodyMd.copyWith(color: MyColors.claroTextoSecundario)),
            const SizedBox(width: MySpacing.md),
            Expanded(
              child: Text(
                valor,
                textAlign: TextAlign.right,
                style: destacado ? MyType.headlineSm.copyWith(color: MyColors.claroAcento) : MyType.labelLg,
              ),
            ),
          ],
        ),
      );
}

/// El detalle de un pedido que ya terminó, encima de la lista: panel al costado
/// en la compu, hoja desde abajo en el celular.
///
/// Uno entregado o cancelado no tiene nada que seguir: abrir la pantalla de
/// seguimiento (pensada para el mapa y los pasos) era un salto para leer tres
/// renglones y volver.
Future<void> mostrarPedidoTerminado(BuildContext context, Pedido pedido) {
  return mostrarHojaLateral(
    context,
    titulo: 'Pedido ${pedido.codigo}',
    builder: (_) => HojaDelPedido(resumen: pedido),
  );
}

class HojaDelPedido extends ConsumerWidget {
  const HojaDelPedido({super.key, required this.resumen});

  /// El pedido como viene en la lista: sin los productos, que se leen aparte.
  final Pedido resumen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La lista no trae los productos: se piden al abrir. Mientras llegan se
    // muestra lo que ya se sabe, sin parpadear a un spinner.
    final completo = ref.watch(pedidoProvider(resumen.id)).value;
    final p = completo ?? resumen;
    final e = p.estado;

    final (icono, titulo, bajada) = switch (e) {
      EstadoPedido.entregado => (Symbols.check_circle, 'Entregado', 'Si algo no estuvo bien, contanos más abajo.'),
      EstadoPedido.rechazado => (Symbols.cancel, 'El local no pudo tomarlo', p.motivoRechazo ?? 'Te devolvimos el dinero.'),
      EstadoPedido.cancelado => (Symbols.cancel, 'Pedido cancelado', 'Si lo habías pagado, te devolvimos el dinero.'),
      _ => (Symbols.receipt_long, e.label, ''),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            MyImagen(url: p.comercioLogoUrl, ancho: 52, alto: 52, icono: Symbols.storefront),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.comercioNombre, style: MyType.headlineSm, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    '${Formato.fechaCorta(p.creadoEn)} ${Formato.hora(p.creadoEn)}',
                    style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: MySpacing.md),
        MyCard(
          color: e == EstadoPedido.entregado ? MyColors.successContainer : MyColors.claroSuperficieAlt,
          shadows: const [],
          padding: const EdgeInsets.all(MySpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, fill: 1, color: e == EstadoPedido.entregado ? MyColors.onSuccessContainer : MyColors.claroTextoSecundario),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MyBadge(titulo, tone: tonoPedido(e)),
                    if (bajada.isNotEmpty) ...[
                      const SizedBox(height: MySpacing.xxs),
                      Text(bajada, style: MyType.bodyMd),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.lg),
        Text('Detalle', style: MyType.headlineSm),
        const SizedBox(height: MySpacing.sm),
        if (completo == null && p.items.isEmpty)
          const MyCargando(size: 32)
        else
          DetalleDelPedido(pedido: p),
        if (e != EstadoPedido.pendientePago && e != EstadoPedido.carrito) ...[
          const SizedBox(height: MySpacing.lg),
          ReclamoDelPedido(pedido: p),
        ],
      ],
    );
  }
}
