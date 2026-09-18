import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'carrito.dart';
import 'producto_sheet.dart';

/// Menú del local (D2). En el celular, lista con barra de pedido abajo; en la
/// PC, grilla con el pedido en un panel al costado.
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
        titulo: '¿Empezar un pedido nuevo?',
        mensaje: 'Tenés productos de ${ref.read(carritoProvider).comercio?.nombre}. '
            'Un pedido es de un solo local: si seguís, se vacía el carrito.',
        aceptar: 'Vaciar y seguir',
      );
      if (!ok) return;
    }
    if (!mounted) return;
    final item = await ProductoSheet.mostrar(context, p);
    if (item == null) return;
    carrito.agregar(comercio, item);
    if (mounted) mostrarAviso(context, '${item.cantidad}× ${p.nombre} agregado');
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
            return const MyEmptyState(title: 'Local no disponible', message: 'Puede que ya no esté en MODO YA.');
          }
          final cot = direccion == null
              ? null
              : ref.watch(cotizacionEnvioProvider((comercioId: comercio.id, direccionId: direccion.id))).value;

          if (!context.esMovil) return _ancho(comercio, menuAsync, carrito, cot);

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
                                  Icon(Symbols.sports_motorsports, size: 20, color: MyColors.tertiary),
                                  const SizedBox(width: MySpacing.xs),
                                  Text(
                                    cot == null
                                        ? 'Agregá tu dirección para ver el envío'
                                        : 'Envío ${Formato.pesos(cot.costoEnvio)}',
                                    style: MyType.labelLg,
                                  ),
                                ],
                              ),
                            ),
                            if (!comercio.abierto) ...[
                              const SizedBox(height: MySpacing.sm),
                              Text(
                                'Ahora no está tomando pedidos. Podés mirar el menú.',
                                style: MyType.bodySm.copyWith(color: MyColors.error),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  ...menuAsync.when(
                    loading: () => [const SliverToBoxAdapter(child: MyCargando())],
                    error: (e, _) => [SliverToBoxAdapter(child: MyEmptyState(title: 'No pudimos cargar el menú', message: '$e'))],
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

  /// PC y tableta: portada, menú en grilla y el pedido en un panel a la derecha.
  Widget _ancho(Comercio comercio, AsyncValue<Menu> menuAsync, Carrito carrito, CotizacionPedido? cot) {
    final delLocal = !carrito.vacio && carrito.comercio?.id == comercio.id;

    final portada = MyCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyImagen(url: comercio.logoUrl, alto: 200, radio: MyRadius.card, icono: Symbols.storefront),
          Padding(
            padding: const EdgeInsets.all(MySpacing.lg),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: MySpacing.lg,
              runSpacing: MySpacing.sm,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(comercio.nombre, style: MyType.headlineLg),
                    Text(comercio.rubro, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  ],
                ),
                Wrap(
                  spacing: MySpacing.xs,
                  runSpacing: MySpacing.xs,
                  children: [
                    MyBadge(
                      comercio.abierto ? 'Abierto' : 'Cerrado',
                      tone: comercio.abierto ? MyBadgeTone.success : MyBadgeTone.dark,
                      dot: true,
                    ),
                    if (cot != null) ...[
                      MyBadge('${cot.minutosEstimados} min', tone: MyBadgeTone.info, icon: Symbols.schedule),
                      MyBadge('Envío ${Formato.pesos(cot.costoEnvio)}', tone: MyBadgeTone.info, icon: Symbols.sports_motorsports),
                    ] else
                      const MyBadge('Agregá tu dirección para ver el envío', tone: MyBadgeTone.info),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final Widget menu = menuAsync.when(
      loading: () => const MyCargando(),
      error: (e, _) => MyEmptyState(title: 'No pudimos cargar el menú', message: '$e'),
      data: (m) {
        if (m.productos.isEmpty) {
          return const MyCard(
            child: MyEmptyState(icon: Symbols.menu_book, title: 'Menú en armado', message: 'Este local todavía no cargó productos.'),
          );
        }
        final secciones = m.secciones.where((x) => m.deSeccion(x.id).isNotEmpty).toList();
        final visibles = _seccionId == null ? secciones : secciones.where((x) => x.id == _seccionId).toList();
        Widget grilla(List<Producto> productos) => MyGrilla(
              anchoMinimo: 260,
              maxColumnas: 3,
              children: [
                for (final pr in productos)
                  _TarjetaProductoAncha(producto: pr, habilitado: comercio.abierto, onAgregar: () => _agregar(comercio, pr)),
              ],
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (secciones.length > 1)
              MyFiltros<String?>(
                seleccionado: _seccionId,
                onChanged: (v) => setState(() => _seccionId = v),
                opciones: [
                  (null, 'Todo', m.productos.length),
                  for (final x in secciones) (x.id, x.nombre, m.deSeccion(x.id).length),
                ],
              ),
            for (final x in visibles) ...[
              const SizedBox(height: MySpacing.lg),
              Text(x.nombre, style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),
              grilla(m.deSeccion(x.id)),
            ],
            if (_seccionId == null && m.sinSeccion.isNotEmpty) ...[
              const SizedBox(height: MySpacing.lg),
              Text(secciones.isEmpty ? 'Menú' : 'Otros', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),
              grilla(m.sinSeccion),
            ],
          ],
        );
      },
    );

    final panel = MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Symbols.shopping_bag, color: MyColors.onSurface, fill: 1),
              const SizedBox(width: MySpacing.xs),
              Text('Tu pedido', style: MyType.headlineSm),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          if (!delLocal)
            Text(
              carrito.vacio
                  ? 'Todavía no agregaste nada. Tocá un producto para sumarlo.'
                  : 'Tenés un pedido abierto en ${carrito.comercio?.nombre}.',
              style: MyType.bodyMd.copyWith(color: MyColors.secondary),
            )
          else ...[
            for (final i in carrito.items)
              Padding(
                padding: const EdgeInsets.only(bottom: MySpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 30, child: Text('${i.cantidad}×', style: MyType.labelLg.copyWith(color: MyColors.tertiary))),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.producto.nombre, style: MyType.labelLg),
                          if (i.elegidas.isNotEmpty)
                            Text(i.elegidas.map((o) => o.nombre).join(', '), style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                        ],
                      ),
                    ),
                    Text(Formato.pesos(i.subtotal), style: MyType.labelMd),
                  ],
                ),
              ),
            const Divider(height: MySpacing.lg),
            Row(
              children: [
                Text('Productos', style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                const Spacer(),
                Text(Formato.pesos(carrito.subtotal), style: MyType.labelLg),
              ],
            ),
            if (cot != null)
              Row(
                children: [
                  Text('Envío', style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  const Spacer(),
                  Text(Formato.pesos(cot.costoEnvio), style: MyType.labelLg),
                ],
              ),
            const SizedBox(height: MySpacing.md),
            MyBotonAccion(
              label: 'Ver pedido · ${Formato.pesos(carrito.subtotal + (cot?.costoEnvio ?? 0))}',
              icon: Symbols.arrow_forward,
              onPressed: () async => context.go('/cliente/carrito'),
            ),
          ],
        ],
      ),
    );

    return Stack(
      children: [
        MyPagina(
          volver: () => context.canPop() ? context.pop() : context.go('/cliente'),
          rotulo: comercio.rubro,
          titulo: comercio.nombre,
          bajada: comercio.abierto ? 'Tocá un producto para agregarlo' : 'Ahora no está tomando pedidos. Podés mirar el menú.',
          conDock: false,
          children: [
            MyConPanel(
              anchoPanel: 340,
              principal: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [portada, const SizedBox(height: MySpacing.md), menu],
              ),
              panel: panel,
            ),
            if (!context.esEscritorio && delLocal) const SizedBox(height: 90),
          ],
        ),
        if (!context.esEscritorio && delLocal)
          Positioned(
            left: MySpacing.xxl,
            right: MySpacing.xxl,
            bottom: MySpacing.lg,
            child: _BarraPedido(carrito: carrito),
          ),
      ],
    );
  }

  List<Widget> _slivers(Comercio comercio, Menu menu) {
    if (menu.productos.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: MyEmptyState(icon: Symbols.menu_book, title: 'Menú en armado', message: 'Este local todavía no cargó productos.'),
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
            child: Text(secciones.isEmpty ? 'Menú' : 'Otros', style: MyType.headlineMd),
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
                    Text(Formato.pesos(producto.precio), style: MyType.headlineMd.copyWith(color: MyColors.onSurface)),
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

class _TarjetaProductoAncha extends StatelessWidget {
  const _TarjetaProductoAncha({required this.producto, required this.habilitado, required this.onAgregar});

  final Producto producto;
  final bool habilitado;
  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    return MyCard(
      padding: EdgeInsets.zero,
      onTap: habilitado ? onAgregar : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyImagen(url: p.fotoUrl, alto: 160, radio: MyRadius.card, icono: Symbols.restaurant),
          Padding(
            padding: const EdgeInsets.fromLTRB(MySpacing.md, MySpacing.sm, MySpacing.md, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre, style: MyType.headlineSm, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (p.descripcion != null)
                  Text(p.descripcion!, style: MyType.bodySm.copyWith(color: MyColors.secondary), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(MySpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Formato.pesos(p.precio), style: MyType.headlineMd.copyWith(color: MyColors.onSurface)),
                      if (p.tienePersonalizacion) Text('Personalizable', style: MyType.labelSm.copyWith(color: MyColors.secondary)),
                    ],
                  ),
                ),
                if (habilitado)
                  MyCircleIconButton(
                    icon: Symbols.add,
                    size: 42,
                    background: MyColors.primary,
                    foreground: MyColors.onPrimary,
                    onTap: onAgregar,
                  ),
              ],
            ),
          ),
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
    return MyApareceEn(
      desplazamiento: 40,
      duracion: const Duration(milliseconds: 420),
      child: MyPressable(
        escala: 0.97,
        onTap: () => context.go('/cliente/carrito'),
        child: Material(
          color: MyColors.dock,
          shape: const StadiumBorder(),
          elevation: 10,
          shadowColor: MyColors.primary.withValues(alpha: 0.45),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
            child: Row(
              children: [
                MyPop(
                  disparador: carrito.cantidad,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: MyColors.primary,
                    child: Text('${carrito.cantidad}', style: MyType.labelLg.copyWith(color: MyColors.onPrimary)),
                  ),
                ),
                const SizedBox(width: MySpacing.sm),
                Text('Ver pedido', style: MyType.headlineSm.copyWith(color: MyColors.inverseOnSurface)),
                const Spacer(),
                MyNumeroAnimado(
                  valor: carrito.subtotal,
                  formato: Formato.pesos,
                  style: MyType.headlineSm.copyWith(color: MyColors.primary),
                ),
                Icon(Symbols.chevron_right, color: MyColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
