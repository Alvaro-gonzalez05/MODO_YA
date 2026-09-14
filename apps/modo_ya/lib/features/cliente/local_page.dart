import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'carrito.dart';
import 'producto_sheet.dart';

/// Menu del local (D2).
class LocalPage extends ConsumerStatefulWidget {
  const LocalPage({super.key, required this.comercioId});

  final String comercioId;

  @override
  ConsumerState<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends ConsumerState<LocalPage> {
  String? _seccionId;

  Future<void> _agregar(Comercio comercio, Producto p) async {
    final carrito = ref.read(carritoProvider.notifier);
    if (!carrito.puedeAgregarDe(comercio)) {
      final ok = await confirmar(
        context,
        titulo: 'Empezar un pedido nuevo?',
        mensaje: 'Tenes productos de ${ref.read(carritoProvider).comercio?.nombre}. '
            'Un pedido es de un solo local: si seguis, se vacia el carrito.',
        aceptar: 'Vaciar y seguir',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    final item = await ProductoSheet.mostrar(context, p);
    if (item == null) return;
    carrito.agregar(comercio, item);
    if (mounted) mostrarAviso(context, '${item.cantidad}x ${p.nombre} agregado');
  }

  @override
  Widget build(BuildContext context) {
    final comercioAsync = ref.watch(comercioPorIdProvider(widget.comercioId));
    final menuAsync = ref.watch(menuPublicoProvider(widget.comercioId));
    final carrito = ref.watch(carritoProvider);
    final direccion = ref.watch(direccionActualProvider);

    return Scaffold(
      body: MyAsync(
        valor: comercioAsync,
        datos: (comercio) {
          if (comercio == null) {
            return const MyEmptyState(title: 'Local no disponible', message: 'Puede que ya no este en MODO YA.');
          }
          final cot = direccion == null
              ? null
              : ref.watch(cotizacionEnvioProvider((comercioId: comercio.id, direccionId: direccion.id))).value;

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 200,
                    backgroundColor: MyColors.surface,
                    leading: Padding(
                      padding: const EdgeInsets.all(6),
                      child: MyCircleIconButton(
                        icon: Symbols.arrow_back,
                        onTap: () => context.canPop() ? context.pop() : context.go('/cliente'),
                      ),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: MyImagen(url: comercio.logoUrl, radio: 0, icono: Symbols.storefront),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(MySpacing.screenEdge),
                      child: MyCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(comercio.nombre, style: MyType.headlineLg)),
                                MyBadge(
                                  comercio.abierto ? 'Abierto' : 'Cerrado',
                                  tone: comercio.abierto ? MyBadgeTone.success : MyBadgeTone.dark,
                                  dot: true,
                                ),
                              ],
                            ),
                            Text(comercio.rubro, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                            const SizedBox(height: MySpacing.sm),
                            Wrap(
                              spacing: MySpacing.xs,
                              runSpacing: MySpacing.xs,
                              children: [
                                if (cot != null) ...[
                                  MyBadge('${cot.minutosEstimados} min', tone: MyBadgeTone.info, icon: Symbols.schedule),
                                  MyBadge(Formato.km(cot.distanciaKm), tone: MyBadgeTone.info, icon: Symbols.route),
                                ],
                              ],
                            ),
                            const SizedBox(height: MySpacing.sm),
                            Container(
                              padding: const EdgeInsets.all(MySpacing.sm),
                              decoration: BoxDecoration(
                                color: MyColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(MyRadius.md),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Symbols.sports_motorsports, size: 20, color: MyColors.primary),
                                  const SizedBox(width: MySpacing.xs),
                                  Text(
                                    cot == null
                                        ? 'Agrega tu direccion para ver el envio'
                                        : 'Envio ${Formato.pesos(cot.costoEnvio)}',
                                    style: MyType.labelLg,
                                  ),
                                ],
                              ),
                            ),
                            if (!comercio.abierto) ...[
                              const SizedBox(height: MySpacing.sm),
                              Text(
                                'Ahora no esta tomando pedidos. Podes mirar el menu.',
                                style: MyType.bodySm.copyWith(color: MyColors.error),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  ...menuAsync.when(
                    loading: () => [const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()))],
                    error: (e, _) => [SliverToBoxAdapter(child: MyEmptyState(title: 'No pudimos cargar el menu', message: '$e'))],
                    data: (menu) => _slivers(comercio, menu),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              ),
              if (!carrito.vacio && carrito.comercio?.id == comercio.id)
                Positioned(
                  left: MySpacing.screenEdge,
                  right: MySpacing.screenEdge,
                  bottom: MySpacing.lg + MediaQuery.paddingOf(context).bottom,
                  child: _BarraPedido(carrito: carrito),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _slivers(Comercio comercio, Menu menu) {
    if (menu.productos.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: MyEmptyState(icon: Symbols.menu_book, title: 'Menu en armado', message: 'Este local todavia no cargo productos.'),
        ),
      ];
    }
    final secciones = menu.secciones.where((s) => menu.deSeccion(s.id).isNotEmpty).toList();
    final visibles = _seccionId == null ? secciones : secciones.where((s) => s.id == _seccionId).toList();

    return [
      if (secciones.length > 1)
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: MySpacing.screenEdge),
              children: [
                MyChip('Todo', selected: _seccionId == null, onTap: () => setState(() => _seccionId = null)),
                for (final s in secciones) ...[
                  const SizedBox(width: MySpacing.xs),
                  MyChip(s.nombre, selected: _seccionId == s.id, onTap: () => setState(() => _seccionId = s.id)),
                ],
              ],
            ),
          ),
        ),
      for (final s in visibles) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.lg, MySpacing.screenEdge, MySpacing.sm),
            child: Text(s.nombre, style: MyType.headlineMd),
          ),
        ),
        _listaProductos(comercio, menu.deSeccion(s.id)),
      ],
      if (_seccionId == null && menu.sinSeccion.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.lg, MySpacing.screenEdge, MySpacing.sm),
            child: Text(secciones.isEmpty ? 'Menu' : 'Otros', style: MyType.headlineMd),
          ),
        ),
        _listaProductos(comercio, menu.sinSeccion),
      ],
    ];
  }

  Widget _listaProductos(Comercio comercio, List<Producto> productos) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: MySpacing.screenEdge),
        sliver: SliverList.separated(
          itemCount: productos.length,
          separatorBuilder: (_, _) => const SizedBox(height: MySpacing.sm),
          itemBuilder: (_, i) => _TarjetaProducto(
            producto: productos[i],
            habilitado: comercio.abierto,
            onAgregar: () => _agregar(comercio, productos[i]),
          ),
        ),
      );
}

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto, required this.habilitado, required this.onAgregar});

  final Producto producto;
  final bool habilitado;
  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      onTap: habilitado ? onAgregar : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(producto.nombre, style: MyType.headlineSm),
                if (producto.descripcion != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    producto.descripcion!,
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: MySpacing.sm),
                Row(
                  children: [
                    Text(Formato.pesos(producto.precio), style: MyType.headlineMd.copyWith(color: MyColors.primary)),
                    const Spacer(),
                    if (habilitado)
                      MyCircleIconButton(
                        icon: Symbols.add,
                        size: 40,
                        background: MyColors.primary,
                        foreground: MyColors.onPrimary,
                        onTap: onAgregar,
                      ),
                  ],
                ),
                if (producto.tienePersonalizacion)
                  Text('Personalizable', style: MyType.labelSm.copyWith(color: MyColors.secondary)),
              ],
            ),
          ),
          if (producto.fotoUrl != null) ...[
            const SizedBox(width: MySpacing.sm),
            MyImagen(url: producto.fotoUrl, ancho: 110, alto: 110, radio: MyRadius.lg),
          ],
        ],
      ),
    );
  }
}

class _BarraPedido extends StatelessWidget {
  const _BarraPedido({required this.carrito});

  final Carrito carrito;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MyColors.primaryContainer,
      shape: const StadiumBorder(),
      elevation: 8,
      shadowColor: MyColors.primary.withValues(alpha: 0.4),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => context.push('/cliente/carrito'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white,
                child: Text('${carrito.cantidad}', style: MyType.labelLg.copyWith(color: MyColors.primary)),
              ),
              const SizedBox(width: MySpacing.sm),
              Text('Ver pedido', style: MyType.headlineSm.copyWith(color: Colors.white)),
              const Spacer(),
              Text(Formato.pesos(carrito.subtotal), style: MyType.headlineSm.copyWith(color: Colors.white)),
              const Icon(Symbols.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
