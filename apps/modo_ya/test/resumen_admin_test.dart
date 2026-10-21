// El resumen de la administración, sin base.
//
// Existe por un error concreto: el panel leía sus cinco consultas con
// `.value ?? const []`, así que una consulta caída se veía igual que una sin
// datos — ceros y un cartel verde diciendo "Todo en orden". Estas pruebas
// fijan que un error se vea como error y que el "Todo en orden" solo salga
// cuando las cinco consultas contestaron.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/admin/dashboard_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin bajar tipografias por HTTPS: dejan temporizadores pendientes al cerrar.
  GoogleFonts.config.allowRuntimeFetching = false;

  // El Scaffold lo pone el contenedor de cada rol, no la pantalla.
  Widget app(Widget pantalla) =>
      MaterialApp(theme: MyTheme.claro, home: Scaffold(body: pantalla));

  // Las cinco consultas del panel, vacias salvo las que se pisen. Sin tipo de
  // retorno a proposito: `Override` no sale del paquete publico de Riverpod.
  consultas({
    Stream<List<Comercio>>? comercios,
    Stream<List<Repartidor>>? riders,
    Stream<List<Envio>>? envios,
    Stream<List<Pedido>>? porCobrar,
    Stream<List<Preinscripcion>>? preinscripciones,
  }) =>
      [
        todosLosComerciosProvider.overrideWith((ref) => comercios ?? Stream.value(const [])),
        todosLosRepartidoresProvider.overrideWith((ref) => riders ?? Stream.value(const [])),
        enviosActivosProvider.overrideWith((ref) => envios ?? Stream.value(const [])),
        pedidosPendientesDePagoProvider.overrideWith((ref) => porCobrar ?? Stream.value(const [])),
        preinscripcionesProvider.overrideWith((ref) => preinscripciones ?? Stream.value(const [])),
      ];

  group('Cuando una consulta falla', () {
    testWidgets('se ve el error y se puede reintentar, no "Todo en orden"',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: consultas(
          envios: Stream.error(const ErrorModoYa('Sin conexión.')),
        ),
        child: app(const DashboardPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar esto'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.textContaining('Todo en orden'), findsNothing);
      // Lo peor del error anterior: los numeros en cero como si fueran ciertos.
      // El rotulo del indicador va en mayusculas (MyKpi).
      expect(find.text('ENVÍOS EN LA CALLE'), findsNothing);
    });

    testWidgets('alcanza con que falle una de las cinco', (tester) async {
      for (final override in [
        consultas(comercios: Stream.error(const ErrorModoYa('x'))),
        consultas(riders: Stream.error(const ErrorModoYa('x'))),
        consultas(envios: Stream.error(const ErrorModoYa('x'))),
        consultas(porCobrar: Stream.error(const ErrorModoYa('x'))),
        consultas(preinscripciones: Stream.error(const ErrorModoYa('x'))),
      ]) {
        await tester.pumpWidget(ProviderScope(
          overrides: override,
          child: app(const DashboardPage()),
        ));
        await tester.pumpAndSettle();

        expect(find.text('No pudimos cargar esto'), findsOneWidget);
      }
    });
  });

  group('Cuando las cinco contestan', () {
    testWidgets('sin nada pendiente dice que esta todo en orden', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: consultas(),
        child: app(const DashboardPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Todo en orden'), findsOneWidget);
      expect(find.text('No pudimos cargar esto'), findsNothing);
      expect(find.text('ENVÍOS EN LA CALLE'), findsOneWidget);
    });
  });
}
