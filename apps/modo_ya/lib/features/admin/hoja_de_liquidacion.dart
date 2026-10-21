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
/// El documento en sí (`MyHojaDescargable`) y su armado (`hojaDeRider`) son los
/// mismos que usan la app del rider y la pantalla del local: acá solo se elige
/// a quién mirar y se agregan las acciones que puede hacer la administración.
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
    builder: (_) => _HojaDeComercio(pendiente: p, desde: desde, hasta: hasta),
  );
}

/// El detalle de una liquidación ya cerrada, para cualquiera de los dos.
Future<void> mostrarHojaCerrada(
  BuildContext context,
  Liquidacion l, {
  String? titular,
  bool paraElMismo = false,
}) {
  return mostrarHojaLateral(
    context,
    titulo: 'Liquidación cerrada',
    builder: (_) => HojaCerrada(liquidacion: l, titular: titular, paraElMismo: paraElMismo),
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
    final rango = (repartidorId: p.repartidorId, desde: desde, hasta: hasta);
    final envios = ref.watch(detalleDeRiderProvider(rango));
    final cargos = ref.watch(cargosDelPeriodoRiderProvider(rango));

    // Se espera a que estén los dos: una hoja a medio armar invita a bajar un
    // PDF al que le falta la mitad de los renglones.
    return MyAsync(
      valor: envios,
      onReintentar: () => ref.invalidate(detalleDeRiderProvider(rango)),
      datos: (lista) => MyAsync(
        valor: cargos,
        onReintentar: () => ref.invalidate(cargosDelPeriodoRiderProvider(rango)),
        datos: (losCargos) => MyHojaDescargable(
          hoja: hojaDeRider(
            resumen: p,
            envios: lista,
            cargos: losCargos,
            desde: desde,
            hasta: hasta,
          ),
          acciones: [
            MyBoton(
              label: 'Cargarle algo',
              icon: Symbols.add,
              tipo: MyBotonTipo.texto,
              onPressed: () => cargarARider(context, ref, p.repartidorId, p.rider),
            ),
          ],
        ),
      ),
    );
  }
}

class _HojaDeComercio extends ConsumerWidget {
  const _HojaDeComercio({required this.pendiente, required this.desde, required this.hasta});

  final PendienteComercio pendiente;
  final DateTime desde;
  final DateTime hasta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pendiente;
    final rango = (comercioId: p.comercioId, desde: desde, hasta: hasta);
    final pedidos = ref.watch(detalleDeComercioProvider(rango));
    final cargos = ref.watch(cargosDelPeriodoComercioProvider(rango));

    return MyAsync(
      valor: pedidos,
      onReintentar: () => ref.invalidate(detalleDeComercioProvider(rango)),
      datos: (lista) => MyAsync(
        valor: cargos,
        onReintentar: () => ref.invalidate(cargosDelPeriodoComercioProvider(rango)),
        datos: (losCargos) => MyHojaDescargable(
          hoja: hojaDeComercio(
            resumen: p,
            pedidos: lista,
            cargos: losCargos,
            desde: desde,
            hasta: hasta,
          ),
        ),
      ),
    );
  }
}

/// El renglón por renglón de una liquidación ya cerrada.
///
/// Es pública porque la usan las tres pantallas de historial (administración,
/// rider y local) con la misma hoja y el mismo PDF.
class HojaCerrada extends ConsumerWidget {
  const HojaCerrada({
    super.key,
    required this.liquidacion,
    this.titular,
    this.paraElMismo = false,
  });

  final Liquidacion liquidacion;

  /// El nombre que va en el encabezado. El historial propio no trae el nombre
  /// en la consulta (sería siempre el mismo), así que lo pone la pantalla.
  final String? titular;
  final bool paraElMismo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clave = (liquidacionId: liquidacion.id, esComercio: liquidacion.esComercio);
    final renglones = ref.watch(renglonesCerradosProvider(clave));

    return MyAsync(
      valor: renglones,
      onReintentar: () => ref.invalidate(renglonesCerradosProvider(clave)),
      datos: (lista) => MyHojaDescargable(
        hoja: hojaCerrada(
          liquidacion: liquidacion,
          renglones: lista,
          titular: titular,
          paraElMismo: paraElMismo,
        ),
      ),
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
                  // Sin período a mano: se invalida toda la familia, que son
                  // dos o tres consultas y se rearman solas.
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
