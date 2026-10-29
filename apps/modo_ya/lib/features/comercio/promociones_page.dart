import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';
import 'widgets/formulario.dart';

/// Promociones del local: descuentos sobre su propio menú.
///
/// A diferencia de las campañas, acá no se le paga nada a MODO YA: el local
/// resigna parte de su precio para vender más. Por eso no hay presupuesto ni
/// fondo, solo el porcentaje, a qué le pega y hasta cuándo.
class PromocionesPage extends ConsumerWidget {
  const PromocionesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promos = ref.watch(promocionesDelComercioProvider);
    // El formulario necesita el menú (para elegir secciones y productos). Se
    // mira desde acá para que ya esté cargado al tocar "Nueva promo": leído
    // recién ahí, sin nadie escuchándolo, podía no terminar nunca.
    final comercioId = ref.watch(sesionProvider).comercioId;
    if (comercioId != null) ref.watch(menuDeComercioProvider(comercioId));

    return MyPagina(
      volver: () => context.go('/local/menu'),
      rotulo: 'Vender más',
      titulo: 'Promociones',
      bajada: 'Bajá el precio de todo tu menú o solo de lo que elijas. El descuento lo ponés vos.',
      acciones: [
        MyBoton(
          label: 'Nueva promo',
          icon: Symbols.add,
          onPressed: () => editarPromocion(context, ref),
        ),
      ],
      children: [
        MyAsync(
          valor: promos,
          onReintentar: () => ref.invalidate(promocionesDelComercioProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.sell,
                  title: 'Todavía no tenés promociones',
                  message: 'Un "20% en pizzas los martes" te llena las horas flojas. '
                      'Los clientes lo ven con el precio tachado y tu local aparece marcado en la lista.',
                  action: MyBoton(
                    label: 'Armar la primera',
                    icon: Symbols.add,
                    onPressed: () => editarPromocion(context, ref),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in lista) ...[
                  _TarjetaPromocion(promocion: p),
                  const SizedBox(height: MySpacing.md),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TarjetaPromocion extends ConsumerWidget {
  const _TarjetaPromocion({required this.promocion});

  final Promocion promocion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = promocion;
    final repo = ref.read(promocionesRepositoryProvider);

    Future<void> pausar() async {
      try {
        await repo.pausar(p.id, activa: !p.activa);
      } catch (e) {
        if (context.mounted) mostrarError(context, e);
      }
    }

    Future<void> borrar() async {
      final ok = await confirmar(
        context,
        titulo: 'Borrar "${p.nombre}"',
        mensaje: 'Los pedidos que ya se hicieron con esta promo no cambian.',
        aceptar: 'Borrar',
        peligroso: true,
      );
      if (!ok) return;
      try {
        await repo.borrar(p.id);
      } catch (e) {
        if (context.mounted) mostrarError(context, e);
      }
    }

    return MyCard(
      // Tocarla abre la promo para editarla en el lugar, como cualquier otra
      // lista del local.
      onTap: () => editarPromocion(context, ref, editar: p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Sello(porcentaje: p.porcentaje, encendido: p.vigente),
              const SizedBox(width: MySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre, style: MyType.headlineSm, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(
                      '${p.detalle} · ${p.cuando}',
                      style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                    ),
                    if (p.hasta != null)
                      Text(
                        'Hasta el ${Formato.fechaCorta(p.hasta!)}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                    const SizedBox(height: MySpacing.xs),
                    MyBadge(
                      p.vigente
                          ? 'Rigiendo ahora'
                          : !p.activa
                              ? 'Pausada'
                              : 'No rige hoy',
                      tone: p.vigente
                          ? MyBadgeTone.success
                          : !p.activa
                              ? MyBadgeTone.neutral
                              : MyBadgeTone.info,
                      dot: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              MyBoton(
                label: 'Editar',
                icon: Symbols.edit,
                tipo: MyBotonTipo.secundario,
                onPressed: () => editarPromocion(context, ref, editar: p),
              ),
              MyBoton(
                label: p.activa ? 'Pausar' : 'Reanudar',
                icon: p.activa ? Symbols.pause : Symbols.play_arrow,
                tipo: MyBotonTipo.secundario,
                onPressed: pausar,
              ),
              MyBoton(
                label: 'Borrar',
                icon: Symbols.delete,
                tipo: MyBotonTipo.secundario,
                onPressed: borrar,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// El "30% OFF" grande, apagado cuando la promo hoy no rige.
class _Sello extends StatelessWidget {
  const _Sello({required this.porcentaje, required this.encendido});

  final int porcentaje;
  final bool encendido;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: encendido ? MyColors.primary : MyColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(MyRadius.card),
        border: Border.all(color: encendido ? MyColors.primary : MyColors.outlineVariant),
      ),
      padding: const EdgeInsets.all(MySpacing.xxs),
      // Se achica si no entra: con la letra agrandada del celular, "20%" y
      // "OFF" se pasaban del cuadrado.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$porcentaje%',
              style: MyType.headlineMd.copyWith(color: encendido ? MyColors.onPrimary : MyColors.secondary),
            ),
            Text(
              'OFF',
              style: MyType.labelMd.copyWith(color: encendido ? MyColors.onPrimary : MyColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Alta o edición de una promoción.
Future<void> editarPromocion(BuildContext context, WidgetRef ref, {Promocion? editar}) async {
  final comercioId = ref.read(sesionProvider).comercioId;
  if (comercioId == null) return;

  final menu = await ref.read(menuDeComercioProvider(comercioId).future);
  // Al editar hay que traer el alcance guardado: la vista solo trae el conteo.
  final alcanceGuardado =
      editar == null ? null : await ref.read(promocionesRepositoryProvider).alcanceDe(editar.id);
  if (!context.mounted) return;

  await mostrarFormularioEmergente(
    context,
    titulo: editar == null ? 'Nueva promoción' : 'Editar promoción',
    builder: (_) => _FormularioPromocion(
      comercioId: comercioId,
      menu: menu,
      editar: editar,
      secciones: {...?alcanceGuardado?.secciones},
      productos: {...?alcanceGuardado?.productos},
    ),
  );
}

/// El formulario, por bloques: qué descuento, sobre qué y cuándo.
///
/// Es un widget con estado para que los controladores vivan hasta que la hoja
/// termine de cerrarse (liberados al volver de `mostrarFormularioEmergente`,
/// el campo se seguía dibujando con el controlador ya liberado).
class _FormularioPromocion extends ConsumerStatefulWidget {
  const _FormularioPromocion({
    required this.comercioId,
    required this.menu,
    required this.secciones,
    required this.productos,
    this.editar,
  });

  final String comercioId;
  final Menu menu;
  final Promocion? editar;
  final Set<String> secciones;
  final Set<String> productos;

  @override
  ConsumerState<_FormularioPromocion> createState() => _FormularioPromocionState();
}

class _FormularioPromocionState extends ConsumerState<_FormularioPromocion> {
  final _form = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.editar?.nombre ?? '');
  late var _porcentaje = widget.editar?.porcentaje ?? 20;
  late var _alcance = widget.editar?.alcance ?? AlcancePromocion.todo;
  late final _dias = {...(widget.editar?.dias ?? const <int>[])};
  late final _secciones = {...widget.secciones};
  late final _productos = {...widget.productos};
  late DateTime? _hasta = widget.editar?.hasta;

  /// Se piensa la semana desde el lunes.
  static const _orden = [1, 2, 3, 4, 5, 6, 0];
  static const _cortos = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _elegirFin() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _hasta ?? hoy.add(const Duration(days: 7)),
      firstDate: hoy,
      lastDate: hoy.add(const Duration(days: 365)),
    );
    if (elegida != null) setState(() => _hasta = elegida);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_alcance == AlcancePromocion.secciones && _secciones.isEmpty) {
      mostrarError(context, 'Elegí al menos un menú.');
      return;
    }
    if (_alcance == AlcancePromocion.productos && _productos.isEmpty) {
      mostrarError(context, 'Elegí al menos un producto.');
      return;
    }
    try {
      await ref.read(promocionesRepositoryProvider).guardar(
            comercioId: widget.comercioId,
            id: widget.editar?.id,
            nombre: _nombre.text,
            porcentaje: _porcentaje,
            alcance: _alcance,
            dias: _dias.toList()..sort(),
            desde: widget.editar?.desde,
            hasta: _hasta,
            // Editar una promo pausada no la vuelve a prender: antes `guardar`
            // la mandaba siempre activa.
            activa: widget.editar?.activa ?? true,
            secciones: _secciones.toList(),
            productos: _productos.toList(),
          );
      ref.invalidate(menuDeComercioProvider(widget.comercioId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Widget _titulo(String texto, {String? bajada}) => Padding(
        padding: const EdgeInsets.only(bottom: MySpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(texto, style: MyType.headlineSm),
            if (bajada != null) Text(bajada, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final menu = widget.menu;
    const separacion = SizedBox(height: MySpacing.lg);

    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo('El descuento'),
          MyCampo(
            controller: _nombre,
            label: 'Cómo se llama',
            hint: 'Ej: Martes de pizza',
            icon: Symbols.sell,
            validar: (v) => v.trim().isEmpty ? 'Ponele un nombre' : null,
          ),
          const MyOverline('Cuánto descontás'),
          const SizedBox(height: MySpacing.xs),
          Row(
            children: [
              Contador(
                valor: _porcentaje,
                minimo: 1,
                maximo: 90,
                paso: 5,
                formato: (n) => '$n%',
                onChanged: (n) => setState(() => _porcentaje = n),
              ),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  'Un producto de \$10.000 queda en ${Formato.pesos(10000 * (100 - _porcentaje) ~/ 100)}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ),
            ],
          ),
          separacion,
          _titulo('Sobre qué'),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              for (final a in AlcancePromocion.values)
                MyChip(a.rotulo, selected: _alcance == a, onTap: () => setState(() => _alcance = a)),
            ],
          ),
          if (_alcance == AlcancePromocion.secciones) ...[
            const SizedBox(height: MySpacing.sm),
            Text('Elegí los menús con descuento', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
            const SizedBox(height: MySpacing.xs),
            if (menu.secciones.isEmpty)
              Text('Todavía no tenés secciones en el menú.', style: MyType.bodySm.copyWith(color: MyColors.error))
            else
              Wrap(
                spacing: MySpacing.xs,
                runSpacing: MySpacing.xs,
                children: [
                  for (final s in menu.secciones)
                    MyChip(
                      s.nombre,
                      selected: _secciones.contains(s.id),
                      onTap: () => setState(() => _secciones.contains(s.id) ? _secciones.remove(s.id) : _secciones.add(s.id)),
                    ),
                ],
              ),
          ],
          if (_alcance == AlcancePromocion.productos) ...[
            const SizedBox(height: MySpacing.sm),
            Text(
              _productos.isEmpty ? 'Elegí los productos con descuento' : '${_productos.length} elegidos',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: MySpacing.xs,
                  runSpacing: MySpacing.xs,
                  children: [
                    for (final p in menu.productos)
                      MyChip(
                        p.nombre,
                        selected: _productos.contains(p.id),
                        onTap: () => setState(() => _productos.contains(p.id) ? _productos.remove(p.id) : _productos.add(p.id)),
                      ),
                  ],
                ),
              ),
            ),
          ],
          separacion,
          _titulo('Cuándo', bajada: _dias.isEmpty ? 'Todos los días' : 'Solo los días marcados'),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              MyChip('Todos', selected: _dias.isEmpty, onTap: () => setState(_dias.clear)),
              for (final d in _orden)
                MyChip(
                  _cortos[d],
                  selected: _dias.contains(d),
                  onTap: () => setState(() => _dias.contains(d) ? _dias.remove(d) : _dias.add(d)),
                ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Row(
            children: [
              Icon(Symbols.event, size: 20, color: MyColors.secondary),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: Text(
                  _hasta == null ? 'Sin fecha de fin' : 'Hasta el ${Formato.fechaCorta(_hasta!)}',
                  style: MyType.bodyMd,
                ),
              ),
              MyBoton(
                label: _hasta == null ? 'Poner fin' : 'Quitar',
                tipo: MyBotonTipo.secundario,
                onPressed: _hasta == null ? _elegirFin : () => setState(() => _hasta = null),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.xl),
          MyBotonAccion(
            label: widget.editar == null ? 'Activar la promo' : 'Guardar cambios',
            icon: Symbols.sell,
            onPressed: _guardar,
          ),
        ],
      ),
    );
  }
}
