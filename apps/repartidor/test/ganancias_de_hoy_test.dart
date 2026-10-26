// "Mis ganancias" del rider: el número de "HOY", sin base.
//
// Existe por un error concreto: el cartel sumaba solo `gananciaRepartidor` de
// los envíos entregados. No restaba el efectivo que el rider junta en la puerta
// (un mandado se cobra entero en mano, 0052) ni los cargos de 0062, así que era
// el único de los tres cálculos de "lo que cobra el rider" que podía dar un
// número de signo distinto al de la liquidación: con dos mandados en el día
// decía "HOY $6.000" cuando la liquidación iba a dar negativa.
//
// Y la semana se calculaba sobre los últimos 100 envíos, que es todo lo que
// trae el stream: una semana cargada subcontaba sin decirlo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya_repartidor/features/ganancias_page.dart';

/// Repositorio de prueba: devuelve el resumen del día y el de la semana según
/// el período que le piden, igual que `pendiente_de_liquidar_riders`.
class _LiquidacionesFalso implements LiquidacionesRepository {
  _LiquidacionesFalso({this.hoy, this.semana});

  final PendienteRider? hoy;
  final PendienteRider? semana;

  @override
  Stream<List<PendienteRider>> watchPendientesRiders(DateTime desde, DateTime hasta) {
    // Un día: desde y hasta son la misma fecha. Cualquier otro rango es la
    // semana, que es el único otro período que esta pantalla pide.
    final esUnDia = desde.year == hasta.year && desde.month == hasta.month && desde.day == hasta.day;
    final r = esUnDia ? hoy : semana;
    return Stream.value(r == null ? const [] : [r]);
  }

  @override
  Future<List<RenglonDeRider>> detalleDeRider(String repartidorId, DateTime desde, DateTime hasta) async =>
      const [];

  @override
  Future<List<RenglonDeCargo>> cargosDelRider(String repartidorId, DateTime desde, DateTime hasta) async =>
      const [];

  @override
  Stream<List<Liquidacion>> watchMisLiquidacionesRider(String repartidorId) => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin bajar tipografias por HTTPS: dejan temporizadores pendientes al cerrar.
  GoogleFonts.config.allowRuntimeFetching = false;
  // La pantalla escribe fechas con `Formato`: sin esto el DateFormat explota.
  initializeDateFormatting('es_AR');

  const yo = Sesion(
    usuarioId: 'u1',
    rol: RolUsuario.repartidor,
    nombre: 'Rider',
    repartidorId: 'r1',
  );

  PendienteRider resumen({
    int envios = 0,
    int ganancias = 0,
    int efectivo = 0,
    int cargos = 0,
  }) =>
      PendienteRider(
        repartidorId: 'r1',
        rider: 'Rider',
        envios: envios,
        ganancias: ganancias,
        efectivo: efectivo,
        cargos: cargos,
        total: ganancias - efectivo - cargos,
      );

  // Un mandado no tiene local: `comercioId` vacío (0052).
  Envio entregado(String codigo, {int ganancia = 3000, int enMano = 0}) => Envio(
        id: 'e-$codigo',
        codigo: codigo,
        comercioId: enMano == 0 ? 'c1' : '',
        comercioNombre: enMano == 0 ? 'El Local' : '',
        origen: const Direccion(calle: 'Roca 900'),
        destino: const Direccion(calle: 'San Martín 100'),
        cliente: const DatosCliente(nombre: 'Clienta', telefono: '2604555000'),
        cotizacion: Cotizacion(distanciaKm: 1.2, gananciaRepartidor: ganancia, comision: 1200),
        quienPaga: QuienPaga.cliente,
        estado: EstadoEnvio.entregado,
        creadoEn: DateTime(2026, 10, 22, 12, 0),
        entregadoEn: DateTime(2026, 10, 22, 12, 30),
        repartidorId: 'r1',
        cobrarAlEntregar: enMano,
        cobroMetodo: enMano == 0 ? null : MetodoPago.efectivo,
      );

  /// Abre la pantalla y pasa a la pestaña "Hoy".
  Future<void> abrirHoy(
    WidgetTester tester, {
    PendienteRider? hoy,
    PendienteRider? semana,
    List<Envio> envios = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionActualProvider.overrideWith((ref) async => yo),
        liquidacionesRepositoryProvider
            .overrideWith((ref) => _LiquidacionesFalso(hoy: hoy, semana: semana)),
        enviosDelRepartidorProvider.overrideWith((ref) => Stream.value(envios)),
        repartidorActualProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        theme: MyTheme.claro,
        home: const Scaffold(body: GananciasPage()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();
  }

  // El mismo importe puede estar en el cartel, en el recuadro de la semana y en
  // un renglón de los últimos viajes: lo que se mira es el cartel.
  Finder enElCartel(String texto) =>
      find.descendant(of: find.byType(MyHeroCard), matching: find.text(texto));

  group('El número de HOY', () {
    testWidgets('con dos mandados no dice que ganó: dice que tiene que rendir',
        (tester) async {
      // Dos mandados de $3.000 de ganancia que se cobran enteros en la puerta
      // ($4.500 cada uno): ganó $6.000 y junta $9.000. La liquidación da -$3.000.
      await abrirHoy(
        tester,
        hoy: resumen(envios: 2, ganancias: 6000, efectivo: 9000),
        semana: resumen(envios: 2, ganancias: 6000, efectivo: 9000),
        envios: [entregado('MY-1', enMano: 4500), entregado('MY-2', enMano: 4500)],
      );

      expect(find.text('TENÉS QUE RENDIR'), findsOneWidget);
      expect(enElCartel(r'$3.000'), findsOneWidget);
      // El número viejo: lo ganado sin descontar nada.
      expect(enElCartel(r'$6.000'), findsNothing);
      expect(find.textContaining('juntaste'), findsWidgets);
    });

    testWidgets('resta los cargos de la administración', (tester) async {
      await abrirHoy(
        tester,
        hoy: resumen(envios: 3, ganancias: 10000, cargos: 4000),
        semana: resumen(envios: 3, ganancias: 10000, cargos: 4000),
        envios: [entregado('MY-3')],
      );

      expect(enElCartel(r'$6.000'), findsOneWidget);
      expect(find.textContaining(r'cargos $4.000'), findsOneWidget);
      expect(find.text('TENÉS QUE RENDIR'), findsNothing);
      // Sin descontar el cargo serían $10.000.
      expect(enElCartel(r'$10.000'), findsNothing);
    });

    testWidgets('un día de ganancia pura no repite el número en el desglose',
        (tester) async {
      await abrirHoy(
        tester,
        hoy: resumen(envios: 1, ganancias: 3000),
        semana: resumen(envios: 1, ganancias: 3000),
        envios: [entregado('MY-4')],
      );

      expect(find.text('1 viaje entregado'), findsOneWidget);
      expect(find.textContaining('Ganaste'), findsNothing);
    });

    testWidgets('sin movimientos muestra un día en cero y no un error',
        (tester) async {
      await abrirHoy(tester);

      expect(find.text(r'$0'), findsWidgets);
      expect(find.text('No pudimos cargar esto'), findsNothing);
    });
  });

  group('La semana', () {
    testWidgets('sale de la liquidación y no de los últimos 100 envíos',
        (tester) async {
      // La semana suma $120.000, pero el stream de envíos solo trae uno.
      await abrirHoy(
        tester,
        hoy: resumen(envios: 1, ganancias: 3000),
        semana: resumen(envios: 40, ganancias: 120000),
        envios: [entregado('MY-5')],
      );

      expect(find.text(r'$120.000'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      // El rótulo dejó de prometer un recorte de los últimos 100.
      expect(find.textContaining('últimos 100'), findsNothing);
    });
  });

  group('Los últimos viajes', () {
    testWidgets('un mandado dice cuánto juntó en la puerta', (tester) async {
      await abrirHoy(
        tester,
        hoy: resumen(envios: 1, ganancias: 3000, efectivo: 4500),
        semana: resumen(envios: 1, ganancias: 3000, efectivo: 4500),
        envios: [entregado('MY-6', enMano: 4500)],
      );

      expect(find.textContaining(r'juntaste $4.500'), findsWidgets);
    });
  });
}
