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

/// Lo que se va a pagar: productos más el envío, si ya se sabe cuánto sale.
///
/// Es orientativo, igual que [Carrito.subtotal]: el número que vale lo calcula
/// `crear_pedido` en el servidor.
int _totalConEnvio(Carrito carrito, CotizacionPedido? cot) => carrito.subtotal + (cot?.costoEnvio ?? 0);

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

  void _volver() => context.canPop() ? context.pop() : context.go('/cliente');

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
                      child: MyCircleIconButton(icon: Symbols.arrow_back, onTap: _volver),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: MyImagen(url: comercio.portadaUrl, radio: 0, icono: Symbols.storefront),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(MySpacing.screenEdge),
                      child: _FichaDelLocal(comercio: comercio, cot: cot),
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
                  child: _BarraPedido(carrito: carrito, cot: cot),
                ),
            ],
          );
        },
      ),
    );
  }

  /// PC y tableta: portada y menú en grilla. En la PC el pedido va en un panel
  /// fijo a la derecha; en la tableta, en la barra flotante como en el celular.
  Widget _ancho(Comercio comercio, AsyncValue<Menu> menuAsync, Carrito carrito, CotizacionPedido? cot) {
    final delLocal = !carrito.vacio && carrito.comercio?.id == comercio.id;
    final escritorio = context.esEscritorio;

    final portada = MyCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 200,
            child: MyImagen(url: comercio.portadaUrl, alto: 200, radio: MyRadius.card, icono: Symbols.storefront),
          ),
          Padding(
            padding: const EdgeInsets.all(MySpacing.lg),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: MySpacing.lg,
              runSpacing: MySpacing.sm,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Logo(url: comercio.logoUrl, lado: 64),
                    const SizedBox(width: MySpacing.md),
                    // Flexible: con un nombre largo la fila desbordaba la
                    // tarjeta en vez de pasar a dos renglones.
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(comercio.nombre, style: MyType.headlineLg, maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text(comercio.rubro, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                        ],
                      ),
                    ),
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
              MyArrastreConMouse(
                child: MyFiltros<String?>(
                  seleccionado: _seccionId,
                  onChanged: (v) => setState(() => _seccionId = v),
                  opciones: [
                    (null, 'Todo', m.productos.length),
                    for (final x in secciones) (x.id, x.nombre, m.deSeccion(x.id).length),
                  ],
                ),
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

    final pagina = MyPagina(
      volver: _volver,
      rotulo: comercio.rubro,
      titulo: comercio.nombre,
      bajada: comercio.abierto ? 'Tocá un producto para agregarlo' : 'Ahora no está tomando pedidos. Podés mirar el menú.',
      conDock: false,
      children: [
        portada,
        const SizedBox(height: MySpacing.md),
        menu,
        if (!escritorio && delLocal) const SizedBox(height: 90),
      ],
    );

    if (escritorio) {
      // El panel va afuera del scroll del menú a propósito: adentro se iba
      // para arriba al bajar y, a mitad de un menú largo, no quedaba ningún
      // botón para ir a pagar.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: pagina),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, MySpacing.xl, MySpacing.xxl, MySpacing.xl),
            child: SizedBox(
              width: 340,
              child: Align(
                alignment: Alignment.topCenter,
                child: _PanelPedido(comercio: comercio, cot: cot),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        pagina,
        if (delLocal)
          Positioned(
            left: MySpacing.xxl,
            right: MySpacing.xxl,
            bottom: MySpacing.lg,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _BarraPedido(carrito: carrito, cot: cot),
              ),
            ),
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
        // Fijas debajo de la portada: en un menú largo, para cambiar de
        // sección no hay que volver a subir hasta arriba.
        SliverPersistentHeader(
          pinned: true,
          delegate: _ChipsFijos(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: MySpacing.screenEdge, vertical: MySpacing.xs),
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

/// Los chips de secciones, pegados arriba mientras se baja por el menú.
class _ChipsFijos extends SliverPersistentHeaderDelegate {
  const _ChipsFijos({required this.child});

  final Widget child;

  static const _alto = 56.0;

  @override
  double get minExtent => _alto;

  @override
  double get maxExtent => _alto;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: MyColors.surface, child: SizedBox.expand(child: child));
  }

  // El chip elegido cambia sin que cambie el alto: hay que redibujar igual.
  @override
  bool shouldRebuild(covariant _ChipsFijos oldDelegate) => true;
}

/// Nombre, estado, demora y costo del envío, arriba del menú en el celular.
class _FichaDelLocal extends StatelessWidget {
  const _FichaDelLocal({required this.comercio, required this.cot});

  final Comercio comercio;
  final CotizacionPedido? cot;

  @override
  Widget build(BuildContext context) {
    final cot = this.cot;
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Logo(url: comercio.logoUrl, lado: 52),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(comercio.nombre, style: MyType.headlineLg, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: MySpacing.xs),
              MyBadge(
                comercio.abierto ? 'Abierto' : 'Cerrado',
                tone: comercio.abierto ? MyBadgeTone.success : MyBadgeTone.dark,
                dot: true,
              ),
            ],
          ),
          Text(comercio.rubro, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
          if (cot != null) ...[
            const SizedBox(height: MySpacing.sm),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                MyBadge('${cot.minutosEstimados} min', tone: MyBadgeTone.info, icon: Symbols.schedule),
                MyBadge(Formato.km(cot.distanciaKm), tone: MyBadgeTone.info, icon: Symbols.route),
              ],
            ),
          ],
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
                Expanded(
                  child: Text(
                    cot == null
                        ? 'Agregá tu dirección para ver el envío'
                        : cot.envioGratis
                            ? 'Envío gratis con Plus'
                            : 'Envío ${Formato.pesos(cot.costoEnvio)}',
                    style: MyType.labelLg,
                  ),
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
    );
  }
}

/// "Tu pedido" en la PC: lo que lleva, cuánto suma y el botón para pagar.
///
/// Es alto como su contenido hasta llegar al borde de la ventana; de ahí en
/// más se desplazan los productos y el total con el botón quedan siempre
/// abajo, a la vista.
class _PanelPedido extends ConsumerWidget {
  const _PanelPedido({required this.comercio, required this.cot});

  final Comercio comercio;
  final CotizacionPedido? cot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carrito = ref.watch(carritoProvider);
    final notifier = ref.read(carritoProvider.notifier);
    final delLocal = !carrito.vacio && carrito.comercio?.id == comercio.id;
    final cot = this.cot;
    final gris = MyType.bodyMd.copyWith(color: MyColors.secondary);

    final encabezado = Padding(
      padding: const EdgeInsets.fromLTRB(MySpacing.lg, MySpacing.lg, MySpacing.lg, MySpacing.sm),
      child: Row(
        children: [
          Icon(Symbols.shopping_bag, color: MyColors.onSurface, fill: 1),
          const SizedBox(width: MySpacing.xs),
          Expanded(child: Text('Tu pedido', style: MyType.headlineSm)),
          if (delLocal)
            MyBadge(
              '${carrito.cantidad} ${carrito.cantidad == 1 ? 'producto' : 'productos'}',
              tone: MyBadgeTone.info,
            ),
        ],
      ),
    );

    if (!delLocal) {
      return MyCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            encabezado,
            Padding(
              padding: const EdgeInsets.fromLTRB(MySpacing.lg, 0, MySpacing.lg, MySpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    carrito.vacio
                        ? 'Todavía no agregaste nada. Tocá un producto para sumarlo.'
                        : 'Tenés un pedido abierto en ${carrito.comercio?.nombre}. Si agregás algo de acá, '
                            'se empieza uno nuevo.',
                    style: gris,
                  ),
                  if (!carrito.vacio) ...[
                    const SizedBox(height: MySpacing.md),
                    MyBoton(
                      label: 'Ver ese pedido',
                      icon: Symbols.shopping_bag,
                      tipo: MyBotonTipo.secundario,
                      onPressed: () => context.go('/cliente/carrito'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return MyCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          encabezado,
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: MySpacing.lg),
              itemCount: carrito.items.length,
              separatorBuilder: (_, _) => const Divider(height: MySpacing.lg),
              itemBuilder: (_, n) {
                final i = carrito.items[n];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(i.producto.nombre, style: MyType.labelLg, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (i.elegidas.isNotEmpty)
                      Text(
                        i.elegidas.map((o) => o.nombre).join(', '),
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: MySpacing.xs),
                    Row(
                      children: [
                        MyStepper(
                          valor: i.cantidad,
                          compacto: true,
                          conQuitar: true,
                          onChanged: (c) => notifier.cambiarCantidad(i.clave, c),
                        ),
                        const Spacer(),
                        Text(Formato.pesos(i.subtotal), style: MyType.labelLg),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const Divider(height: MySpacing.xl),
          Padding(
            padding: const EdgeInsets.fromLTRB(MySpacing.lg, 0, MySpacing.lg, MySpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sin dirección el envío no se sabe y "Productos" repetía el
                // mismo número que el total de abajo.
                if (cot != null) _Renglon('Productos', Formato.pesos(carrito.subtotal)),
                _Renglon(
                  'Envío',
                  cot == null
                      ? 'Según tu dirección'
                      : cot.envioGratis
                          ? 'Gratis con Plus'
                          : Formato.pesos(cot.costoEnvio),
                ),
                const SizedBox(height: MySpacing.xxs),
                Row(
                  children: [
                    Expanded(child: Text(cot == null ? 'Subtotal' : 'Total', style: MyType.headlineSm)),
                    MyNumeroAnimado(
                      valor: _totalConEnvio(carrito, cot),
                      formato: Formato.pesos,
                      style: MyType.headlineMd.copyWith(color: MyColors.tertiary),
                    ),
                  ],
                ),
                const SizedBox(height: MySpacing.md),
                MyBotonAccion(
                  label: 'Ir a pagar',
                  icon: Symbols.arrow_forward,
                  onPressed: () async => context.go('/cliente/carrito'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Renglon extends StatelessWidget {
  const _Renglon(this.concepto, this.valor);

  final String concepto;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MySpacing.xxs),
        child: Row(
          children: [
            Expanded(child: Text(concepto, style: MyType.bodyMd.copyWith(color: MyColors.secondary))),
            Text(valor, style: MyType.labelLg),
          ],
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
    // Más chica en un celular angosto: a 360 px una foto de 110 dejaba el
    // nombre y el precio apretados en media tarjeta.
    final lado = MediaQuery.sizeOf(context).width < 400 ? 92.0 : 110.0;
    return MyCard(
      onTap: habilitado ? onAgregar : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(producto.nombre, style: MyType.headlineSm, maxLines: 2, overflow: TextOverflow.ellipsis),
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
                    Expanded(
                      child: MyPrecio(
                        precio: Formato.pesos(producto.precio),
                        precioLista: producto.enPromocion ? Formato.pesos(producto.precioLista!) : null,
                        descuento: producto.descuento,
                      ),
                    ),
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
            MyImagen(url: producto.fotoUrl, ancho: lado, alto: lado, radio: MyRadius.lg),
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
                      MyPrecio(
                        precio: Formato.pesos(p.precio),
                        precioLista: p.enPromocion ? Formato.pesos(p.precioLista!) : null,
                        descuento: p.descuento,
                      ),
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

/// Barra flotante del celular y la tableta: cuánto lleva y el botón para
/// verlo. Está mientras haya algo de este local en el carrito.
class _BarraPedido extends StatelessWidget {
  const _BarraPedido({required this.carrito, required this.cot});

  final Carrito carrito;
  final CotizacionPedido? cot;

  @override
  Widget build(BuildContext context) {
    return MyApareceEn(
      desplazamiento: 40,
      duracion: const Duration(milliseconds: 420),
      child: Semantics(
        button: true,
        label: 'Ver pedido',
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ver pedido',
                          style: MyType.headlineSm.copyWith(color: MyColors.inverseOnSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Sin dirección no se sabe el envío: que no se lea el
                        // subtotal como si fuera lo que se va a pagar.
                        Text(
                          cot == null ? 'Sin contar el envío' : 'Total con envío',
                          style: MyType.bodySm.copyWith(color: MyColors.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MySpacing.xs),
                  MyNumeroAnimado(
                    valor: _totalConEnvio(carrito, cot),
                    formato: Formato.pesos,
                    style: MyType.headlineSm.copyWith(color: MyColors.primary),
                  ),
                  Icon(Symbols.chevron_right, color: MyColors.primary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo cuadrado del local con un borde fino, como en la tarjeta del inicio.
class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.lado});

  final String? url;
  final double lado;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: MyColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(MyRadius.lg + 2),
          border: Border.all(color: MyColors.outlineVariant),
        ),
        child: MyImagen(url: url, ancho: lado, alto: lado, radio: MyRadius.lg, icono: Symbols.storefront),
      );
}
