import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/estados_ui.dart';

/// Pedidos de la app que le llegan al local, en vivo.
///
/// Flujo: Nuevo → Aceptar → En preparación → Listo (sale a buscar rider) → el
/// rider lo retira y el resto lo sigue el cliente.
///
/// En la PC es un tablero por columnas, como una comanda. En el celular, una
/// lista con filtros.
class PedidosLocalPage extends ConsumerStatefulWidget {
  const PedidosLocalPage({super.key});

  @override
  ConsumerState<PedidosLocalPage> createState() => _PedidosLocalPageState();
}

enum _Filtro {
  activos('Por atender'),
  enCamino('En camino'),
  cerrados('Cerrados');

  const _Filtro(this.label);
  final String label;

  bool incluye(Pedido p) => switch (this) {
        activos => p.estado.esParaElLocal,
        enCamino => p.estado == EstadoPedido.enCamino,
        cerrados => p.estado.esFinal,
      };
}

class _PedidosLocalPageState extends ConsumerState<PedidosLocalPage> {
  var _filtro = _Filtro.activos;
  var _verCerrados = false;

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosDelComercioProvider);

    return MyPagina(
      rotulo: 'En vivo',
      titulo: 'Pedidos',
      bajada: 'Los que te hacen desde la app. Suenan apenas llegan.',
      anchoMaximo: 1600,
      acciones: [
        if (!context.esMovil)
          MyBoton(
            label: _verCerrados ? 'Ver tablero' : 'Ver cerrados',
            icon: _verCerrados ? Symbols.view_kanban : Symbols.history,
            tipo: MyBotonTipo.secundario,
            onPressed: () => setState(() => _verCerrados = !_verCerrados),
          ),
      ],
      children: [
        MyAsync(
          valor: pedidos,
          onReintentar: () => ref.invalidate(pedidosDelComercioProvider),
          datos: (lista) {
            // Dentro de cada grupo, el más viejo arriba: es el que el cliente
            // lleva más tiempo esperando.
            final ordenada = [...lista]..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));

            if (context.esMovil) return _movil(ordenada);
            if (_verCerrados) {
              final cerrados = ordenada.where((p) => p.estado.esFinal).toList().reversed.toList();
              return cerrados.isEmpty
                  ? const MyCard(child: MyEmptyState(icon: Symbols.history, title: 'Sin pedidos cerrados', message: 'Los entregados, rechazados y cancelados aparecen acá.'))
                  : MyGrilla(anchoMinimo: 320, maxColumnas: 3, children: [for (final p in cerrados) _TarjetaPedido(pedido: p)]);
            }

            List<Pedido> de(Set<EstadoPedido> estados) => ordenada.where((p) => estados.contains(p.estado)).toList();
            final columnas = [
              ('Nuevos', Symbols.notifications_active, de({EstadoPedido.pagado})),
              ('En cocina', Symbols.skillet, de({EstadoPedido.aceptado, EstadoPedido.enPreparacion})),
              ('Listos', Symbols.package_2, de({EstadoPedido.listo})),
              ('En camino', Symbols.sports_motorsports, de({EstadoPedido.enCamino})),
            ];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < columnas.length; i++) ...[
                  if (i > 0) const SizedBox(width: MySpacing.md),
                  Expanded(
                    child: _Columna(titulo: columnas[i].$1, icono: columnas[i].$2, pedidos: columnas[i].$3, destacada: i == 0),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _movil(List<Pedido> lista) {
    final visibles = lista.where(_filtro.incluye).toList();
    if (_filtro == _Filtro.activos) {
      visibles.sort((a, b) {
        final orden = a.estado.index.compareTo(b.estado.index);
        return orden != 0 ? orden : a.creadoEn.compareTo(b.creadoEn);
      });
    } else {
      visibles.sort((a, b) => b.creadoEn.compareTo(a.creadoEn));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyFiltros<_Filtro>(
          seleccionado: _filtro,
          onChanged: (f) => setState(() => _filtro = f),
          opciones: [for (final f in _Filtro.values) (f, f.label, lista.where(f.incluye).length)],
        ),
        const SizedBox(height: MySpacing.md),
        if (visibles.isEmpty)
          MyCard(
            child: MyEmptyState(
              icon: Symbols.receipt_long,
              title: _filtro == _Filtro.activos ? 'No hay pedidos por atender' : 'Nada por acá',
              message: _filtro == _Filtro.activos
                  ? 'Cuando un cliente te haga un pedido, suena acá y en el inicio.'
                  : 'Los pedidos aparecen acá a medida que avanzan.',
            ),
          )
        else
          for (final p in visibles) ...[
            _TarjetaPedido(pedido: p),
            const SizedBox(height: MySpacing.sm),
          ],
      ],
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({required this.titulo, required this.icono, required this.pedidos, this.destacada = false});

  final String titulo;
  final IconData icono;
  final List<Pedido> pedidos;
  final bool destacada;

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
                Expanded(child: Text(titulo, style: MyType.headlineSm)),
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
              _TarjetaPedido(pedido: p),
              const SizedBox(height: MySpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _TarjetaPedido extends ConsumerWidget {
  const _TarjetaPedido({required this.pedido});

  final Pedido pedido;

  Future<void> _hacer(BuildContext context, Future<void> Function() accion) async {
    try {
      await accion();
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(pedidosRepositoryProvider);
    final esNuevo = pedido.estado == EstadoPedido.pagado;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
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
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MyBadge(pedido.estado.label, tone: tonoPedido(pedido.estado), dot: esNuevo),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          Text(pedido.clienteNombre ?? 'Cliente', style: MyType.headlineSm),
          Text(
            [pedido.entrega.calle, if (pedido.entrega.referencia != null) pedido.entrega.referencia!].join(' · '),
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          const Divider(height: MySpacing.lg),
          for (final item in pedido.items)
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
                        for (final o in item.opciones) Text(o, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                        if (item.nota != null)
                          Text('"${item.nota}"', style: MyType.bodySm.copyWith(fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const SizedBox(width: MySpacing.xs),
                  Text(Formato.pesos(item.subtotal), style: MyType.labelMd),
                ],
              ),
            ),
          if (pedido.nota != null) ...[
            const SizedBox(height: MySpacing.xxs),
            Container(
              padding: const EdgeInsets.all(MySpacing.sm),
              decoration: BoxDecoration(color: MyColors.secondaryContainer, borderRadius: BorderRadius.circular(MyRadius.md)),
              child: Text('Nota: ${pedido.nota}', style: MyType.bodySm),
            ),
          ],
          const SizedBox(height: MySpacing.sm),
          Row(
            children: [
              Text('Productos', style: MyType.labelLg),
              const Spacer(),
              Text(Formato.pesos(pedido.subtotal), style: MyType.headlineSm.copyWith(color: MyColors.tertiary)),
            ],
          ),
          Text(
            'El envío (${Formato.pesos(pedido.costoEnvio)}) lo cobra MODO YA.',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          if (pedido.metodoPago != null) ...[
            const SizedBox(height: MySpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: MyBadge(
                switch (pedido.metodoPago!) {
                  MetodoPago.efectivo => 'Paga en efectivo al rider',
                  MetodoPago.tarjeta => 'Paga con tarjeta (posnet del rider)',
                  MetodoPago.transferencia => 'Paga por transferencia',
                  final m => 'Paga con ${m.label.toLowerCase()}',
                },
                tone: MyBadgeTone.info,
                icon: Symbols.payments,
              ),
            ),
          ],
          if (!pedido.estado.esFinal) ...[
            const SizedBox(height: MySpacing.md),
            switch (pedido.estado) {
              EstadoPedido.pagado => Wrap(
                  alignment: WrapAlignment.end,
                  spacing: MySpacing.xs,
                  runSpacing: MySpacing.xs,
                  children: [
                    MyBoton(
                      label: 'Rechazar',
                      tipo: MyBotonTipo.secundario,
                      onPressed: () async {
                        final motivo = await pedirTexto(
                          context,
                          titulo: 'Rechazar ${pedido.codigo}',
                          label: 'Motivo (se lo decimos al cliente)',
                          aceptar: 'Rechazar',
                        );
                        if (motivo != null && context.mounted) {
                          await _hacer(context, () => repo.rechazar(pedido.id, motivo));
                        }
                      },
                    ),
                    MyBoton(
                      label: 'Aceptar pedido',
                      icon: Symbols.check,
                      onPressed: () => _hacer(context, () => repo.aceptar(pedido.id)),
                    ),
                  ],
                ),
              EstadoPedido.aceptado => MyBotonAccion(
                  label: 'Empezar a preparar',
                  icon: Symbols.skillet,
                  onPressed: () => _hacer(context, () => repo.avanzar(pedido.id, EstadoPedido.enPreparacion)),
                ),
              EstadoPedido.enPreparacion => MyBotonAccion(
                  label: 'Listo: llamar rider',
                  icon: Symbols.sports_motorsports,
                  onPressed: () => _hacer(context, () => repo.avanzar(pedido.id, EstadoPedido.listo)),
                ),
              EstadoPedido.listo || EstadoPedido.enCamino => pedido.envioId == null
                  ? const SizedBox.shrink()
                  : MyBoton(
                      label: pedido.estado == EstadoPedido.listo ? 'Ver el rider' : 'Seguir el envío',
                      icon: Symbols.near_me,
                      tipo: MyBotonTipo.secundario,
                      onPressed: () => context.go('/local/envios/${pedido.envioId}'),
                    ),
              _ => const SizedBox.shrink(),
            },
          ],
        ],
      ),
    );
  }
}
