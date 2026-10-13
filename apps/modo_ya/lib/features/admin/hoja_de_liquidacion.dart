import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';

/// El detalle de lo que se le va a pagar a un rider, como una hoja.
///
/// Entra desde la derecha y tapa la mitad: así se compara el renglón de la
/// lista con el detalle sin ir y volver. Es un documento, no una pantalla —
/// está pensado para leerlo con el rider al lado y poder discutir cada línea.
Future<void> mostrarHojaDeRider(
  BuildContext context,
  PendienteRider p,
  DateTime desde,
  DateTime hasta,
) {
  return mostrarHojaLateral(
    context,
    titulo: 'Liquidación',
    builder: (_) => _HojaDeRider(pendiente: p, desde: desde, hasta: hasta),
  );
}

class _HojaDeRider extends ConsumerWidget {
  const _HojaDeRider({required this.pendiente, required this.desde, required this.hasta});

  final PendienteRider pendiente;
  final DateTime desde;
  final DateTime hasta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pendiente;
    final detalle = ref.watch(detalleDeRiderProvider(
      (repartidorId: p.repartidorId, desde: desde, hasta: hasta),
    ));
    final cargos = ref.watch(cargosDeRiderProvider(p.repartidorId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyHojaImpresa(
          children: [
            // ---- Encabezado del documento ------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MODO YA', style: MyType.labelLg.copyWith(color: MyColors.secondary)),
                      const SizedBox(height: 2),
                      Text(p.rider, style: MyType.headlineMd),
                      Text(
                        'Del ${Formato.fechaCorta(desde)} al ${Formato.fechaCorta(hasta)}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ),
                MyBadge(
                  p.total >= 0 ? 'A pagarle' : 'Tiene que rendir',
                  tone: p.total >= 0 ? MyBadgeTone.success : MyBadgeTone.danger,
                ),
              ],
            ),
            const Divider(height: MySpacing.xl),

            // ---- Los envíos ----------------------------------------------------
            Text('Envíos entregados', style: MyType.labelLg),
            const SizedBox(height: MySpacing.xs),
            MyAsync(
              valor: detalle,
              onReintentar: () => ref.invalidate(detalleDeRiderProvider(
                (repartidorId: p.repartidorId, desde: desde, hasta: hasta),
              )),
              datos: (lista) {
                if (lista.isEmpty) {
                  return Text(
                    'No entregó nada en este período.',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in lista)
                      MyRenglon(
                        '${e.codigo} · ${e.comercio}',
                        Formato.pesos(e.ganancia),
                        detalle: '${Formato.fechaHora(e.entregado)} · ${e.destino}'
                            '${e.efectivo == 0 ? '' : ' · cobró ${Formato.pesos(e.efectivo)}'}',
                      ),
                  ],
                );
              },
            ),

            const Divider(height: MySpacing.xl),

            // ---- Los cargos ----------------------------------------------------
            Row(
              children: [
                Expanded(child: Text('Cargos', style: MyType.labelLg)),
                MyBoton(
                  label: 'Agregar',
                  icon: Symbols.add,
                  tipo: MyBotonTipo.texto,
                  onPressed: () => cargarARider(context, ref, p.repartidorId, p.rider),
                ),
              ],
            ),
            const SizedBox(height: MySpacing.xs),
            MyAsync(
              valor: cargos,
              onReintentar: () => ref.invalidate(cargosDeRiderProvider(p.repartidorId)),
              datos: (lista) {
                final delPeriodo = lista
                    .where((c) => !c.fecha.isBefore(desde) && !c.fecha.isAfter(hasta))
                    .toList();
                if (delPeriodo.isEmpty) {
                  return Text(
                    'Sin cargos en este período.',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in delPeriodo)
                      MyRenglon(
                        c.concepto.rotulo,
                        Formato.pesos(c.monto),
                        detalle: '${Formato.fechaCorta(c.fecha)} · ${c.detalle}',
                        color: c.monto > 0 ? MyColors.error : MyColors.success,
                      ),
                  ],
                );
              },
            ),

            const Divider(height: MySpacing.xl),

            // ---- El cierre ------------------------------------------------------
            MyRenglon('Ganó por ${p.envios} ${p.envios == 1 ? "envío" : "envíos"}',
                Formato.pesos(p.ganancias)),
            if (p.efectivo != 0)
              MyRenglon('Cobró en efectivo', '− ${Formato.pesos(p.efectivo)}',
                  detalle: 'Lo juntó en la puerta y lo tiene que rendir',
                  color: MyColors.secondary),
            if (p.cargos != 0)
              MyRenglon('Cargos', '− ${Formato.pesos(p.cargos)}', color: MyColors.error),
            const Divider(height: MySpacing.lg),
            MyRenglon(
              p.total >= 0 ? 'A pagarle' : 'Tiene que rendir',
              Formato.pesos(p.total.abs()),
              fuerte: true,
              color: p.total >= 0 ? MyColors.tertiary : MyColors.error,
            ),
          ],
        ),
      ],
    );
  }
}

/// Carga un cargo a un rider. Lo decide una persona: el sistema registra las
/// bajadas, pero no cobra solo.
Future<void> cargarARider(
  BuildContext context,
  WidgetRef ref,
  String repartidorId,
  String rider, {
  String? envioId,
  ConceptoCargoRider? concepto,
  String? detalleSugerido,
}) async {
  final monto = TextEditingController();
  final detalle = TextEditingController(text: detalleSugerido ?? '');
  final form = GlobalKey<FormState>();
  var elegido = concepto ?? ConceptoCargoRider.abandono;

  await mostrarFormularioEmergente(
    context,
    titulo: 'Cargarle algo a $rider',
    builder: (h) => StatefulBuilder(
      builder: (h, refrescar) => Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Se le descuenta de lo que cobra en su próxima liquidación. '
              'Un monto negativo se lo devuelve.',
              style: MyType.bodyMd.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.md),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (final c in ConceptoCargoRider.values)
                  MyChip(c.rotulo, selected: elegido == c, onTap: () => refrescar(() => elegido = c)),
              ],
            ),
            const SizedBox(height: MySpacing.md),
            MyCampo(
              controller: detalle,
              label: 'Por qué',
              hint: 'Se bajó con el pedido listo en el local',
              icon: Symbols.notes,
              validar: (v) => v.trim().isEmpty ? 'Escribí por qué se le cobra' : null,
            ),
            MyCampo(
              controller: monto,
              label: 'Cuánto',
              hint: '4000',
              icon: Symbols.payments,
              validar: (v) {
                final n = int.tryParse(v.replaceAll('-', ''));
                if (n == null || n == 0) return 'Escribí un monto';
                return null;
              },
            ),
            MyBotonAccion(
              label: 'Cargar',
              icon: Symbols.check,
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                try {
                  await ref.read(liquidacionesRepositoryProvider).cargarARider(
                        repartidorId: repartidorId,
                        concepto: elegido,
                        detalle: detalle.text,
                        monto: int.parse(monto.text.replaceAll(' ', '')),
                        envioId: envioId,
                      );
                  ref.invalidate(cargosDeRiderProvider(repartidorId));
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

  monto.dispose();
  detalle.dispose();
}
