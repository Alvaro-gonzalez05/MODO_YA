import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';
import 'encoger.dart';
import 'envios_page.dart';

/// Los pedidos de la app de todos los locales, en vivo.
///
/// Cuando se sacó la sección Cobros (era de la época del efectivo) se fue con
/// ella la única lista de pedidos que tenía la administración: si un cliente
/// llamaba preguntando por su pedido no había dónde buscarlo. Esto es eso,
/// sin lo de cobrar a mano.
///
/// En la compu, tocar un pedido abre su ficha al costado y la lista queda
/// quieta: se puede ir de uno a otro sin cerrar nada. En el celular la ficha
/// sube desde abajo.
class AdminPedidosPage extends ConsumerStatefulWidget {
  const AdminPedidosPage({super.key});

  @override
  ConsumerState<AdminPedidosPage> createState() => _AdminPedidosPageState();
}

enum _Vista {
  enCurso('En curso'),
  porAceptar('Por aceptar'),
  sinPagar('Esperando pago'),
  cerrados('Cerrados');

  const _Vista(this.label);
  final String label;

  bool incluye(Pedido p) => switch (this) {
        enCurso => !p.estado.esFinal && p.estado != EstadoPedido.pendientePago,
        porAceptar => p.estado == EstadoPedido.pagado,
        sinPagar => p.estado == EstadoPedido.pendientePago,
        cerrados => p.estado.esFinal,
      };
}

class _AdminPedidosPageState extends ConsumerState<AdminPedidosPage> {
  var _vista = _Vista.enCurso;
  var _busqueda = '';
  String? _seleccionado;

  void _abrir(Pedido p) {
    if (context.esEscritorio) {
      // Tocar el que ya está abierto lo cierra: es lo que se espera de una fila
      // marcada.
      setState(() => _seleccionado = _seleccionado == p.id ? null : p.id);
    } else {
      mostrarFichaPedido(context, p.id);
    }
  }

  /// Busca por código, cliente, teléfono o local: es lo que dice quien llama.
  bool _coincide(Pedido p) {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [p.codigo, p.clienteNombre ?? '', p.clienteTelefono ?? '', p.comercioNombre]
        .any((t) => t.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(todosLosPedidosProvider);

    return MyPagina(
      rotulo: 'En vivo',
      titulo: 'Pedidos',
      bajada: 'Los de la app, de todos los locales',
      anchoMaximo: 1400,
      children: [
        MyAsync(
          valor: pedidos,
          onReintentar: () => ref.invalidate(todosLosPedidosProvider),
          datos: (lista) {
            final buscados = lista.where(_coincide).toList();
            final visibles = buscados.where(_vista.incluye).toList();
            final seleccionado = lista.where((p) => p.id == _seleccionado).firstOrNull;

            final filtros = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyBuscador(
                  hint: 'Código, cliente, teléfono o local',
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
                const SizedBox(height: MySpacing.sm),
                MyFiltros<_Vista>(
                  seleccionado: _vista,
                  onChanged: (v) => setState(() => _vista = v),
                  opciones: [for (final v in _Vista.values) (v, v.label, buscados.where(v.incluye).length)],
                ),
                const SizedBox(height: MySpacing.md),
              ],
            );

            if (visibles.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  filtros,
                  MyCard(
                    child: MyEmptyState(
                      icon: _busqueda.isEmpty ? Symbols.receipt_long : Symbols.search_off,
                      title: _busqueda.isEmpty ? 'Nada en "${_vista.label}"' : 'Ningún pedido coincide',
                      message: _busqueda.isEmpty
                          ? 'Se actualiza solo cuando entra o cambia un pedido.'
                          : 'Probá con el código (lo ve el cliente en su pedido) o con su teléfono.',
                    ),
                  ),
                ],
              );
            }

            if (context.esMovil) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  filtros,
                  for (final p in visibles) ...[
                    _TarjetaPedidoAdmin(pedido: p, onTap: () => _abrir(p)),
                    const SizedBox(height: MySpacing.sm),
                  ],
                ],
              );
            }

            // Con la ficha abierta la tabla pierde las columnas menos
            // importantes en vez de apretarlas todas.
            final compacta = seleccionado != null || !context.esEscritorio;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filtros,
                MyConPanel(
                  anchoPanel: 420,
                  principal: MyTabla(
                    columnas: [
                      const MyColumna('Pedido'),
                      const MyColumna('Local', flex: 2),
                      const MyColumna('Cliente', flex: 2),
                      if (!compacta) const MyColumna('Total', alDerecha: true),
                      const MyColumna('Estado', flex: 2, alDerecha: true),
                    ],
                    filas: [
                      for (final p in visibles)
                        MyFila(
                          seleccionada: p.id == _seleccionado,
                          onTap: () => _abrir(p),
                          celdas: [
                            MyCeldaDoble(p.codigo, bajada: Formato.hora(p.creadoEn)),
                            Text(p.comercioNombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(p.clienteNombre ?? 'Cliente', style: MyType.bodyMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (!compacta) Text(Formato.pesos(p.total), style: MyType.labelLg),
                            Encoger(
                              child: MyBadge(p.estado.label, tone: tonoPedido(p.estado), dot: p.estado == EstadoPedido.pagado),
                            ),
                          ],
                        ),
                    ],
                  ),
                  panel: seleccionado == null
                      ? null
                      : MyCard(
                          child: FichaPedido(
                            key: ValueKey(seleccionado.id),
                            pedidoId: seleccionado.id,
                            onCerrar: () => setState(() => _seleccionado = null),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// La ficha de un pedido encima de lo que se esté mirando. Pública para que
/// el Resumen la abra en el lugar.
Future<void> mostrarFichaPedido(BuildContext context, String pedidoId) => mostrarHojaLateral(
      context,
      titulo: 'Pedido',
      builder: (_) => FichaPedido(pedidoId: pedidoId),
    );

class _TarjetaPedidoAdmin extends StatelessWidget {
  const _TarjetaPedidoAdmin({required this.pedido, required this.onTap});

  final Pedido pedido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final secundario = MyType.bodySm.copyWith(color: MyColors.secondary);
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(p.codigo, style: MyType.labelLg.copyWith(color: MyColors.tertiary)),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: Text(Formato.haceCuanto(p.creadoEn), style: secundario, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: MySpacing.xs),
              Text(Formato.pesos(p.total), style: MyType.labelLg),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Text(p.comercioNombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Para ${p.clienteNombre ?? 'Cliente'}', style: secundario, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: MySpacing.xs),
          Encoger(
            alineacion: Alignment.centerLeft,
            child: MyBadge(p.estado.label, tone: tonoPedido(p.estado), dot: p.estado == EstadoPedido.pagado),
          ),
        ],
      ),
    );
  }
}

/// Todo el pedido para la administración: en qué paso está y desde cuándo,
/// quién lo pidió, a qué local, qué pidió, cuánto se cobró y qué se puede
/// hacer.
class FichaPedido extends ConsumerWidget {
  const FichaPedido({super.key, required this.pedidoId, this.onCerrar});

  final String pedidoId;

  /// Solo en el panel de la compu: en la hoja la cruz ya la pone la hoja.
  final VoidCallback? onCerrar;

  Future<void> _cancelar(BuildContext context, WidgetRef ref, Pedido p) async {
    final motivo = await pedirTexto(
      context,
      titulo: 'Cancelar ${p.codigo}',
      label: 'Motivo (lo ven el cliente y el local)',
      aceptar: 'Cancelar pedido',
      ayuda: p.cobrado
          ? 'Al cliente se le devuelve todo lo que pagó. Al local no se le cobra penalidad.'
          : 'Todavía no se cobró: no hay nada que devolver.',
    );
    if (motivo == null) return;
    try {
      await ref.read(pedidosRepositoryProvider).cancelar(p.id, motivo);
      if (context.mounted) mostrarAviso(context, 'Pedido ${p.codigo} cancelado');
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(todosLosPedidosProvider).value?.where((x) => x.id == pedidoId).firstOrNull;
    if (p == null) {
      return const MyEmptyState(
        icon: Symbols.search_off,
        title: 'Pedido no encontrado',
        message: 'Puede que sea muy viejo para esta lista.',
      );
    }
    final secundario = MyType.bodySm.copyWith(color: MyColors.secondary);
    const espacio = SizedBox(height: MySpacing.lg);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pedido ${p.codigo}', style: MyType.headlineMd),
                  Text('Entró ${Formato.haceCuanto(p.creadoEn)} · ${p.comercioNombre}', style: secundario),
                ],
              ),
            ),
            if (onCerrar != null) IconButton(onPressed: onCerrar, icon: const Icon(Symbols.close), tooltip: 'Cerrar'),
          ],
        ),
        const SizedBox(height: MySpacing.sm),
        Encoger(
          alineacion: Alignment.centerLeft,
          child: MyBadge(p.estado.label, tone: tonoPedido(p.estado), dot: p.estado == EstadoPedido.pagado),
        ),
        if (p.respondeAntesDe case final limite?) ...[
          const SizedBox(height: MySpacing.sm),
          Text(
            'El local tiene hasta las ${Formato.hora(limite)} para aceptarlo. Si no, se rechaza solo.',
            style: MyType.bodySm.copyWith(color: MyColors.error),
          ),
        ],
        if (p.motivoDelCierre case final motivo?) ...[
          const SizedBox(height: MySpacing.sm),
          Container(
            padding: const EdgeInsets.all(MySpacing.sm),
            decoration: BoxDecoration(color: MyColors.errorContainer, borderRadius: BorderRadius.circular(MyRadius.md)),
            child: Text('Motivo: $motivo', style: MyType.bodySm.copyWith(color: MyColors.onErrorContainer)),
          ),
        ],
        espacio,
        const MyOverline('Recorrido'),
        const SizedBox(height: MySpacing.xs),
        _Pasos(pedido: p),
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
            padding: const EdgeInsets.only(bottom: MySpacing.xs),
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
        if (p.nota != null) Text('Nota: ${p.nota}', style: MyType.bodySm),
        espacio,
        const MyOverline('Cuentas'),
        const SizedBox(height: MySpacing.xs),
        MyRenglon('Productos', Formato.pesos(p.subtotal)),
        MyRenglon(
          'Envío',
          Formato.pesos(p.costoEnvio),
          detalle: p.envioLoPoneElLocal ? 'Plus: el local pone ${Formato.pesos(p.envioCubierto)}' : null,
        ),
        const Divider(height: MySpacing.lg),
        MyRenglon('Pagó el cliente', Formato.pesos(p.total), fuerte: true, color: MyColors.tertiary),
        const SizedBox(height: MySpacing.xs),
        Row(
          children: [
            Icon(p.cobrado ? Symbols.check_circle : Symbols.schedule, size: 18, color: p.cobrado ? MyColors.success : MyColors.secondary),
            const SizedBox(width: MySpacing.xs),
            Expanded(
              child: Text(
                p.cobrado ? 'Cobrado con tarjeta por Mercado Pago' : 'Todavía no se acreditó el pago',
                style: MyType.labelMd,
              ),
            ),
          ],
        ),
        if (p.envioId != null || !p.estado.esFinal) ...[
          espacio,
          Wrap(
            spacing: MySpacing.sm,
            runSpacing: MySpacing.sm,
            children: [
              if (p.envioId != null)
                MyBoton(
                  label: 'Ver el envío',
                  icon: Symbols.route,
                  tipo: MyBotonTipo.secundario,
                  onPressed: () => mostrarFichaEnvio(context, p.envioId!),
                ),
              if (!p.estado.esFinal)
                MyBoton(
                  label: 'Cancelar pedido',
                  icon: Symbols.cancel,
                  tipo: MyBotonTipo.peligro,
                  onPressed: () => _cancelar(context, ref, p),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Los pasos del pedido con la hora de cada uno. Lo que no pasó todavía va
/// apagado; si se cerró sin entregarse, el último paso es el cierre.
class _Pasos extends StatelessWidget {
  const _Pasos({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    final p = pedido;
    final cerradoSinEntregar = p.estado == EstadoPedido.rechazado || p.estado == EstadoPedido.cancelado;
    final pasos = <(String, DateTime?)>[
      ('Lo pidió', p.creadoEn),
      ('Pagó', p.pagadoEn),
      if (!cerradoSinEntregar || p.aceptadoEn != null) ('El local lo aceptó', p.aceptadoEn),
      if (!cerradoSinEntregar || p.listoEn != null) ('Listo para retirar', p.listoEn),
      if (!cerradoSinEntregar) ('Entregado', p.entregadoEn),
      if (cerradoSinEntregar) (p.estado == EstadoPedido.rechazado ? 'Rechazado' : 'Cancelado', p.canceladoEn),
    ];

    return Column(
      children: [
        for (final (rotulo, cuando) in pasos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  cuando == null ? Symbols.radio_button_unchecked : Symbols.check_circle,
                  size: 18,
                  fill: cuando == null ? 0 : 1,
                  color: cuando == null ? MyColors.outline : MyColors.onSurface,
                ),
                const SizedBox(width: MySpacing.xs),
                Expanded(
                  child: Text(
                    rotulo,
                    style: MyType.bodyMd.copyWith(color: cuando == null ? MyColors.secondary : null),
                  ),
                ),
                Text(cuando == null ? '—' : Formato.hora(cuando), style: MyType.labelMd),
              ],
            ),
          ),
      ],
    );
  }
}
