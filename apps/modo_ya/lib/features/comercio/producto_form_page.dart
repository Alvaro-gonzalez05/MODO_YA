import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';


/// Alta y edición de un producto, con foto y personalización.
class ProductoFormPage extends ConsumerStatefulWidget {
  const ProductoFormPage({super.key, this.producto});

  /// Null para crear uno nuevo.
  final Producto? producto;

  @override
  ConsumerState<ProductoFormPage> createState() => _ProductoFormPageState();
}

class _ProductoFormPageState extends ConsumerState<ProductoFormPage> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.producto?.nombre);
  late final _descripcion = TextEditingController(text: widget.producto?.descripcion);
  late final _precio = TextEditingController(text: widget.producto?.precio.toString());

  late String? _seccionId = widget.producto?.seccionId;
  late bool _disponible = widget.producto?.disponible ?? true;
  late final List<_GrupoEditable> _grupos = [
    for (final o in widget.producto?.opciones ?? const <OpcionProducto>[]) _GrupoEditable.desde(o),
  ];

  Uint8List? _foto;
  String _fotoExt = 'jpg';

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _precio.dispose();
    for (final g in _grupos) {
      g.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirFoto() async {
    try {
      final archivo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 82,
      );
      if (archivo == null) return;
      final bytes = await archivo.readAsBytes();
      if (bytes.lengthInBytes > 5 * 1024 * 1024) {
        if (mounted) mostrarError(context, 'La foto pesa más de 5 MB. Elegí una más liviana.');
        return;
      }
      final ext = archivo.name.split('.').last.toLowerCase();
      setState(() {
        _foto = bytes;
        _fotoExt = ext == 'png' ? 'png' : 'jpg';
      });
    } catch (e) {
      if (mounted) mostrarError(context, 'No se pudo abrir la foto: $e');
    }
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final comercioId = ref.read(sesionProvider).comercioId!;

    final opciones = <OpcionProducto>[];
    for (final g in _grupos) {
      final items = [
        for (final i in g.items)
          if (i.nombre.text.trim().isNotEmpty)
            OpcionItem(nombre: i.nombre.text.trim(), precioExtra: int.tryParse(i.precio.text) ?? 0),
      ];
      if (g.nombre.text.trim().isEmpty && items.isEmpty) continue;
      if (g.nombre.text.trim().isEmpty || items.isEmpty) {
        mostrarError(context, 'Cada grupo de opciones necesita un nombre y al menos una opción.');
        return;
      }
      opciones.add(OpcionProducto(
        nombre: g.nombre.text.trim(),
        tipo: g.tipo,
        obligatoria: g.obligatoria,
        items: items,
      ));
    }

    try {
      await ref.read(catalogoRepositoryProvider).guardarProducto(
            id: widget.producto?.id,
            comercioId: comercioId,
            seccionId: _seccionId,
            nombre: _nombre.text,
            descripcion: _descripcion.text,
            precio: int.parse(_precio.text),
            disponible: _disponible,
            opciones: opciones,
            foto: _foto,
            fotoExtension: _fotoExt,
          );
      ref.invalidate(menuDeComercioProvider(comercioId));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _borrar() async {
    final p = widget.producto!;
    final ok = await confirmar(
      context,
      titulo: 'Borrar "${p.nombre}"',
      mensaje: 'Los pedidos que ya lo incluyeron no cambian. Si solo no tenés stock, mejor desactivalo.',
      aceptar: 'Borrar',
      peligroso: true,
    );
    if (!ok) return;
    try {
      await ref.read(catalogoRepositoryProvider).borrarProducto(p);
      ref.invalidate(menuDeComercioProvider(p.comercioId));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comercioId = ref.watch(sesionProvider).comercioId;
    final secciones = comercioId == null
        ? const <SeccionMenu>[]
        : ref.watch(menuDeComercioProvider(comercioId)).value?.secciones ?? const <SeccionMenu>[];
    final tieneFoto = _foto != null || widget.producto?.fotoUrl != null;

    final foto = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _elegirFoto,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MyRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: _foto != null
                    ? Image.memory(_foto!, fit: BoxFit.cover)
                    : widget.producto?.fotoUrl != null
                        ? MyImagen(url: widget.producto!.fotoUrl, radio: 0)
                        : Container(
                            color: MyColors.surfaceContainerHigh,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Symbols.add_a_photo, size: 40, color: MyColors.secondary),
                                const SizedBox(height: MySpacing.xs),
                                Text('Agregar foto', style: MyType.labelLg.copyWith(color: MyColors.secondary)),
                                Text('Una buena foto vende mucho más', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                              ],
                            ),
                          ),
              ),
            ),
          ),
        ),
        if (tieneFoto)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _elegirFoto,
              icon: const Icon(Symbols.photo_camera, size: 18),
              label: const Text('Cambiar foto'),
            ),
          ),
      ],
    );

    final datos = MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyCampo(controller: _nombre, label: 'Nombre', hint: 'Pizza muzzarella'),
          MyCampo(
            controller: _descripcion,
            label: 'Descripción (opcional)',
            hint: 'Salsa de tomate casera, muzzarella y aceitunas',
            obligatorio: false,
            lineas: 3,
          ),
          MyCampo(
            controller: _precio,
            label: 'Precio (pesos)',
            hint: '8200',
            icon: Symbols.payments,
            soloNumeros: true,
            validar: (t) => (int.tryParse(t) ?? 0) <= 0 ? 'Poné un precio' : null,
          ),
          const MyOverline('Sección'),
          const SizedBox(height: MySpacing.xs),
          DropdownButtonFormField<String?>(
            initialValue: secciones.any((s) => s.id == _seccionId) ? _seccionId : null,
            items: [
              const DropdownMenuItem(value: null, child: Text('Sin sección')),
              for (final s in secciones) DropdownMenuItem(value: s.id, child: Text(s.nombre)),
            ],
            onChanged: (v) => setState(() => _seccionId = v),
          ),
          const SizedBox(height: MySpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _disponible,
            onChanged: (v) => setState(() => _disponible = v),
            title: Text('Disponible', style: MyType.labelLg),
            subtitle: Text('Si lo apagás, los clientes no lo pueden pedir', style: MyType.bodySm),
          ),
        ],
      ),
    );

    final personalizacion = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Personalización', style: MyType.headlineSm),
        Text(
          'Opciones que elige el cliente: tamaño, agregados, gustos…',
          style: MyType.bodySm.copyWith(color: MyColors.secondary),
        ),
        const SizedBox(height: MySpacing.sm),
        for (var i = 0; i < _grupos.length; i++) ...[
          _EditorGrupo(
            grupo: _grupos[i],
            onCambio: () => setState(() {}),
            onQuitar: () => setState(() => _grupos.removeAt(i).dispose()),
          ),
          const SizedBox(height: MySpacing.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: MyBoton(
            onPressed: () => setState(() => _grupos.add(_GrupoEditable.vacio())),
            icon: Symbols.add,
            label: 'Agregar grupo de opciones',
            tipo: MyBotonTipo.secundario,
          ),
        ),
      ],
    );

    final guardar = MyBotonAccion(label: 'Guardar producto', icon: Symbols.save, onPressed: _guardar);
    const espacio = SizedBox(height: MySpacing.md);

    return Form(
      key: _form,
      child: MyPagina(
        volver: () => context.canPop() ? context.pop() : context.go('/local/menu'),
        rotulo: 'Menú',
        titulo: widget.producto == null ? 'Nuevo producto' : 'Editar producto',
        anchoMaximo: 1180,
        conDock: false,
        acciones: [
          if (widget.producto != null)
            MyBoton(label: 'Borrar', icon: Symbols.delete, tipo: MyBotonTipo.peligro, onPressed: _borrar),
        ],
        children: context.esMovil
            ? [foto, espacio, datos, const SizedBox(height: MySpacing.lg), personalizacion, const SizedBox(height: MySpacing.xl), guardar]
            : [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [foto, espacio, datos])),
                    const SizedBox(width: MySpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [personalizacion, const SizedBox(height: MySpacing.xl), guardar],
                      ),
                    ),
                  ],
                ),
              ],
      ),
    );
  }
}

class _ItemEditable {
  _ItemEditable({String nombre = '', int precio = 0})
      : nombre = TextEditingController(text: nombre),
        precio = TextEditingController(text: precio == 0 ? '' : '$precio');

  final TextEditingController nombre;
  final TextEditingController precio;

  void dispose() {
    nombre.dispose();
    precio.dispose();
  }
}

class _GrupoEditable {
  _GrupoEditable({required this.nombre, required this.tipo, required this.obligatoria, required this.items});

  factory _GrupoEditable.vacio() => _GrupoEditable(
        nombre: TextEditingController(),
        tipo: TipoOpcion.unica,
        obligatoria: false,
        items: [_ItemEditable()],
      );

  factory _GrupoEditable.desde(OpcionProducto o) => _GrupoEditable(
        nombre: TextEditingController(text: o.nombre),
        tipo: o.tipo,
        obligatoria: o.obligatoria,
        items: [for (final i in o.items) _ItemEditable(nombre: i.nombre, precio: i.precioExtra)],
      );

  final TextEditingController nombre;
  TipoOpcion tipo;
  bool obligatoria;
  final List<_ItemEditable> items;

  void dispose() {
    nombre.dispose();
    for (final i in items) {
      i.dispose();
    }
  }
}

class _EditorGrupo extends StatelessWidget {
  const _EditorGrupo({required this.grupo, required this.onCambio, required this.onQuitar});

  final _GrupoEditable grupo;
  final VoidCallback onCambio;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: grupo.nombre,
                  decoration: const InputDecoration(hintText: 'Nombre del grupo (ej: Tamaño)'),
                ),
              ),
              IconButton(onPressed: onQuitar, icon: Icon(Symbols.delete, color: MyColors.error)),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              for (final t in TipoOpcion.values)
                MyChip(
                  t == TipoOpcion.unica ? 'Elige una' : 'Elige varias',
                  selected: grupo.tipo == t,
                  onTap: () {
                    grupo.tipo = t;
                    onCambio();
                  },
                ),
              FilterChip(
                label: const Text('Obligatorio'),
                selected: grupo.obligatoria,
                onSelected: (v) {
                  grupo.obligatoria = v;
                  onCambio();
                },
              ),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          for (var i = 0; i < grupo.items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: MySpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: grupo.items[i].nombre,
                      decoration: const InputDecoration(hintText: 'Opción (ej: Grande)'),
                    ),
                  ),
                  const SizedBox(width: MySpacing.xs),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: grupo.items[i].precio,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '+ \$0', prefixText: '+\$ '),
                    ),
                  ),
                  IconButton(
                    onPressed: grupo.items.length == 1
                        ? null
                        : () {
                            grupo.items.removeAt(i).dispose();
                            onCambio();
                          },
                    icon: Icon(Symbols.remove_circle, color: MyColors.secondary),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () {
              grupo.items.add(_ItemEditable());
              onCambio();
            },
            icon: const Icon(Symbols.add, size: 18),
            label: const Text('Agregar opción'),
          ),
        ],
      ),
    );
  }
}
