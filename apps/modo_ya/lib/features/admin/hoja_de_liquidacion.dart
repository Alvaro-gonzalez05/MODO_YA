import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';

/// El detalle de lo que se le va a pagar a un rider o a un local, como una hoja.
///
/// Entra desde la derecha y tapa la mitad: así se compara el renglón de la
/// lista con el detalle sin ir y volver. Es un documento, no una pantalla —
/// está pensado para leerlo con el rider al lado y poder discutir cada línea.
///
/// La hoja en sí (`MyHojaDeRider`) y su PDF viven en `my_ui`: son los mismos
/// que ve el rider en su app y el local en su pantalla. Acá solo se elige a
/// quién mirar y se agrega lo único que la administración puede hacer y los
/// demás no: cargarle algo.
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

/// Lo mismo para un local: qué pedidos entraron y qué se le descuenta.
Future<void> mostrarHojaDeComercio(
  BuildContext context,
  PendienteComercio p,
  DateTime desde,
  DateTime hasta,
) {
  return mostrarHojaLateral(
    context,
    titulo: 'Liquidación',
    builder: (_) => MyHojaDeComercio(resumen: p, desde: desde, hasta: hasta),
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
    return MyHojaDeRider(
      resumen: p,
      desde: desde,
      hasta: hasta,
      acciones: [
        MyBoton(
          label: 'Cargarle algo',
          icon: Symbols.add,
          tipo: MyBotonTipo.texto,
          onPressed: () => cargarARider(context, ref, p.repartidorId, p.rider),
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
                  // Sin el período a mano se invalida toda la familia: son dos
                  // o tres consultas y se rearman solas.
                  ref.invalidate(cargosDelPeriodoRiderProvider);
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
