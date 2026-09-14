import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Editor del menu del local: secciones, productos, fotos y disponibilidad.
class MenuPage extends ConsumerWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercioId = ref.watch(sesionProvider).comercioId;
    if (comercioId == null) return const SizedBox.shrink();
    final menu = ref.watch(menuDeComercioProvider(comercioId));

    Future<void> nuevaSeccion([SeccionMenu? editar]) async {
      final nombre = await pedirTexto(
        context,
        titulo: editar == null ? 'Nueva seccion' : 'Renombrar seccion',
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

    return Column(
      children: [
        const MyTopBar(zona: 'Mi menu'),
        Expanded(
          child: MyAsync(
            valor: menu,
            onReintentar: () => ref.invalidate(menuDeComercioProvider(comercioId)),
            datos: (m) => RefreshIndicator(
              onRefresh: () => ref.refresh(menuDeComercioProvider(comercioId).future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance,
                ),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/local/producto'),
                          icon: const Icon(Symbols.add, size: 20),
                          label: const Text('Producto'),
                        ),
                      ),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: nuevaSeccion,
                          icon: const Icon(Symbols.playlist_add, size: 20),
                          label: const Text('Seccion'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MySpacing.lg),
                  if (m.productos.isEmpty && m.secciones.isEmpty)
                    const MyEmptyState(
                      icon: Symbols.menu_book,
                      title: 'Tu menu esta vacio',
                      message: 'Crea secciones (Pizzas, Bebidas...) y carga tus productos con foto. '
                          'Es lo que ven los clientes cuando entran a tu local.',
                    ),
                  for (final s in m.secciones) ...[
                    _EncabezadoSeccion(
                      seccion: s,
                      cantidad: m.deSeccion(s.id).length,
                      onRenombrar: () => nuevaSeccion(s),
                      onBorrar: () async {
                        final ok = await confirmar(
                          context,
                          titulo: 'Borrar "${s.nombre}"',
                          mensaje: 'Los productos de la seccion no se borran: quedan "sin seccion".',
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
                      },
                    ),
                    for (final p in m.deSeccion(s.id)) _FilaProducto(producto: p),
                    const SizedBox(height: MySpacing.lg),
                  ],
                  if (m.sinSeccion.isNotEmpty) ...[
                    _EncabezadoSeccion(cantidad: m.sinSeccion.length),
                    for (final p in m.sinSeccion) _FilaProducto(producto: p),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EncabezadoSeccion extends StatelessWidget {
  const _EncabezadoSeccion({
    required this.cantidad,
    this.seccion,
    this.onRenombrar,
    this.onBorrar,
  });

  final SeccionMenu? seccion;
  final int cantidad;
  final VoidCallback? onRenombrar;
  final VoidCallback? onBorrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${seccion?.nombre ?? 'Sin seccion'} ($cantidad)',
              style: MyType.headlineSm,
            ),
          ),
          if (seccion != null)
            PopupMenuButton<int>(
              icon: const Icon(Symbols.more_vert, color: MyColors.secondary),
              onSelected: (v) => v == 0 ? onRenombrar?.call() : onBorrar?.call(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Renombrar')),
                PopupMenuItem(value: 1, child: Text('Borrar seccion')),
              ],
            ),
        ],
      ),
    );
  }
}

class _FilaProducto extends ConsumerWidget {
  const _FilaProducto({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.xs),
      child: MyCard(
        padding: const EdgeInsets.all(MySpacing.sm),
        onTap: () => context.push('/local/producto', extra: producto),
        child: Opacity(
          opacity: producto.disponible ? 1 : 0.55,
          child: Row(
            children: [
              MyImagen(url: producto.fotoUrl, ancho: 64, alto: 64, icono: Symbols.restaurant),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(producto.nombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(Formato.pesos(producto.precio), style: MyType.headlineSm.copyWith(color: MyColors.primary)),
                    Text(
                      [
                        if (!producto.disponible) 'Sin stock',
                        if (producto.tienePersonalizacion) '${producto.opciones.length} opciones',
                        if (producto.fotoUrl == null) 'Sin foto',
                      ].join(' - '),
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
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
                  Text(producto.disponible ? 'Hay' : 'No hay', style: MyType.labelSm),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
