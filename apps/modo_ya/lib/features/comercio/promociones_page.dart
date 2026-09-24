import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Sello(porcentaje: p.porcentaje, encendido: p.vigente),
              const SizedBox(width: MySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre, style: MyType.headlineSm),
                    Text(
                      '${p.detalle} · ${p.cuando}',
                      style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                    ),
                    if (p.hasta != null)
                      Text(
                        'Hasta el ${Formato.fechaCorta(p.hasta!)}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: MySpacing.sm),
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

  final nombre = TextEditingController(text: editar?.nombre ?? '');
  final porcentaje = TextEditingController(text: editar?.porcentaje.toString() ?? '');
  final form = GlobalKey<FormState>();

  var alcance = editar?.alcance ?? AlcancePromocion.todo;
  var dias = {...(editar?.dias ?? const <int>[])};
  final secciones = {...?alcanceGuardado?.secciones};
  final productos = {...?alcanceGuardado?.productos};
  DateTime? hasta = editar?.hasta;

  await mostrarFormularioEmergente(
    context,
    titulo: editar == null ? 'Nueva promoción' : 'Editar promoción',
    builder: (h) => StatefulBuilder(
      builder: (h, refrescar) => Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyCampo(
              controller: nombre,
              label: 'Cómo se llama',
              hint: 'Martes de pizza',
              icon: Symbols.sell,
              validar: (v) => v.trim().isEmpty ? 'Ponele un nombre' : null,
            ),
            MyCampo(
              controller: porcentaje,
              label: 'Cuánto descontás (%)',
              hint: '20',
              icon: Symbols.percent,
              soloNumeros: true,
              validar: (v) {
                final n = int.tryParse(v) ?? 0;
                return n < 1 || n > 90 ? 'Entre 1% y 90%' : null;
              },
            ),
            const SizedBox(height: MySpacing.sm),
            Text('¿Sobre qué?', style: MyType.labelLg),
            const SizedBox(height: MySpacing.xs),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (final a in AlcancePromocion.values)
                  MyChip(
                    a.rotulo,
                    selected: alcance == a,
                    onTap: () => refrescar(() => alcance = a),
                  ),
              ],
            ),
            if (alcance == AlcancePromocion.secciones) ...[
              const SizedBox(height: MySpacing.sm),
              Text(
                'Elegí los menús con descuento',
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
              const SizedBox(height: MySpacing.xs),
              Wrap(
                spacing: MySpacing.xs,
                runSpacing: MySpacing.xs,
                children: [
                  for (final s in menu.secciones)
                    MyChip(
                      s.nombre,
                      selected: secciones.contains(s.id),
                      onTap: () => refrescar(
                        () => secciones.contains(s.id) ? secciones.remove(s.id) : secciones.add(s.id),
                      ),
                    ),
                ],
              ),
            ],
            if (alcance == AlcancePromocion.productos) ...[
              const SizedBox(height: MySpacing.sm),
              Text(
                'Elegí los productos con descuento',
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
                          selected: productos.contains(p.id),
                          onTap: () => refrescar(
                            () => productos.contains(p.id) ? productos.remove(p.id) : productos.add(p.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: MySpacing.md),
            Text('¿Qué días?', style: MyType.labelLg),
            Text(
              dias.isEmpty ? 'Todos los días' : 'Solo los días marcados',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.xs),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (var d = 0; d < 7; d++)
                  MyChip(
                    const ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'][d],
                    selected: dias.contains(d),
                    onTap: () => refrescar(() => dias.contains(d) ? dias.remove(d) : dias.add(d)),
                  ),
              ],
            ),
            const SizedBox(height: MySpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasta == null ? 'Sin fecha de fin' : 'Hasta el ${Formato.fechaCorta(hasta!)}',
                    style: MyType.bodyMd,
                  ),
                ),
                MyBoton(
                  label: hasta == null ? 'Poner fin' : 'Quitar',
                  icon: Symbols.event,
                  tipo: MyBotonTipo.secundario,
                  onPressed: () async {
                    if (hasta != null) {
                      refrescar(() => hasta = null);
                      return;
                    }
                    final hoy = DateTime.now();
                    final elegida = await showDatePicker(
                      context: h,
                      initialDate: hoy.add(const Duration(days: 7)),
                      firstDate: hoy,
                      lastDate: hoy.add(const Duration(days: 365)),
                    );
                    if (elegida != null) refrescar(() => hasta = elegida);
                  },
                ),
              ],
            ),
            const SizedBox(height: MySpacing.md),
            MyBotonAccion(
              label: editar == null ? 'Activar la promo' : 'Guardar',
              icon: Symbols.sell,
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                if (alcance == AlcancePromocion.secciones && secciones.isEmpty) {
                  mostrarAviso(h, 'Elegí al menos un menú.');
                  return;
                }
                if (alcance == AlcancePromocion.productos && productos.isEmpty) {
                  mostrarAviso(h, 'Elegí al menos un producto.');
                  return;
                }
                try {
                  await ref.read(promocionesRepositoryProvider).guardar(
                        comercioId: comercioId,
                        id: editar?.id,
                        nombre: nombre.text,
                        porcentaje: int.parse(porcentaje.text),
                        alcance: alcance,
                        dias: dias.toList()..sort(),
                        hasta: hasta,
                        secciones: secciones.toList(),
                        productos: productos.toList(),
                      );
                  ref.invalidate(menuDeComercioProvider(comercioId));
                  if (h.mounted) Navigator.pop(h);
                } catch (e) {
                  if (h.mounted) mostrarError(h, e);
                }
              },
            ),
          ],
        ),
      ),
    ),
  );

  nombre.dispose();
  porcentaje.dispose();
}
