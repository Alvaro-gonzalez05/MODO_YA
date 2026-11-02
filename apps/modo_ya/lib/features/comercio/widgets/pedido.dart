import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../../comun/estados_ui.dart';
import 'envio.dart';

/// Abre el pedido encima de lo que se está mirando: panel al costado en la
/// compu, hoja desde abajo en el celular.
///
/// Se usa desde el tablero, el inicio y el aviso de pedido nuevo. Antes cada
/// uno mandaba a la pestaña Pedidos y el local tenía que volver a buscarlo.
Future<void> mostrarDetallePedido(BuildContext context, Pedido pedido) => mostrarHojaLateral(
      context,
      titulo: 'Detalle del pedido',
      builder: (_) => DetallePedido(inicial: pedido),
    );

/// Lista de pedidos en una hoja (los nuevos, los que están en cocina). Si hay
/// uno solo, va directo a su detalle: una lista de un renglón es un toque de
/// más.
Future<void> mostrarPedidos(
  BuildContext context, {
  required String titulo,
  required bool Function(Pedido) filtro,
  required List<Pedido> ahora,
}) {
  final visibles = ahora.where(filtro).toList();
  if (visibles.length == 1) return mostrarDetallePedido(context, visibles.first);
  return mostrarHojaLateral(
    context,
    titulo: titulo,
    builder: (_) => _ListaDePedidos(titulo: titulo, filtro: filtro),
  );
}

class _ListaDePedidos extends ConsumerWidget {
  const _ListaDePedidos({required this.titulo, required this.filtro});

  final String titulo;
  final bool Function(Pedido) filtro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // En vivo: si acepta uno desde acá, sale de "nuevos" sin cerrar la hoja.
    final lista = (ref.watch(pedidosDelComercioProvider).value ?? const <Pedido>[]).where(filtro).toList()
      ..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: MyType.headlineMd),
        const SizedBox(height: MySpacing.md),
        if (lista.isEmpty)
          const MyEmptyState(
            icon: Symbols.task_alt,
            title: 'Ya no queda ninguno',
            message: 'Los fuiste atendiendo. Los que siguen en curso están en Pedidos.',
          )
        else
          for (final p in lista) ...[
            TarjetaPedido(pedido: p),
            const SizedBox(height: MySpacing.sm),
          ],
      ],
    );
  }
}

/// Tarjeta corta de un pedido: lo que hace falta para decidir sin abrirlo
/// (quién, qué, cuánto y hasta cuándo) y el botón del paso siguiente. Tocarla
/// abre el detalle.
///
/// Es angosta a propósito: en el tablero de la compu cada columna tiene unos
/// 200 px y en el celular la tarjeta va a lo ancho de 360.
class TarjetaPedido extends StatelessWidget {
  const TarjetaPedido({super.key, required this.pedido, this.mostrarEstado = true});

  final Pedido pedido;

  /// En las columnas del tablero el estado ya lo dice la columna.
  final bool mostrarEstado;

  /// Los renglones del pedido que entran en la tarjeta. El resto, en el detalle.
  static const _maxItems = 4;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final secundario = MyType.bodySm.copyWith(color: MyColors.secondary);

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      onTap: () => mostrarDetallePedido(context, p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap y no Row: en una columna angosta el estado baja de renglón en
          // vez de desbordar.
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Achicable(MyBadge(p.codigo, tone: MyBadgeTone.dark)),
              if (mostrarEstado)
                _Achicable(MyBadge(p.estado.label, tone: tonoPedido(p.estado), dot: p.estado == EstadoPedido.pagado)),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  p.clienteNombre ?? 'Cliente',
                  style: MyType.headlineSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: MySpacing.xs),
              Text(Formato.pesos(p.subtotal), style: MyType.labelLg.copyWith(color: MyColors.tertiary)),
            ],
          ),
          Text(
            '${Formato.haceCuanto(p.creadoEn)} · ${p.entrega.calle}',
            style: secundario,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (p.respondeAntesDe case final limite?) ...[
            const SizedBox(height: MySpacing.xs),
            AvisoVencimiento(limite: limite),
          ],
          const Divider(height: MySpacing.lg),
          for (final item in p.items.take(_maxItems))
            Padding(
              padding: const EdgeInsets.only(bottom: MySpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text('${item.cantidad}×', style: MyType.labelLg.copyWith(color: MyColors.tertiary)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.nombreProducto, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (item.opciones.isNotEmpty)
                          Text(item.opciones.join(' · '), style: secundario, maxLines: 1, overflow: TextOverflow.ellipsis),
                        // La aclaración del cliente ("sin cebolla") es lo que
                        // más se pierde en la cocina: va siempre a la vista.
                        if (item.nota != null)
                          Text(
                            '"${item.nota}"',
                            style: MyType.bodySm.copyWith(fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (p.items.length > _maxItems)
            Text('y ${p.items.length - _maxItems} más · tocá para ver todo', style: secundario),
          if (p.nota != null) ...[
            const SizedBox(height: MySpacing.xs),
            _Nota(texto: p.nota!, lineas: 2),
          ],
          if (!p.estado.esFinal) ...[
            const SizedBox(height: MySpacing.sm),
            AccionesPedido(pedido: p),
          ],
        ],
      ),
    );
  }
}

/// Una pastilla que, si no entra en el ancho, se achica en vez de desbordar.
/// `MyBadge` no corta el texto, y "En preparación" en una columna de 150 px
/// del tablero no entraba.
class _Achicable extends StatelessWidget {
  const _Achicable(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: child);
}

/// "Respondé antes de las 20:55…". Sin esto el local se enteraba del
/// vencimiento (0076) recién al ver la penalidad en la liquidación.
class AvisoVencimiento extends StatelessWidget {
  const AvisoVencimiento({super.key, required this.limite});

  final DateTime limite;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Symbols.timer, size: 16, color: MyColors.error),
        const SizedBox(width: MySpacing.xxs),
        Expanded(
          child: Text(
            'Respondé antes de las ${Formato.hora(limite)}: si no, se rechaza solo y se cobra la penalidad.',
            style: MyType.bodySm.copyWith(color: MyColors.error),
          ),
        ),
      ],
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota({required this.texto, this.lineas});

  final String texto;
  final int? lineas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MySpacing.sm),
      decoration: BoxDecoration(
        color: MyColors.secondaryContainer,
        borderRadius: BorderRadius.circular(MyRadius.md),
      ),
      child: Text(
        'Nota: $texto',
        style: MyType.bodySm,
        maxLines: lineas,
        overflow: lineas == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

/// El paso siguiente del pedido. Es el mismo en la tarjeta y en el detalle,
/// así el botón está donde lo busque.
class AccionesPedido extends ConsumerWidget {
  const AccionesPedido({super.key, required this.pedido});

  final Pedido pedido;

  Future<void> _hacer(BuildContext context, Future<void> Function() accion) async {
    try {
      await accion();
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  Future<void> _rechazar(BuildContext context, PedidosRepository repo) async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Rechazar ${pedido.codigo}',
      label: 'Motivo (se lo decimos al cliente)',
      aceptar: 'Rechazar',
      // Lo que hace `rechazar_pedido` desde 0060: el cliente no pierde nada y
      // el local sí. Mejor saberlo antes de tocar.
      ayuda: 'Al cliente le devolvemos todo lo que pagó. A vos se te descuenta '
          'una penalidad en la liquidación.',
    );
    if (motivo != null && context.mounted) {
      await _hacer(context, () => repo.rechazar(pedido.id, motivo));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(pedidosRepositoryProvider);
    final p = pedido;

    return switch (p.estado) {
      // Uno arriba del otro y no lado a lado: en una columna de 200 px dos
      // botones en fila no dejan leer ninguno.
      EstadoPedido.pagado => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyBotonAccion(
              label: 'Aceptar pedido',
              icon: Symbols.check,
              onPressed: () => _hacer(context, () => repo.aceptar(p.id)),
            ),
            const SizedBox(height: MySpacing.xxs),
            MyBoton(
              label: 'Rechazar',
              tipo: MyBotonTipo.texto,
              onPressed: () => _rechazar(context, repo),
            ),
          ],
        ),
      EstadoPedido.aceptado => MyBotonAccion(
          label: 'Empezar a preparar',
          icon: Symbols.skillet,
          onPressed: () => _hacer(context, () => repo.avanzar(p.id, EstadoPedido.enPreparacion)),
        ),
      EstadoPedido.enPreparacion => MyBotonAccion(
          label: 'Listo: llamar rider',
          icon: Symbols.sports_motorsports,
          onPressed: () => _hacer(context, () => repo.avanzar(p.id, EstadoPedido.listo)),
        ),
      EstadoPedido.listo || EstadoPedido.enCamino when p.envioId != null => MyBotonAccion(
          label: p.estado == EstadoPedido.listo ? 'Ver el rider' : 'Seguir el envío',
          icon: Symbols.near_me,
          secundario: true,
          onPressed: () => mostrarDetalleEnvio(context, p.envioId!),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Todo el pedido: cliente, renglones con sus opciones, notas, cuentas y el
/// paso siguiente.
///
/// Se dibuja con el pedido en vivo: si lo acepta desde acá, la hoja pasa a
/// "Aceptado" y muestra "Empezar a preparar" sin cerrarse.
class DetallePedido extends ConsumerWidget {
  const DetallePedido({super.key, required this.inicial});

  /// El que se tocó. Se usa mientras llega la lista y si el pedido ya no está
  /// en ella (los más viejos se caen de la consulta).
  final Pedido inicial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enVivo = ref.watch(pedidosDelComercioProvider).value?.where((x) => x.id == inicial.id).firstOrNull;
    final p = enVivo ?? inicial;
    final secundario = MyType.bodySm.copyWith(color: MyColors.secondary);
    const espacio = SizedBox(height: MySpacing.lg);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pedido ${p.codigo}', style: MyType.headlineMd),
        const SizedBox(height: MySpacing.xxs),
        Wrap(
          spacing: MySpacing.xs,
          runSpacing: MySpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Achicable(MyBadge(p.estado.label, tone: tonoPedido(p.estado), dot: p.estado == EstadoPedido.pagado)),
            Text('Entró a las ${Formato.hora(p.creadoEn)} · ${Formato.haceCuanto(p.creadoEn)}', style: secundario),
          ],
        ),
        if (p.respondeAntesDe case final limite?) ...[
          const SizedBox(height: MySpacing.sm),
          AvisoVencimiento(limite: limite),
        ],
        if (p.motivoDelCierre case final motivo?) ...[
          const SizedBox(height: MySpacing.sm),
          Container(
            padding: const EdgeInsets.all(MySpacing.sm),
            decoration: BoxDecoration(color: MyColors.errorContainer, borderRadius: BorderRadius.circular(MyRadius.md)),
            child: Text('Motivo: $motivo', style: MyType.bodySm.copyWith(color: MyColors.onErrorContainer)),
          ),
        ],
        if (!p.estado.esFinal) ...[
          const SizedBox(height: MySpacing.md),
          AccionesPedido(pedido: p),
        ],
        espacio,
        const MyOverline('Cliente'),
        MyDato('Nombre', p.clienteNombre ?? 'Cliente', icono: Symbols.person),
        if ((p.clienteTelefono ?? '').isNotEmpty) MyDato('Teléfono', p.clienteTelefono!, icono: Symbols.call),
        MyDato(
          'Entrega',
          [p.entrega.calle, if ((p.entrega.referencia ?? '').isNotEmpty) p.entrega.referencia!].join(' · '),
          icono: Symbols.location_on,
        ),
        espacio,
        MyOverline('Qué pidió · ${p.cantidadProductos} ${p.cantidadProductos == 1 ? 'producto' : 'productos'}'),
        const SizedBox(height: MySpacing.xs),
        for (final item in p.items)
          Padding(
            padding: const EdgeInsets.only(bottom: MySpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 30, child: Text('${item.cantidad}×', style: MyType.labelLg.copyWith(color: MyColors.tertiary))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.nombreProducto, style: MyType.labelLg),
                      for (final o in item.opciones) Text(o, style: secundario),
                      if (item.nota != null) Text('"${item.nota}"', style: MyType.bodySm.copyWith(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                const SizedBox(width: MySpacing.xs),
                Text(Formato.pesos(item.subtotal), style: MyType.labelMd),
              ],
            ),
          ),
        if (p.nota != null) _Nota(texto: p.nota!),
        espacio,
        const MyOverline('Cuentas'),
        const SizedBox(height: MySpacing.xs),
        MyRenglon('Productos', Formato.pesos(p.subtotal), fuerte: true, color: MyColors.tertiary),
        const SizedBox(height: MySpacing.xxs),
        // Con Plus el cliente no paga el envío y `costoEnvio` viene en 0, así
        // que acá decía "$0": el envío igual vale lo que vale y lo pone el
        // local con su campaña. Mostrarle cero era mentirle sobre su plata.
        Text(
          p.envioLoPoneElLocal
              ? 'El envío (${Formato.pesos(p.envioReal)}) lo ponés vos con tu campaña Plus: '
                  'se te descuenta de tus ventas.'
              : 'El envío (${Formato.pesos(p.envioReal)}) lo cobra MODO YA.',
          style: secundario,
        ),
        // En la app solo se paga con tarjeta desde 0058: el pedido llega al
        // local ya cobrado. Los métodos viejos no se nombran: ningún pedido
        // abierto los usa.
        if (p.metodoPago == MetodoPago.mercadoPago) ...[
          const SizedBox(height: MySpacing.sm),
          Row(
            children: [
              Icon(Symbols.credit_card, size: 18, color: MyColors.secondary),
              const SizedBox(width: MySpacing.xs),
              Expanded(child: Text('Pagado con tarjeta en la app', style: MyType.labelMd)),
            ],
          ),
        ],
      ],
    );
  }
}
