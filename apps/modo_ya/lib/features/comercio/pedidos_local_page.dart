import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/pedido.dart';

/// Pedidos de la app que le llegan al local, en vivo.
///
/// Flujo: Nuevo → Aceptar → En preparación → Listo (sale a buscar rider) → el
/// rider lo retira y el resto lo sigue el cliente.
///
/// Con lugar es un tablero por columnas, como una comanda. Sin lugar (celular,
/// tableta, ventana angosta) las columnas pasan a grupos uno debajo del otro:
/// cuatro columnas de 140 px no dejaban leer ni el código del pedido.
///
/// Tocar una tarjeta abre el pedido entero en una hoja ([mostrarDetallePedido]).
class PedidosLocalPage extends ConsumerStatefulWidget {
  const PedidosLocalPage({super.key});

  /// Ancho de contenido desde el que entra el tablero. Por debajo, cada
  /// columna queda en menos de ~210 px y la tarjeta ya no se lee.
  static const anchoTablero = 900.0;

  @override
  ConsumerState<PedidosLocalPage> createState() => _PedidosLocalPageState();
}

enum _Vista {
  activos('Por atender'),
  enCamino('En camino'),
  cerrados('Cerrados');

  const _Vista(this.label);
  final String label;

  bool incluye(Pedido p) => switch (this) {
        activos => p.estado.esParaElLocal,
        enCamino => p.estado == EstadoPedido.enCamino,
        cerrados => p.estado.esFinal,
      };
}

/// Las columnas del tablero, que en la lista son los grupos de "Por atender".
const _grupos = [
  ('Nuevos', Symbols.notifications_active, {EstadoPedido.pagado}),
  ('En cocina', Symbols.skillet, {EstadoPedido.aceptado, EstadoPedido.enPreparacion}),
  ('Listos', Symbols.package_2, {EstadoPedido.listo}),
  ('En camino', Symbols.sports_motorsports, {EstadoPedido.enCamino}),
];

class _PedidosLocalPageState extends ConsumerState<PedidosLocalPage> {
  var _vista = _Vista.activos;
  var _verCerrados = false;

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosDelComercioProvider);

    return MyPagina(
      rotulo: 'En vivo',
      titulo: 'Pedidos',
      bajada: 'Los que te hacen desde la app. Suenan apenas llegan.',
      anchoMaximo: 1600,
      children: [
        MyAsync(
          valor: pedidos,
          onReintentar: () => ref.invalidate(pedidosDelComercioProvider),
          datos: (lista) {
            // Dentro de cada grupo, el más viejo arriba: es el que el cliente
            // lleva más tiempo esperando.
            final ordenada = [...lista]..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
            // Por el ancho que queda y no por el de la ventana: con la barra
            // lateral, una compu de 1100 px deja menos lugar que una tableta.
            return LayoutBuilder(
              builder: (context, c) => c.maxWidth >= PedidosLocalPage.anchoTablero
                  ? _tablero(ordenada)
                  : _lista(ordenada),
            );
          },
        ),
      ],
    );
  }

  Widget _tablero(List<Pedido> lista) {
    final cerrados = lista.where((p) => p.estado.esFinal).toList().reversed.toList();
    final enCurso = lista.where((p) => !p.estado.esFinal).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyFiltros<bool>(
          seleccionado: _verCerrados,
          onChanged: (v) => setState(() => _verCerrados = v),
          opciones: [(false, 'En curso', enCurso), (true, 'Cerrados', cerrados.length)],
        ),
        const SizedBox(height: MySpacing.md),
        if (_verCerrados)
          cerrados.isEmpty
              ? const _SinCerrados()
              : _EnColumnas(children: [for (final p in cerrados) TarjetaPedido(pedido: p)])
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < _grupos.length; i++) ...[
                if (i > 0) const SizedBox(width: MySpacing.md),
                Expanded(
                  child: _Columna(
                    titulo: _grupos[i].$1,
                    icono: _grupos[i].$2,
                    pedidos: lista.where((p) => _grupos[i].$3.contains(p.estado)).toList(),
                    destacada: i == 0,
                    // "En cocina" junta dos estados: ahí sí hace falta decir
                    // cuál es cada uno.
                    mostrarEstado: _grupos[i].$3.length > 1,
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _lista(List<Pedido> lista) {
    final visibles = lista.where(_vista.incluye).toList();
    if (_vista != _Vista.activos) visibles.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyFiltros<_Vista>(
          seleccionado: _vista,
          onChanged: (v) => setState(() => _vista = v),
          opciones: [for (final v in _Vista.values) (v, v.label, lista.where(v.incluye).length)],
        ),
        const SizedBox(height: MySpacing.md),
        if (visibles.isEmpty)
          switch (_vista) {
            _Vista.activos => const MyCard(
                child: MyEmptyState(
                  icon: Symbols.receipt_long,
                  title: 'No hay pedidos por atender',
                  message: 'Cuando un cliente te haga un pedido, suena acá y en el inicio.',
                ),
              ),
            _Vista.enCamino => const MyCard(
                child: MyEmptyState(
                  icon: Symbols.sports_motorsports,
                  title: 'Ninguno en camino',
                  message: 'Cuando un rider retire un pedido, lo seguís desde acá.',
                ),
              ),
            _Vista.cerrados => const _SinCerrados(),
          }
        else if (_vista == _Vista.activos)
          ..._porGrupo(visibles)
        else
          _EnColumnas(children: [for (final p in visibles) TarjetaPedido(pedido: p)]),
      ],
    );
  }

  /// Los mismos grupos que las columnas del tablero, uno debajo del otro y
  /// solo los que tienen algo.
  List<Widget> _porGrupo(List<Pedido> visibles) => [
        for (final (titulo, icono, estados) in _grupos.take(3))
          if (visibles.where((p) => estados.contains(p.estado)).toList() case final grupo when grupo.isNotEmpty) ...[
            _TituloGrupo(titulo: titulo, icono: icono, cantidad: grupo.length),
            const SizedBox(height: MySpacing.sm),
            _EnColumnas(
              children: [for (final p in grupo) TarjetaPedido(pedido: p, mostrarEstado: estados.length > 1)],
            ),
            const SizedBox(height: MySpacing.lg),
          ],
      ];
}

class _SinCerrados extends StatelessWidget {
  const _SinCerrados();

  @override
  Widget build(BuildContext context) => const MyCard(
        child: MyEmptyState(
          icon: Symbols.history,
          title: 'Sin pedidos cerrados',
          message: 'Los entregados, rechazados y cancelados aparecen acá.',
        ),
      );
}

class _TituloGrupo extends StatelessWidget {
  const _TituloGrupo({required this.titulo, required this.icono, required this.cantidad});

  final String titulo;
  final IconData icono;
  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 20, color: MyColors.onSurface, fill: 1),
        const SizedBox(width: MySpacing.xs),
        Expanded(child: Text(titulo, style: MyType.headlineSm)),
        MyBadge('$cantidad', tone: MyBadgeTone.dark),
      ],
    );
  }
}

/// Reparte tarjetas en tantas columnas como entren, cada una con su alto.
///
/// No usa `MyGrilla`: esa iguala el alto de la fila, y una tarjeta de dos
/// renglones quedaba estirada al lado de una de seis, con el botón flotando
/// en el medio.
class _EnColumnas extends StatelessWidget {
  const _EnColumnas({required this.children});

  final List<Widget> children;

  static const _anchoMinimo = 320.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final n = ((c.maxWidth + MySpacing.md) / (_anchoMinimo + MySpacing.md)).floor().clamp(1, 4);
        Widget columna(int j) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = j; i < children.length; i += n) ...[
                  if (i >= n) const SizedBox(height: MySpacing.sm),
                  children[i],
                ],
              ],
            );
        if (n == 1) return columna(0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < n; j++) ...[
              if (j > 0) const SizedBox(width: MySpacing.md),
              Expanded(child: columna(j)),
            ],
          ],
        );
      },
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({
    required this.titulo,
    required this.icono,
    required this.pedidos,
    this.destacada = false,
    this.mostrarEstado = false,
  });

  final String titulo;
  final IconData icono;
  final List<Pedido> pedidos;
  final bool destacada;
  final bool mostrarEstado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MySpacing.sm),
      decoration: BoxDecoration(
        color: destacada && pedidos.isNotEmpty ? MyColors.primaryFixed.withValues(alpha: 0.5) : MyColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MyRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(MySpacing.xs, MySpacing.xs, MySpacing.xs, MySpacing.sm),
            child: Row(
              children: [
                Icon(icono, size: 20, color: MyColors.onSurface, fill: 1),
                const SizedBox(width: MySpacing.xs),
                Expanded(child: Text(titulo, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis)),
                MyBadge('${pedidos.length}', tone: pedidos.isEmpty ? MyBadgeTone.neutral : MyBadgeTone.dark),
              ],
            ),
          ),
          if (pedidos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: MySpacing.xl),
              child: Text('Vacío', textAlign: TextAlign.center, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
            )
          else
            for (final p in pedidos) ...[
              TarjetaPedido(pedido: p, mostrarEstado: mostrarEstado),
              const SizedBox(height: MySpacing.sm),
            ],
        ],
      ),
    );
  }
}
