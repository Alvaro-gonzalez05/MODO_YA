import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Editor del menú del local: secciones, productos, fotos y disponibilidad.
/// En la PC los productos van en grilla con la foto grande; en el celular, en
/// lista.
class MenuPage extends ConsumerWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercioId = ref.watch(sesionProvider).comercioId;
    if (comercioId == null) return const SizedBox.shrink();
    final menu = ref.watch(menuDeComercioProvider(comercioId));

    Future<void> seccion([SeccionMenu? editar]) async {
      final nombre = await pedirTexto(
        context,
        titulo: editar == null ? 'Nueva sección' : 'Renombrar sección',
        label: 'Ej: Pizzas, Empanadas, Bebidas',
        aceptar: 'Guardar',
        inicial: editar?.nombre,
      );
      if (nombre == null) return;
      try {
        await ref.read(catalogoRepositoryProvider).guardarSeccion(
              comercioId: comercioId,
              nombre: nombre,
              id: editar?.id,
              orden: editar?.orden ?? (menu.value?.secciones.length ?? 0),
            );
        ref.invalidate(menuDeComercioProvider(comercioId));
      } catch (e) {
        if (context.mounted) mostrarError(context, e);
      }
    }

    Future<void> borrarSeccion(SeccionMenu s) async {
      final ok = await confirmar(
        context,
        titulo: 'Borrar "${s.nombre}"',
        mensaje: 'Los productos de la sección no se borran: quedan "sin sección".',
        aceptar: 'Borrar',
        peligroso: true,
      );
      if (!ok) return;
      try {
        await ref.read(catalogoRepositoryProvider).borrarSeccion(s.id);
        ref.invalidate(menuDeComercioProvider(comercioId));
      } catch (e) {
        if (context.mounted) mostrarError(context, e);
      }
    }

    final total = menu.value?.productos.length ?? 0;
    final sinStock = menu.value?.productos.where((p) => !p.disponible).length ?? 0;

    return MyPagina(
      rotulo: 'Catálogo',
      titulo: 'Menú',
      bajada: total == 0
          ? 'Lo que ven los clientes cuando entran a tu local'
          : '$total productos${sinStock > 0 ? ' · $sinStock sin stock' : ''}',
      onRefresh: () => ref.refresh(menuDeComercioProvider(comercioId).future),
      acciones: [
        MyBoton(label: 'Sección', icon: Symbols.playlist_add, tipo: MyBotonTipo.secundario, onPressed: seccion),
        MyBoton(label: 'Producto', icon: Symbols.add, onPressed: () => context.go('/local/menu/producto')),
      ],
      children: [
        MyAsync(
          valor: menu,
          onReintentar: () => ref.invalidate(menuDeComercioProvider(comercioId)),
          datos: (m) {
            if (m.productos.isEmpty && m.secciones.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.menu_book,
                  title: 'Tu menú está vacío',
                  message: 'Creá secciones (Pizzas, Bebidas…) y cargá tus productos con foto. '
                      'Es lo que ven los clientes cuando entran a tu local.',
                  action: MyBoton(label: 'Cargar el primer producto', icon: Symbols.add, onPressed: () => context.go('/local/menu/producto')),
                ),
              );
            }

            Widget bloque(SeccionMenu? s, List<Producto> productos) => Padding(
                  padding: const EdgeInsets.only(bottom: MySpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: s?.nombre ?? 'Sin sección', style: MyType.headlineMd),
                                TextSpan(text: '  ${productos.length}', style: MyType.labelLg.copyWith(color: MyColors.secondary)),
                              ]),
                            ),
                          ),
                          if (s != null)
                            PopupMenuButton<int>(
                              tooltip: 'Opciones de la sección',
                              icon: const Icon(Symbols.more_horiz, color: MyColors.secondary),
                              onSelected: (v) => v == 0 ? seccion(s) : borrarSeccion(s),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 0, child: Text('Renombrar')),
                                PopupMenuItem(value: 1, child: Text('Borrar sección')),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: MySpacing.sm),
                      if (productos.isEmpty)
                        Text('Sin productos todavía.', style: MyType.bodySm.copyWith(color: MyColors.secondary))
                      else if (context.esMovil)
                        for (final p in productos) ...[_FilaProducto(producto: p), const SizedBox(height: MySpacing.xs)]
                      else
                        MyGrilla(
                          anchoMinimo: 250,
                          maxColumnas: 5,
                          children: [for (final p in productos) _TarjetaProducto(producto: p)],
                        ),
                    ],
                  ),
                );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in m.secciones) bloque(s, m.deSeccion(s.id)),
                if (m.sinSeccion.isNotEmpty) bloque(null, m.sinSeccion),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Disponible extends ConsumerWidget {
  const _Disponible({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(producto.disponible ? 'Hay' : 'Sin stock', style: MyType.labelMd.copyWith(color: MyColors.secondary)),
        const SizedBox(width: MySpacing.xxs),
        Switch(
          value: producto.disponible,
          onChanged: (v) async {
            try {
              await ref.read(catalogoRepositoryProvider).setDisponible(producto.id, v);
              ref.invalidate(menuDeComercioProvider(producto.comercioId));
            } catch (e) {
              if (context.mounted) mostrarError(context, e);
            }
          },
        ),
      ],
    );
  }
}

String _detalle(Producto p) => [
      if (p.tienePersonalizacion) '${p.opciones.length} ${p.opciones.length == 1 ? 'opción' : 'opciones'}',
      if (p.fotoUrl == null) 'Sin foto',
    ].join(' · ');

class _TarjetaProducto extends StatelessWidget {
  const _TarjetaProducto({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    return MyCard(
      padding: EdgeInsets.zero,
      onTap: () => context.go('/local/menu/producto', extra: p),
      child: Opacity(
        opacity: p.disponible ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyImagen(url: p.fotoUrl, alto: 150, radio: MyRadius.card, icono: Symbols.restaurant),
            Padding(
              padding: const EdgeInsets.fromLTRB(MySpacing.md, MySpacing.sm, MySpacing.sm, MySpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nombre, style: MyType.labelLg.copyWith(fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if ((p.descripcion ?? '').isNotEmpty)
                    Text(p.descripcion!, style: MyType.bodySm.copyWith(color: MyColors.secondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(MySpacing.md, 0, MySpacing.xs, MySpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Formato.pesos(p.precio), style: MyType.headlineSm.copyWith(color: MyColors.tertiary)),
                        if (_detalle(p).isNotEmpty) Text(_detalle(p), style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                      ],
                    ),
                  ),
                  _Disponible(producto: p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaProducto extends StatelessWidget {
  const _FilaProducto({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context) {
    final p = producto;
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      onTap: () => context.go('/local/menu/producto', extra: p),
      child: Opacity(
        opacity: p.disponible ? 1 : 0.6,
        child: Row(
          children: [
            MyImagen(url: p.fotoUrl, ancho: 68, alto: 68, icono: Symbols.restaurant),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nombre, style: MyType.labelLg, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(Formato.pesos(p.precio), style: MyType.headlineSm.copyWith(color: MyColors.tertiary)),
                  if (_detalle(p).isNotEmpty) Text(_detalle(p), style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SoloSwitch(producto: p),
                Text(p.disponible ? 'Hay' : 'Sin stock', style: MyType.labelSm.copyWith(color: MyColors.secondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SoloSwitch extends ConsumerWidget {
  const _SoloSwitch({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Switch(
      value: producto.disponible,
      onChanged: (v) async {
        try {
          await ref.read(catalogoRepositoryProvider).setDisponible(producto.id, v);
          ref.invalidate(menuDeComercioProvider(producto.comercioId));
        } catch (e) {
          if (context.mounted) mostrarError(context, e);
        }
      },
    );
  }
}
