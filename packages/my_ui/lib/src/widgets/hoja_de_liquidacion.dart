import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';

import '../hoja_en_pdf.dart';
import '../tokens.dart';
import '../typography.dart';
import 'controls.dart';
import 'escritorio.dart';
import 'formularios.dart';
import 'hoja_lateral.dart';

/// Color de cada tono. Afuera del widget porque el PDF decide con el mismo
/// criterio sobre su propia paleta.
Color? colorDeTono(TonoDeRenglon tono) => switch (tono) {
      TonoDeRenglon.neutro => null,
      TonoDeRenglon.apagado => MyColors.secondary,
      TonoDeRenglon.contra => MyColors.error,
      TonoDeRenglon.aFavor => MyColors.tertiary,
    };

/// La hoja de liquidación en pantalla.
///
/// Es un documento, no una pantalla: está pensada para leerla con el rider o
/// con el dueño del local al lado y poder discutir cada línea. Por eso vive en
/// `my_ui` y no en la app de administración — la administración, el rider y el
/// local leen el mismo papel, armado por `hojaDeRider` / `hojaDeComercio` /
/// `hojaCerrada` en `my_core`.
class MyHojaDeLiquidacion extends StatelessWidget {
  const MyHojaDeLiquidacion({super.key, required this.hoja, this.acciones = const []});

  final HojaDeLiquidacion hoja;

  /// Botones del encabezado: bajar el PDF, cargarle algo, cerrarla.
  final List<Widget> acciones;

  Widget _renglon(RenglonDeHoja r) => MyRenglon(
        r.concepto,
        r.valor,
        detalle: r.detalle,
        fuerte: r.fuerte,
        color: colorDeTono(r.tono),
      );

  @override
  Widget build(BuildContext context) {
    return MyHojaImpresa(
      children: [
        // ---- Encabezado del documento ----------------------------------------
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MODO YA', style: MyType.labelLg.copyWith(color: MyColors.secondary)),
                  const SizedBox(height: 2),
                  Text(hoja.titular, style: MyType.headlineMd),
                  Text(hoja.periodo, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                ],
              ),
            ),
            MyBadge(
              hoja.etiqueta,
              tone: hoja.aFavor ? MyBadgeTone.success : MyBadgeTone.danger,
            ),
          ],
        ),
        if (acciones.isNotEmpty) ...[
          const SizedBox(height: MySpacing.sm),
          // En Wrap y no en Row: la hoja también se abre en el celular, donde
          // dos botones en una línea se cortan.
          Wrap(
            alignment: WrapAlignment.end,
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: acciones,
          ),
        ],

        // ---- Los bloques -------------------------------------------------------
        for (final b in hoja.bloques) ...[
          const Divider(height: MySpacing.xl),
          Text(b.titulo, style: MyType.labelLg),
          const SizedBox(height: MySpacing.xs),
          if (b.renglones.isEmpty)
            Text(b.vacio, style: MyType.bodySm.copyWith(color: MyColors.secondary))
          else
            for (final r in b.renglones) _renglon(r),
        ],

        // ---- El cierre ---------------------------------------------------------
        const Divider(height: MySpacing.xl),
        for (final r in hoja.cierre) _renglon(r),
        const Divider(height: MySpacing.lg),
        _renglon(hoja.total),
      ],
    );
  }
}

/// La hoja con el botón de PDF ya puesto.
///
/// El botón vive acá y no en cada pantalla porque los tres roles bajan el mismo
/// archivo: si cada app armara el suyo, el día que cambie el nombre del archivo
/// o el aviso de error habría que acordarse de tres lugares.
class MyHojaDescargable extends StatelessWidget {
  const MyHojaDescargable({super.key, required this.hoja, this.acciones = const []});

  final HojaDeLiquidacion hoja;

  /// Lo que puede hacer este rol además de bajarla (cargar un cargo, cerrarla).
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    return MyHojaDeLiquidacion(
      hoja: hoja,
      acciones: [
        MyBoton(
          label: 'Bajar PDF',
          icon: Symbols.download,
          tipo: MyBotonTipo.texto,
          onPressed: () async {
            try {
              await guardarHojaEnPdf(hoja);
            } catch (e) {
              if (context.mounted) mostrarError(context, e);
            }
          },
        ),
        ...acciones,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Las hojas que traen sus propios datos
// ---------------------------------------------------------------------------
//
// Van acá y no en cada app porque las tres pantallas piden lo mismo a las
// mismas funciones: la administración mirando a un rider y el rider mirándose a
// sí mismo leen el mismo documento. Lo único que cambia es `paraElMismo` (cómo
// se le habla) y las acciones que tiene permitidas cada rol.

/// La liquidación de un rider en el período en curso.
class MyHojaDeRider extends ConsumerWidget {
  const MyHojaDeRider({
    super.key,
    required this.resumen,
    required this.desde,
    required this.hasta,
    this.paraElMismo = false,
    this.acciones = const [],
  });

  final PendienteRider resumen;
  final DateTime desde;
  final DateTime hasta;
  final bool paraElMismo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rango = (repartidorId: resumen.repartidorId, desde: desde, hasta: hasta);
    final envios = ref.watch(detalleDeRiderProvider(rango));
    final cargos = ref.watch(cargosDelPeriodoRiderProvider(rango));

    // Se esperan los dos: una hoja a medio armar invita a bajar un PDF al que
    // le falta la mitad de los renglones.
    return MyAsync(
      valor: envios,
      onReintentar: () => ref.invalidate(detalleDeRiderProvider(rango)),
      datos: (lista) => MyAsync(
        valor: cargos,
        onReintentar: () => ref.invalidate(cargosDelPeriodoRiderProvider(rango)),
        datos: (losCargos) => MyHojaDescargable(
          hoja: hojaDeRider(
            resumen: resumen,
            envios: lista,
            cargos: losCargos,
            desde: desde,
            hasta: hasta,
            paraElMismo: paraElMismo,
          ),
          acciones: acciones,
        ),
      ),
    );
  }
}

/// La liquidación de un local en el período en curso.
class MyHojaDeComercio extends ConsumerWidget {
  const MyHojaDeComercio({
    super.key,
    required this.resumen,
    required this.desde,
    required this.hasta,
    this.paraElMismo = false,
    this.acciones = const [],
  });

  final PendienteComercio resumen;
  final DateTime desde;
  final DateTime hasta;
  final bool paraElMismo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rango = (comercioId: resumen.comercioId, desde: desde, hasta: hasta);
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
            resumen: resumen,
            pedidos: lista,
            cargos: losCargos,
            desde: desde,
            hasta: hasta,
            paraElMismo: paraElMismo,
          ),
          acciones: acciones,
        ),
      ),
    );
  }
}

/// El renglón por renglón de una liquidación ya cerrada, de un local o de un
/// rider.
class MyHojaCerrada extends ConsumerWidget {
  const MyHojaCerrada({
    super.key,
    required this.liquidacion,
    this.titular,
    this.paraElMismo = false,
  });

  final Liquidacion liquidacion;

  /// El historial propio no trae el nombre en la consulta (sería siempre el
  /// mismo), así que lo pone la pantalla.
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

/// Abre la hoja de una liquidación cerrada como panel lateral.
Future<void> mostrarHojaCerrada(
  BuildContext context,
  Liquidacion l, {
  String? titular,
  bool paraElMismo = false,
}) {
  return mostrarHojaLateral(
    context,
    titulo: 'Liquidación cerrada',
    builder: (_) => MyHojaCerrada(liquidacion: l, titular: titular, paraElMismo: paraElMismo),
  );
}
