// Liquidaciones de la administración a los tres anchos, sin base.
//
// Existe por dos cosas que se rompían en el celular y la tableta:
//
// - La tabla de seis o siete columnas de plata se dibujaba igual en una
//   tableta, con 80 px por columna, y la fila de una liquidación cerrada
//   (icono, textos, saldo y "Marcar pagada" en un solo renglón) no entraba en
//   360 px.
// - Cerrar una liquidación o cargarle algo se hacía desde la fila, lejos del
//   renglón por renglón. Ahora tocar la fila abre la hoja y las acciones
//   están adentro.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/admin/liquidaciones_page.dart';

import 'soporte.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  const local = PendienteComercio(
    comercioId: 'c1',
    comercio: 'Pizzería Don Luis de la Avenida San Martín',
    pedidos: 42,
    ventas: 1250000,
    cargos: 185000,
    total: 1065000,
  );
  const rider = PendienteRider(
    repartidorId: 'r1',
    rider: 'Juan Pérez',
    envios: 31,
    ganancias: 108500,
    efectivo: 42000,
    cargos: 4000,
    total: 62500,
  );
  final cerrada = Liquidacion(
    id: 'l1',
    nombre: 'Heladería del Sur',
    desde: DateTime(2026, 10, 13),
    hasta: DateTime(2026, 10, 19),
    aFavor: 980000,
    enContra: 120000,
    ajustes: 0,
    total: 860000,
    pagada: false,
    esComercio: true,
  );

  Future<void> mostrar(WidgetTester tester, Size tamanio) async {
    enPantalla(tester, tamanio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pendientesComerciosProvider.overrideWith((ref, _) => Stream.value(const [local])),
        pendientesRidersProvider.overrideWith((ref, _) => Stream.value(const [rider])),
        historialLiquidacionesProvider.overrideWith((ref) => Stream.value([cerrada])),
        detalleDeComercioProvider.overrideWith((ref, _) async => const []),
        cargosDelPeriodoComercioProvider.overrideWith((ref, _) async => const []),
        detalleDeRiderProvider.overrideWith((ref, _) async => const []),
        cargosDelPeriodoRiderProvider.overrideWith((ref, _) async => const []),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: LiquidacionesPage())),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  for (final (formato, tamanio) in anchos) {
    group('En $formato', () {
      testWidgets('tocar un local abre su hoja con los cargos y el cierre adentro', (tester) async {
        await mostrar(tester, tamanio);

        await tocar(tester, find.text(local.comercio).first);

        expect(find.widgetWithText(MyBoton, 'Cerrar liquidación'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Cargos'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Bajar PDF'), findsOneWidget);
      });

      testWidgets('tocar un rider abre su hoja con el cierre y el cargo adentro', (tester) async {
        await mostrar(tester, tamanio);
        await tocar(tester, find.text('Riders (1)'));

        await tocar(tester, find.text('Juan Pérez').first);

        expect(find.widgetWithText(MyBoton, 'Cerrar liquidación'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Cargarle algo'), findsOneWidget);
      });

      testWidgets('una liquidación cerrada sin pagar entra con su botón', (tester) async {
        await mostrar(tester, tamanio);
        await tocar(tester, find.text('Cerradas (1)'));

        expect(find.text('Heladería del Sur'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Marcar pagada'), findsOneWidget);
      });
    });
  }

  testWidgets('los avisos de Mercado Pago siguen a mano desde Liquidaciones', (tester) async {
    await mostrar(tester, const Size(360, 800));

    expect(find.widgetWithText(MyBoton, 'Avisos de Mercado Pago'), findsOneWidget);
  });
}
