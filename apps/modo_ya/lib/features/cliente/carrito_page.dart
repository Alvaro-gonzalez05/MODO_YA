import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';
import 'carrito.dart';

/// Carrito y checkout (D3).
///
/// Del diseno no estan la propina ni el cupon (no existen en el sistema) y el
/// metodo de pago figura "a confirmar": todavia no esta definido como se cobra.
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
      mostrarError(context, 'Elegi a donde te lo llevamos.');
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
      if (mounted) context.pushReplacement('/cliente/pedido/$id');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final carrito = ref.watch(carritoProvider);
    final notifier = ref.read(carritoProvider.notifier);
    final direccion = ref.watch(direccionActualProvider);
    final direcciones = ref.watch(direccionesProvider);

    final cotAsync = (carrito.comercio == null || direccion == null)
        ? null
        : ref.watch(cotizacionEnvioProvider((comercioId: carrito.comercio!.id, direccionId: direccion.id)));
    final cot = cotAsync?.value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Symbols.arrow_back), onPressed: () => context.pop()),
        title: const Text('Tu pedido'),
      ),
      body: carrito.vacio
          ? const MyEmptyState(
              icon: Symbols.shopping_bag,
              title: 'Tu carrito esta vacio',
              message: 'Entra a un local y agrega lo que quieras.',
            )
          : FormularioCentrado(
              ancho: 580,
              children: [
                MyCard(
                  child: Row(
                    children: [
                      MyImagen(url: carrito.comercio!.logoUrl, ancho: 48, alto: 48, icono: Symbols.storefront),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(carrito.comercio!.nombre, style: MyType.headlineSm),
                            if (cot != null)
                              Text('${cot.minutosEstimados} min de entrega estimada',
                                  style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.lg),
                MySectionHeader(
                  title: 'Productos (${carrito.cantidad})',
                  actionLabel: 'Agregar mas',
                  onAction: () => context.pop(),
                ),
                const SizedBox(height: MySpacing.sm),
                MyCard(
                  padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.xs),
                  child: Column(
                    children: [
                      for (final i in carrito.items) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: MySpacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              MyImagen(url: i.producto.fotoUrl, ancho: 52, alto: 52, icono: Symbols.restaurant),
                              const SizedBox(width: MySpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(i.producto.nombre, style: MyType.labelLg),
                                    if (i.elegidas.isNotEmpty)
                                      Text(i.elegidas.map((o) => o.nombre).join(', '),
                                          style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                                    if (i.nota != null)
                                      Text('"${i.nota}"', style: MyType.bodySm.copyWith(fontStyle: FontStyle.italic)),
                                    Row(
                                      children: [
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => notifier.cambiarCantidad(i.clave, i.cantidad - 1),
                                          icon: Icon(i.cantidad == 1 ? Symbols.delete : Symbols.remove, size: 20),
                                        ),
                                        Text('${i.cantidad}', style: MyType.labelLg),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => notifier.cambiarCantidad(i.clave, i.cantidad + 1),
                                          icon: const Icon(Symbols.add, size: 20, color: MyColors.primary),
                                        ),
                                      ],
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
                ),

                // ---- Direccion -----------------------------------------------
                const SizedBox(height: MySpacing.lg),
                MySectionHeader(
                  title: 'Direccion de entrega',
                  actionLabel: 'Cambiar',
                  onAction: () => context.push('/cliente/direcciones'),
                ),
                const SizedBox(height: MySpacing.sm),
                MyAsync(
                  valor: direcciones,
                  datos: (_) => direccion == null
                      ? MyCard(
                          onTap: () => context.push('/cliente/direcciones'),
                          child: Row(
                            children: [
                              const Icon(Symbols.add_location, color: MyColors.primary),
                              const SizedBox(width: MySpacing.sm),
                              Expanded(child: Text('Agrega tu direccion', style: MyType.labelLg)),
                              const Icon(Symbols.chevron_right, color: MyColors.outline),
                            ],
                          ),
                        )
                      : MyCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Symbols.location_on, color: MyColors.primary, fill: 1),
                                  const SizedBox(width: MySpacing.xs),
                                  Expanded(child: Text(direccion.calle, style: MyType.headlineSm)),
                                  MyBadge(direccion.alias, tone: MyBadgeTone.info),
                                ],
                              ),
                              if (direccion.referencia != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: MySpacing.xxs, left: 28),
                                  child: Text('"${direccion.referencia}"', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                                ),
                              const SizedBox(height: MySpacing.sm),
                              MyMapaVista(
                                alto: 120,
                                marcadores: [
                                  MyMarcador(punto: LatLng(direccion.lat, direccion.lng), icono: Symbols.home),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),

                // ---- Pago y nota ---------------------------------------------
                const SizedBox(height: MySpacing.lg),
                Text('Pago', style: MyType.headlineSm),
                const SizedBox(height: MySpacing.sm),
                MyCard(
                  color: MyColors.secondaryContainer,
                  shadows: const [],
                  child: Row(
                    children: [
                      const Icon(Symbols.payments, color: MyColors.secondary),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Text(
                          'Te confirmamos como pagar apenas recibamos el pedido. '
                          'El local empieza a prepararlo cuando el pago quede confirmado.',
                          style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.md),
                TextField(
                  controller: _nota,
                  onChanged: notifier.setNota,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Nota para el local o el rider (opcional)',
                    prefixIcon: Icon(Symbols.edit_note, size: 20),
                  ),
                ),

                // ---- Resumen -------------------------------------------------
                const SizedBox(height: MySpacing.lg),
                MyCard(
                  child: Column(
                    children: [
                      _Linea('Productos', Formato.pesos(carrito.subtotal)),
                      _Linea(
                        'Envio MODO YA',
                        cotAsync == null
                            ? '-'
                            : cotAsync.isLoading
                                ? '...'
                                : cot == null
                                    ? 'No disponible'
                                    : Formato.pesos(cot.costoEnvio),
                      ),
                      const Divider(height: MySpacing.lg),
                      Row(
                        children: [
                          Text('Total', style: MyType.headlineMd),
                          const Spacer(),
                          Text(
                            Formato.pesos(carrito.subtotal + (cot?.costoEnvio ?? 0)),
                            style: MyType.priceHero.copyWith(color: MyColors.primary),
                          ),
                        ],
                      ),
                      if (cotAsync?.hasError ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: MySpacing.xs),
                          child: Text('${cotAsync!.error}', style: MyType.bodySm.copyWith(color: MyColors.error)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.lg),
                MyBotonAccion(
                  label: 'Confirmar pedido',
                  icon: Symbols.shopping_bag,
                  onPressed: (direccion == null || cot == null || !(carrito.comercio?.abierto ?? false)) ? null : _confirmar,
                ),
                if (!(carrito.comercio?.abierto ?? true))
                  Padding(
                    padding: const EdgeInsets.only(top: MySpacing.xs),
                    child: Text('El local cerro. Proba mas tarde.',
                        style: MyType.bodySm.copyWith(color: MyColors.error), textAlign: TextAlign.center),
                  ),
                const SizedBox(height: MySpacing.xl),
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
            Text(label, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
            const Spacer(),
            Text(valor, style: MyType.labelLg),
          ],
        ),
      );
}
