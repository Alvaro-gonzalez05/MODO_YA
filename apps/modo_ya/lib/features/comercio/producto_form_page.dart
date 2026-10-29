import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/formulario.dart';

/// Alta y edición de un producto, con foto y opciones para elegir.
///
/// Va por bloques (lo básico, precio, disponibilidad, opciones) y el botón de
/// guardar queda fijo abajo en el celular.
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
  late final _precio = TextEditingController(
      text: widget.producto == null ? null : MilesFormatter.formatear(widget.producto!.precio));

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
    // Los errores se ven al lado de cada campo, también los de las opciones.
    if (!_form.currentState!.validate()) {
      mostrarError(context, 'Revisá los campos marcados en rojo.');
      return;
    }
    final comercioId = ref.read(sesionProvider).comercioId!;

    final opciones = [
      for (final g in _grupos)
        if (!g.vacio) g.armar(),
    ];

    try {
      await ref.read(catalogoRepositoryProvider).guardarProducto(
            id: widget.producto?.id,
            comercioId: comercioId,
            seccionId: _seccionId,
            nombre: _nombre.text,
            descripcion: _descripcion.text,
            precio: MilesFormatter.leer(_precio.text)!,
            disponible: _disponible,
            opciones: opciones,
            foto: _foto,
            fotoExtension: _fotoExt,
          );
      ref.invalidate(menuDeComercioProvider(comercioId));
      if (mounted) {
        mostrarAviso(context, widget.producto == null ? 'Producto agregado' : 'Cambios guardados');
        context.canPop() ? context.pop() : context.go('/local/menu');
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _borrar() async {
    final p = widget.producto!;
    final ok = await confirmar(
      context,
      titulo: 'Borrar "${p.nombre}"',
      mensaje: 'Los pedidos que ya lo incluyeron no cambian. Si solo no tenés stock, mejor apagá "Lo pueden pedir".',
      aceptar: 'Borrar',
      peligroso: true,
    );
    if (!ok) return;
    try {
      await ref.read(catalogoRepositoryProvider).borrarProducto(p);
      ref.invalidate(menuDeComercioProvider(p.comercioId));
      if (mounted) context.canPop() ? context.pop() : context.go('/local/menu');
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
    final movil = context.esMovil;

    final foto = _Foto(
      nueva: _foto,
      guardada: widget.producto?.fotoUrl,
      onElegir: _elegirFoto,
    );

    final basico = SeccionFormulario(
      titulo: 'Lo básico',
      children: [
        MyCampo(controller: _nombre, label: 'Nombre', hint: 'Ej: Pizza muzzarella', accion: TextInputAction.next),
        MyCampo(
          controller: _descripcion,
          label: 'Descripción (opcional)',
          hint: 'Ej: Salsa de tomate casera, muzzarella y aceitunas',
          obligatorio: false,
          lineas: 3,
        ),
      ],
    );

    final precio = SeccionFormulario(
      titulo: 'Precio y sección',
      children: [
        MyCampo(
          controller: _precio,
          label: 'Precio',
          hint: 'Ej: 8.200',
          icon: Symbols.payments,
          miles: true,
          validar: (t) => (MilesFormatter.leer(t) ?? 0) <= 0 ? 'Poné un precio mayor a cero' : null,
        ),
        const MyOverline('Sección del menú'),
        const SizedBox(height: MySpacing.xs),
        DropdownButtonFormField<String?>(
          initialValue: secciones.any((s) => s.id == _seccionId) ? _seccionId : null,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: null, child: Text('Sin sección')),
            for (final s in secciones)
              DropdownMenuItem(value: s.id, child: Text(s.nombre, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _seccionId = v),
        ),
        if (secciones.isEmpty) ...[
          const SizedBox(height: MySpacing.xs),
          Text(
            'Las secciones (Pizzas, Bebidas…) se crean desde el menú con "Nueva sección".',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
        ],
      ],
    );

    final disponibilidad = SeccionFormulario(
      titulo: 'Disponibilidad',
      children: [
        InterruptorFormulario(
          valor: _disponible,
          onChanged: (v) => setState(() => _disponible = v),
          titulo: _disponible ? 'Lo pueden pedir' : 'Sin stock',
          bajada: 'Si te quedaste sin, apagalo: no se borra y lo prendés cuando vuelva.',
        ),
      ],
    );

    final opciones = SeccionFormulario(
      titulo: 'Opciones para elegir',
      bajada: 'Tamaño, gustos, agregados. Si una opción cuesta más, poné cuánto se suma al precio.',
      enTarjeta: false,
      children: [
        for (var i = 0; i < _grupos.length; i++) ...[
          _EditorGrupo(
            key: ObjectKey(_grupos[i]),
            grupo: _grupos[i],
            onCambio: () => setState(() {}),
            onQuitar: () => setState(() => _grupos.removeAt(i).dispose()),
          ),
          const SizedBox(height: MySpacing.sm),
        ],
        if (_grupos.isEmpty)
          MyCard(
            color: MyColors.surfaceContainerLow,
            shadows: const [],
            padding: const EdgeInsets.all(MySpacing.md),
            child: Text(
              'Este producto no tiene opciones: el cliente lo pide tal cual.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
          ),
        const SizedBox(height: MySpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: MyBoton(
            onPressed: () => setState(() => _grupos.add(_GrupoEditable.vacio())),
            icon: Symbols.add,
            label: _grupos.isEmpty ? 'Agregar opciones' : 'Agregar otro grupo',
            tipo: MyBotonTipo.secundario,
          ),
        ),
      ],
    );

    final guardar = MyBotonAccion(
      label: widget.producto == null ? 'Agregar al menú' : 'Guardar cambios',
      icon: Symbols.save,
      onPressed: _guardar,
    );
    const espacio = SizedBox(height: MySpacing.md);

    return Form(
      key: _form,
      child: ConBarraDeGuardado(
        boton: guardar,
        pagina: MyPagina(
          volver: () => context.canPop() ? context.pop() : context.go('/local/menu'),
          rotulo: 'Menú',
          titulo: widget.producto == null ? 'Nuevo producto' : 'Editar producto',
          anchoMaximo: 1180,
          conDock: false,
          acciones: [
            if (widget.producto != null)
              MyBoton(label: 'Borrar', icon: Symbols.delete, tipo: MyBotonTipo.peligro, onPressed: _borrar),
          ],
          children: movil
              ? [foto, espacio, basico, espacio, precio, espacio, disponibilidad, const SizedBox(height: MySpacing.lg), opciones]
              : [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [foto, espacio, basico, espacio, precio, espacio, disponibilidad],
                        ),
                      ),
                      const SizedBox(width: MySpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [opciones, const SizedBox(height: MySpacing.xl), guardar],
                        ),
                      ),
                    ],
                  ),
                ],
        ),
      ),
    );
  }
}

class _Foto extends StatelessWidget {
  const _Foto({required this.nueva, required this.guardada, required this.onElegir});

  final Uint8List? nueva;
  final String? guardada;
  final VoidCallback onElegir;

  @override
  Widget build(BuildContext context) {
    final tiene = nueva != null || guardada != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onElegir,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MyRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: nueva != null
                    ? Image.memory(nueva!, fit: BoxFit.cover)
                    : guardada != null
                        ? MyImagen(url: guardada, radio: 0)
                        : Container(
                            color: MyColors.surfaceContainerHigh,
                            padding: const EdgeInsets.all(MySpacing.md),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Symbols.add_a_photo, size: 40, color: MyColors.secondary),
                                const SizedBox(height: MySpacing.xs),
                                Text('Agregar foto', style: MyType.labelLg.copyWith(color: MyColors.secondary)),
                                Text(
                                  'Una buena foto vende mucho más',
                                  textAlign: TextAlign.center,
                                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
          ),
        ),
        if (tiene)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onElegir,
              icon: const Icon(Symbols.photo_camera, size: 18),
              label: const Text('Cambiar foto'),
            ),
          ),
      ],
    );
  }
}

class _ItemEditable {
  _ItemEditable({String nombre = '', int precio = 0, this.id, this.disponible = true})
      : nombre = TextEditingController(text: nombre),
        precio = TextEditingController(text: precio == 0 ? '' : MilesFormatter.formatear(precio));

  final TextEditingController nombre;
  final TextEditingController precio;

  // Se conservan al editar: guardar borra y vuelve a crear las opciones, y
  // sin esto una opción que estaba sin stock volvía a aparecer.
  final String? id;
  final bool disponible;

  bool get vacio => nombre.text.trim().isEmpty && precio.text.trim().isEmpty;

  void dispose() {
    nombre.dispose();
    precio.dispose();
  }
}

class _GrupoEditable {
  _GrupoEditable({
    required this.nombre,
    required this.tipo,
    required this.obligatoria,
    required this.items,
    this.id,
    this.maxSelecciones,
  });

  factory _GrupoEditable.vacio() => _GrupoEditable(
        nombre: TextEditingController(),
        tipo: TipoOpcion.unica,
        obligatoria: true,
        items: [_ItemEditable(), _ItemEditable()],
      );

  factory _GrupoEditable.desde(OpcionProducto o) => _GrupoEditable(
        nombre: TextEditingController(text: o.nombre),
        tipo: o.tipo,
        obligatoria: o.obligatoria,
        id: o.id,
        maxSelecciones: o.maxSelecciones,
        items: [
          for (final i in o.items) _ItemEditable(nombre: i.nombre, precio: i.precioExtra, id: i.id, disponible: i.disponible),
        ],
      );

  final TextEditingController nombre;
  TipoOpcion tipo;
  bool obligatoria;
  final List<_ItemEditable> items;
  final String? id;
  final int? maxSelecciones;

  /// Un grupo que se agregó y no se completó no se guarda ni se reclama.
  bool get vacio => nombre.text.trim().isEmpty && items.every((i) => i.vacio);

  bool get sinOpciones => items.every((i) => i.nombre.text.trim().isEmpty);

  OpcionProducto armar() => OpcionProducto(
        id: id,
        nombre: nombre.text.trim(),
        tipo: tipo,
        obligatoria: obligatoria,
        maxSelecciones: maxSelecciones,
        items: [
          for (final i in items)
            if (i.nombre.text.trim().isNotEmpty)
              OpcionItem(
                id: i.id,
                nombre: i.nombre.text.trim(),
                precioExtra: MilesFormatter.leer(i.precio.text) ?? 0,
                disponible: i.disponible,
              ),
        ],
      );

  void dispose() {
    nombre.dispose();
    for (final i in items) {
      i.dispose();
    }
  }
}

/// Un grupo de opciones ("Tamaño": Chica, Grande +$1.500).
///
/// Antes eran dos campos sin rótulo, dos chips y un "Obligatorio" sueltos, y
/// no se entendía qué era el precio. Ahora cada cosa dice qué es, y abajo se
/// ve cómo le va a quedar al cliente.
class _EditorGrupo extends StatelessWidget {
  const _EditorGrupo({
    super.key,
    required this.grupo,
    required this.onCambio,
    required this.onQuitar,
  });

  final _GrupoEditable grupo;
  final VoidCallback onCambio;
  final VoidCallback onQuitar;

  static const _denso = InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: MySpacing.sm, vertical: MySpacing.sm),
  );

  String get _vistaPrevia {
    final nombre = grupo.nombre.text.trim().isEmpty ? 'Este grupo' : grupo.nombre.text.trim();
    final regla = [
      grupo.tipo == TipoOpcion.unica ? 'elegí una' : 'elegí las que quieras',
      if (grupo.obligatoria) 'obligatorio',
    ].join(', ');
    final items = [
      for (final i in grupo.items)
        if (i.nombre.text.trim().isNotEmpty)
          switch (MilesFormatter.leer(i.precio.text) ?? 0) {
            0 => i.nombre.text.trim(),
            final extra => '${i.nombre.text.trim()} (+${Formato.pesos(extra)})',
          },
    ];
    return '$nombre ($regla): ${items.isEmpty ? '…' : items.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const MyOverline('Nombre del grupo'),
                    const SizedBox(height: MySpacing.xs),
                    TextFormField(
                      controller: grupo.nombre,
                      onChanged: (_) => onCambio(),
                      decoration: const InputDecoration(hintText: 'Ej: Tamaño, Gustos, Agregados'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty && !grupo.vacio ? 'Ponele un nombre (ej: Tamaño)' : null,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Quitar el grupo',
                onPressed: onQuitar,
                icon: Icon(Symbols.delete, color: MyColors.error),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          const MyOverline('El cliente elige'),
          const SizedBox(height: MySpacing.xs),
          SegmentedButton<TipoOpcion>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TipoOpcion.unica, label: Text('Una sola')),
              ButtonSegment(value: TipoOpcion.multiple, label: Text('Varias')),
            ],
            selected: {grupo.tipo},
            onSelectionChanged: (s) {
              grupo.tipo = s.first;
              onCambio();
            },
          ),
          const SizedBox(height: MySpacing.xs),
          InterruptorFormulario(
            valor: grupo.obligatoria,
            onChanged: (v) {
              grupo.obligatoria = v;
              onCambio();
            },
            titulo: 'Tiene que elegir',
            bajada: grupo.obligatoria ? 'No puede pedir sin elegir una opción' : 'Puede pedirlo sin elegir ninguna',
          ),
          const SizedBox(height: MySpacing.xs),
          Row(
            children: [
              const Expanded(flex: 5, child: MyOverline('Opción')),
              const SizedBox(width: MySpacing.xs),
              const Expanded(flex: 4, child: MyOverline('Suma al precio')),
              // Lo que ocupa el botón de quitar, para que los rótulos queden
              // arriba de su campo.
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          for (var i = 0; i < grupo.items.length; i++)
            Padding(
              key: ObjectKey(grupo.items[i]),
              padding: const EdgeInsets.only(bottom: MySpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextFormField(
                      controller: grupo.items[i].nombre,
                      onChanged: (_) => onCambio(),
                      decoration: _denso.copyWith(hintText: i == 0 ? 'Ej: Chica' : 'Ej: Grande'),
                      validator: (v) {
                        final vacio = (v ?? '').trim().isEmpty;
                        if (vacio && grupo.items[i].precio.text.trim().isNotEmpty) return 'Falta el nombre';
                        if (vacio && i == 0 && grupo.sinOpciones && !grupo.vacio) return 'Agregá al menos una';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: MySpacing.xs),
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      controller: grupo.items[i].precio,
                      onChanged: (_) => onCambio(),
                      keyboardType: TextInputType.number,
                      inputFormatters: const [MilesFormatter()],
                      decoration: _denso.copyWith(hintText: '0', prefixText: '+ \$ '),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      tooltip: 'Quitar la opción',
                      visualDensity: VisualDensity.compact,
                      onPressed: grupo.items.length == 1
                          ? null
                          : () {
                              grupo.items.removeAt(i).dispose();
                              onCambio();
                            },
                      icon: Icon(Symbols.remove_circle, color: MyColors.secondary),
                    ),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                grupo.items.add(_ItemEditable());
                onCambio();
              },
              icon: const Icon(Symbols.add, size: 18),
              label: const Text('Agregar opción'),
            ),
          ),
          const SizedBox(height: MySpacing.xs),
          Container(
            padding: const EdgeInsets.all(MySpacing.sm),
            decoration: BoxDecoration(
              color: MyColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(MyRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.visibility, size: 16, color: MyColors.secondary),
                const SizedBox(width: MySpacing.xs),
                Expanded(
                  child: Text('Así lo ve el cliente: $_vistaPrevia', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
