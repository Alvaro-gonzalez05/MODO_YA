import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Personalización de un producto antes de agregarlo (D2).
class ProductoSheet extends StatefulWidget {
  const ProductoSheet({super.key, required this.producto, this.enVentana = false});

  final Producto producto;
  final bool enVentana;

  /// Hoja inferior en el celular; ventana centrada en la PC.
  static Future<ItemCarrito?> mostrar(BuildContext context, Producto producto) {
    if (context.esMovil) {
      return showModalBottomSheet<ItemCarrito>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => ProductoSheet(producto: producto),
      );
    }
    return showDialog<ItemCarrito>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: MyColors.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
          child: ProductoSheet(producto: producto, enVentana: true),
        ),
      ),
    );
  }

  @override
  State<ProductoSheet> createState() => _ProductoSheetState();
}

class _ProductoSheetState extends State<ProductoSheet> {
  var _cantidad = 1;
  final _nota = TextEditingController();

  /// Por grupo, los items elegidos.
  late final Map<int, List<OpcionItem>> _elegidas = {
    for (var i = 0; i < widget.producto.opciones.length; i++) i: [],
  };

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  List<OpcionItem> get _todas => _elegidas.values.expand((e) => e).toList();

  int get _unitario => widget.producto.precio + _todas.fold(0, (s, o) => s + o.precioExtra);

  /// Primer grupo obligatorio sin elegir, para avisar y no dejar agregar.
  String? get _faltante {
    for (var i = 0; i < widget.producto.opciones.length; i++) {
      final o = widget.producto.opciones[i];
      if (o.obligatoria && (_elegidas[i]?.isEmpty ?? true)) return o.nombre;
    }
    return null;
  }

  /// El grupo de "varias" ya tiene todas las que se pueden elegir.
  bool _lleno(int grupo) {
    final o = widget.producto.opciones[grupo];
    return o.tipo == TipoOpcion.multiple &&
        o.maxSelecciones != null &&
        _elegidas[grupo]!.length >= o.maxSelecciones!;
  }

  void _tocar(int grupo, OpcionItem item) {
    final o = widget.producto.opciones[grupo];
    final lista = _elegidas[grupo]!;
    setState(() {
      if (o.tipo == TipoOpcion.unica) {
        lista
          ..clear()
          ..add(item);
      } else if (lista.contains(item)) {
        lista.remove(item);
      } else if (o.maxSelecciones == null || lista.length < o.maxSelecciones!) {
        lista.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.producto;
    final faltante = _faltante;

    Widget contenido(ScrollController? scroll) => Column(
        mainAxisSize: widget.enVentana ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Flexible(
            child: ListView(
              controller: scroll,
              shrinkWrap: widget.enVentana,
              padding: const EdgeInsets.all(MySpacing.screenEdge),
              children: [
                if (p.fotoUrl != null) ...[
                  MyImagen(url: p.fotoUrl, alto: 200, radio: MyRadius.card),
                  const SizedBox(height: MySpacing.md),
                ],
                Text(p.nombre, style: MyType.headlineLg),
                if (p.descripcion != null)
                  Text(p.descripcion!, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                const SizedBox(height: MySpacing.xs),
                // El mismo precio que en la tarjeta del menú: si allá se ve la
                // promoción y acá no, parece que se perdió el descuento.
                MyPrecio(
                  precio: Formato.pesos(p.precio),
                  precioLista: p.enPromocion ? Formato.pesos(p.precioLista!) : null,
                  descuento: p.descuento,
                  estilo: MyType.headlineMd.copyWith(color: MyColors.tertiary),
                ),
                for (var g = 0; g < p.opciones.length; g++) ...[
                  const SizedBox(height: MySpacing.lg),
                  _EncabezadoGrupo(opcion: p.opciones[g], elegidas: _elegidas[g]!.length),
                  const SizedBox(height: MySpacing.xs),
                  for (final item in p.opciones[g].items.where((i) => i.disponible))
                    _FilaOpcion(
                      item: item,
                      unica: p.opciones[g].tipo == TipoOpcion.unica,
                      elegida: _elegidas[g]!.contains(item),
                      // Con el tope lleno, las que faltan se ven apagadas:
                      // antes se tocaban y no pasaba nada.
                      habilitada: _elegidas[g]!.contains(item) || !_lleno(g),
                      onTap: () => _tocar(g, item),
                    ),
                ],
                const SizedBox(height: MySpacing.lg),
                Text('Aclaraciones', style: MyType.headlineSm),
                Text('Opcional. Las lee el local antes de prepararlo.', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                const SizedBox(height: MySpacing.xs),
                TextField(
                  controller: _nota,
                  maxLines: 2,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Ej.: sin cebolla, bien cocida',
                    prefixIcon: Icon(Symbols.edit_note, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // El botón queda fijo abajo: con muchas opciones había que bajar
          // hasta el final para encontrar cómo agregarlo.
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: MyColors.outlineVariant)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(MySpacing.screenEdge),
                child: Row(
                  children: [
                    MyStepper(
                      valor: _cantidad,
                      maximo: 50,
                      onChanged: (c) => setState(() => _cantidad = c),
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: faltante != null
                            ? null
                            : () => Navigator.pop(
                                  context,
                                  ItemCarrito(
                                    producto: p,
                                    cantidad: _cantidad,
                                    elegidas: _todas,
                                    nota: _nota.text.trim().isEmpty ? null : _nota.text.trim(),
                                  ),
                                ),
                        child: Text(
                          faltante != null ? 'Elegí $faltante' : 'Agregar ${Formato.pesos(_unitario * _cantidad)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

    if (widget.enVentana) return contenido(null);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: p.opciones.isEmpty ? 0.55 : 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => contenido(scroll),
    );
  }
}

/// Título de un grupo de opciones con su regla ("Elegí una", "Hasta 3") y si
/// ya está resuelto.
class _EncabezadoGrupo extends StatelessWidget {
  const _EncabezadoGrupo({required this.opcion, required this.elegidas});

  final OpcionProducto opcion;
  final int elegidas;

  @override
  Widget build(BuildContext context) {
    final o = opcion;
    final tope = o.maxSelecciones;
    final regla = o.tipo == TipoOpcion.multiple && tope != null
        ? 'Elegí hasta $tope · $elegidas de $tope'
        : o.tipo.label;
    final listo = o.obligatoria && elegidas > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(o.nombre, style: MyType.headlineSm)),
            const SizedBox(width: MySpacing.xs),
            // Pasa a verde cuando se eligió: así se ve de un vistazo qué
            // grupo falta y por qué el botón todavía no deja agregar.
            if (o.obligatoria)
              MyBadge(
                listo ? 'Listo' : 'Obligatorio',
                tone: listo ? MyBadgeTone.success : MyBadgeTone.ember,
                icon: listo ? Symbols.check : null,
              )
            else
              const MyBadge('Opcional', tone: MyBadgeTone.info),
          ],
        ),
        Text(regla, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
      ],
    );
  }
}

class _FilaOpcion extends StatelessWidget {
  const _FilaOpcion({
    required this.item,
    required this.unica,
    required this.elegida,
    required this.onTap,
    this.habilitada = true,
  });

  final OpcionItem item;
  final bool unica;
  final bool elegida;
  final bool habilitada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: habilitada ? 1 : 0.45,
      child: InkWell(
        onTap: habilitada ? onTap : null,
        borderRadius: BorderRadius.circular(MyRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
          child: Row(
            children: [
              Icon(
                unica
                    ? (elegida ? Symbols.radio_button_checked : Symbols.radio_button_unchecked)
                    : (elegida ? Symbols.check_box : Symbols.check_box_outline_blank),
                color: elegida ? MyColors.primary : MyColors.outline,
                fill: elegida ? 1 : 0,
              ),
              const SizedBox(width: MySpacing.sm),
              Expanded(child: Text(item.nombre, style: MyType.bodyLg)),
              if (item.precioExtra > 0)
                Text('+ ${Formato.pesos(item.precioExtra)}', style: MyType.labelLg.copyWith(color: MyColors.secondary)),
            ],
          ),
        ),
      ),
    );
  }
}
