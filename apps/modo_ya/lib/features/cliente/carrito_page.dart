import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'carrito.dart';

/// Carrito y checkout (D3).
///
/// Del diseño no están la propina ni el cupón (no existen en el sistema) y el
/// método de pago figura "a confirmar": todavía no está definido cómo se cobra.
class CarritoPage extends ConsumerStatefulWidget {
  const CarritoPage({super.key});

  @override
  ConsumerState<CarritoPage> createState() => _CarritoPageState();
}

class _CarritoPageState extends ConsumerState<CarritoPage> {
  late final _nota = TextEditingController(text: ref.read(carritoProvider).nota);

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final carrito = ref.read(carritoProvider);
    final direccion = ref.read(direccionActualProvider);
    if (direccion == null) {
      mostrarError(context, 'Elegí a dónde te lo llevamos.');
      return;
    }
    try {
      final id = await ref.read(pedidosRepositoryProvider).crear(
            comercioId: carrito.comercio!.id,
            direccionId: direccion.id,
            items: carrito.items,
            nota: _nota.text,
          );
      ref.read(carritoProvider.notifier).vaciar();
      if (!mounted) return;
      await mostrarExito(
        context,
        titulo: '¡Pedido confirmado!',
        mensaje: 'Ya lo enviamos a ${carrito.comercio!.nombre}.',
      );
      if (mounted) context.go('/cliente/pedidos/$id');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrito = ref.watch(carritoProvider);
    final notifier = ref.read(carritoProvider.notifier);
    final direccion = ref.watch(direccionActualProvider);

    void volver() => context.canPop()
        ? context.pop()
        : context.go(carrito.comercio == null ? '/cliente' : '/cliente/local/${carrito.comercio!.id}');

    if (carrito.vacio) {
      return MyPantallaClara(
        child: MyPagina(
          volver: () => context.go('/cliente'),
          titulo: 'Tu pedido',
          conDock: false,
          children: const [
            MyCard(
              child: MyEmptyState(
                icon: Symbols.shopping_bag,
                title: 'Tu carrito está vacío',
                message: 'Entrá a un local y agregá lo que quieras.',
              ),
            ),
          ],
        ),
      );
    }

    final cotAsync = direccion == null
        ? null
        : ref.watch(cotizacionEnvioProvider((comercioId: carrito.comercio!.id, direccionId: direccion.id)));
    final cot = cotAsync?.value;

    final productos = MyCard(
      padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.xs),
      child: Column(
        children: [
          for (final i in carrito.items) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: MySpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MyImagen(url: i.producto.fotoUrl, ancho: 56, alto: 56, icono: Symbols.restaurant),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.producto.nombre, style: MyType.labelLg),
                        if (i.elegidas.isNotEmpty)
                          Text(i.elegidas.map((o) => o.nombre).join(', '), style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
                        if (i.nota != null) Text('"${i.nota}"', style: MyType.bodySm.copyWith(fontStyle: FontStyle.italic)),
                        const SizedBox(height: MySpacing.xxs),
                        Container(
                          decoration: BoxDecoration(
                            color: MyColors.claroSuperficieAlt,
                            borderRadius: BorderRadius.circular(MyRadius.full),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: i.cantidad == 1 ? 'Quitar' : 'Uno menos',
                                onPressed: () => notifier.cambiarCantidad(i.clave, i.cantidad - 1),
                                icon: Icon(i.cantidad == 1 ? Symbols.delete : Symbols.remove, size: 18),
                              ),
                              Text('${i.cantidad}', style: MyType.labelLg),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Uno más',
                                onPressed: () => notifier.cambiarCantidad(i.clave, i.cantidad + 1),
                                icon: Icon(Symbols.add, size: 18, color: MyColors.onSurface),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(Formato.pesos(i.subtotal), style: MyType.labelLg),
                ],
              ),
            ),
            if (i != carrito.items.last) const Divider(),
          ],
        ],
      ),
    );

    final entrega = direccion == null
        ? MyCard(
            onTap: () => context.go('/cliente/direcciones'),
            child: Row(
              children: [
                const MyIconoCaja(Symbols.add_location, circular: true),
                const SizedBox(width: MySpacing.sm),
                Expanded(child: Text('Agregá tu dirección', style: MyType.labelLg)),
                Icon(Symbols.chevron_right, color: MyColors.claroTextoSecundario),
              ],
            ),
          )
        : MyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Symbols.location_on, color: MyColors.primary, fill: 1),
                    const SizedBox(width: MySpacing.xs),
                    Expanded(child: Text(direccion.calle, style: MyType.headlineSm)),
                    MyBadge(direccion.alias, tone: MyBadgeTone.info),
                  ],
                ),
                if (direccion.referencia != null)
                  Padding(
                    padding: const EdgeInsets.only(top: MySpacing.xxs, left: 28),
                    child: Text('"${direccion.referencia}"', style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
                  ),
                const SizedBox(height: MySpacing.sm),
                MyMapaVista(alto: 130, marcadores: [MyMarcador(punto: LatLng(direccion.lat, direccion.lng), icono: Symbols.home)]),
              ],
            ),
          );

    final nota = TextField(
      controller: _nota,
      onChanged: notifier.setNota,
      maxLines: 2,
      decoration: InputDecoration(
        hintText: 'Nota para el local o el rider (opcional)',
        prefixIcon: Icon(Symbols.edit_note, size: 20),
        fillColor: MyColors.claroSuperficieAlt,
      ),
    );

    final pago = MyCard(
      color: MyColors.primaryFixed,
      shadows: const [],
      child: Row(
        children: [
          Icon(Symbols.payments, color: MyColors.onPrimaryFixed),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Text(
              'Te confirmamos cómo pagar apenas recibamos el pedido. '
              'El local empieza a prepararlo cuando el pago quede confirmado.',
              style: MyType.bodySm.copyWith(color: MyColors.onPrimaryFixed),
            ),
          ),
        ],
      ),
    );

    final resumen = MyCard(
      child: Column(
        children: [
          _Linea('Productos', Formato.pesos(carrito.subtotal)),
          _Linea(
            'Envío MODO YA',
            cotAsync == null
                ? '—'
                : cotAsync.isLoading
                    ? '…'
                    : cot == null
                        ? 'No disponible'
                        : Formato.pesos(cot.costoEnvio),
          ),
          if (cot != null) _Linea('Llega en', '~${cot.minutosEstimados} min'),
          const Divider(height: MySpacing.lg),
          Row(
            children: [
              Text('Total', style: MyType.headlineMd),
              const Spacer(),
              MyNumeroAnimado(valor: carrito.subtotal + (cot?.costoEnvio ?? 0), formato: Formato.pesos, style: MyType.priceHero.copyWith(color: MyColors.onSurface)),
            ],
          ),
          if (cotAsync?.hasError ?? false)
            Padding(
              padding: const EdgeInsets.only(top: MySpacing.xs),
              child: Text('${cotAsync!.error}', style: MyType.bodySm.copyWith(color: MyColors.claroError)),
            ),
        ],
      ),
    );

    final confirmar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyBotonAccion(
          label: 'Confirmar pedido',
          icon: Symbols.shopping_bag,
          onPressed: (direccion == null || cot == null || !(carrito.comercio?.abierto ?? false)) ? null : _confirmar,
        ),
        if (!(carrito.comercio?.abierto ?? true))
          Padding(
            padding: const EdgeInsets.only(top: MySpacing.xs),
            child: Text('El local cerró. Probá más tarde.', style: MyType.bodySm.copyWith(color: MyColors.claroError), textAlign: TextAlign.center),
          ),
      ],
    );

    Widget titulo(String t, {String? accion, VoidCallback? onAccion}) => Padding(
          padding: const EdgeInsets.only(bottom: MySpacing.sm),
          child: MySectionHeader(title: t, actionLabel: accion, onAction: onAccion),
        );

    const espacio = SizedBox(height: MySpacing.lg);
    final izquierda = [
      titulo('Productos (${carrito.cantidad})', accion: 'Agregar más', onAccion: volver),
      productos,
      espacio,
      titulo('Dirección de entrega', accion: 'Cambiar', onAccion: () => context.go('/cliente/direcciones')),
      entrega,
      espacio,
      nota,
    ];
    final derecha = [
      titulo('Resumen'),
      resumen,
      const SizedBox(height: MySpacing.md),
      pago,
      espacio,
      confirmar,
    ];

    return MyPantallaClara(
      child: MyPagina(
        volver: volver,
        rotulo: carrito.comercio!.nombre,
        titulo: 'Tu pedido',
        bajada: 'Revisá y confirmá',
        anchoMaximo: 1180,
        conDock: false,
        children: context.esMovil
            ? [...izquierda, espacio, ...derecha]
            : [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: izquierda)),
                    const SizedBox(width: MySpacing.lg),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: derecha)),
                  ],
                ),
              ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.label, this.valor);

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MySpacing.xs),
        child: Row(
          children: [
            Text(label, style: MyType.bodyMd.copyWith(color: MyColors.claroTextoSecundario)),
            const Spacer(),
            Text(valor, style: MyType.labelLg),
          ],
        ),
      );
}
