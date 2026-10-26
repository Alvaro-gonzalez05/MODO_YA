// El formulario de cargos de un local, sin base.
//
// Existe por dos errores concretos:
//
// - El monto se parseaba con `int.tryParse(texto.replaceAll(RegExp(r'\D'), ''))`,
//   que borra el signo menos, y el campo era `soloNumeros` así que el `-` no se
//   podía ni tipear. Un ajuste negativo era imposible de cargar desde la
//   pantalla, aunque el esquema lo contempla desde 0035 ("Negativo: se le suma,
//   una devolución") y el formulario del rider sí lo permita. Si un local
//   reclamaba una penalidad con razón había que entrar por SQL.
//
// - El borrado de un cargo iba derecho a la tabla y lo único que lo frenaba era
//   que la pantalla escondiera el botón. La lista es un stream en vivo: si la
//   liquidación se cierra desde otro dispositivo, el botón sigue dibujado. Ahora
//   la base rebota el borrado, así que el error tiene que verse.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/admin/liquidaciones_page.dart';

/// Repositorio de prueba: anota lo que se le pide en vez de pegarle a la base.
class _LiquidacionesFalso implements LiquidacionesRepository {
  _LiquidacionesFalso({this.alBorrar});

  int? montoCargado;
  String? borrado;

  /// Lo que la base contesta al borrar, para probar el caso de la carrera.
  final Object? alBorrar;

  @override
  Future<void> agregarCargo({
    required String comercioId,
    required String concepto,
    required String detalle,
    required int monto,
    DateTime? fecha,
  }) async {
    montoCargado = monto;
  }

  @override
  Future<void> borrarCargo(String id) async {
    borrado = id;
    if (alBorrar != null) throw alBorrar!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin bajar tipografias por HTTPS: dejan temporizadores pendientes al cerrar.
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  CargoComercio cargo({String id = 'cg1', int monto = 15000, bool liquidado = false}) =>
      CargoComercio(
        id: id,
        comercioId: 'c1',
        concepto: 'ajuste',
        detalle: 'Penalidad por rechazar P-9999',
        monto: monto,
        fecha: DateTime(2026, 10, 22),
        liquidado: liquidado,
      );

  /// Abre el formulario de cargos del local `c1`.
  Future<void> abrir(
    WidgetTester tester,
    _LiquidacionesFalso repo, {
    List<CargoComercio> cargos = const [],
  }) async {
    tester.view.physicalSize = const Size(1600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        liquidacionesRepositoryProvider.overrideWith((ref) => repo),
        cargosDeComercioProvider('c1').overrideWith((ref) => Stream.value(cargos)),
      ],
      child: MaterialApp(
        theme: MyTheme.claro,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => MyBoton(
              label: 'Cargos',
              onPressed: () => mostrarCargos(context, ref, 'c1', 'El Local'),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MyBoton, 'Cargos'));
    await tester.pumpAndSettle();
  }

  group('Cargar un monto negativo', () {
    test('el signo sobrevive al parseo', () {
      expect(montoConSigno('15000'), 15000);
      expect(montoConSigno('-15000'), -15000);
      // Lo que escribe alguien copiando de la pantalla.
      expect(montoConSigno(r'-$15.000'), -15000);
      expect(montoConSigno(''), isNull);
      expect(montoConSigno('-'), isNull);
      // El signo cuenta solo adelante: atrás es un tipeo, no una devolución.
      expect(montoConSigno('15000-'), 15000);
    });

    testWidgets('se puede devolverle plata al local desde la pantalla',
        (tester) async {
      final repo = _LiquidacionesFalso();
      await abrir(tester, repo);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Plan Básico de septiembre'), 'Le devolvemos P-9999');
      await tester.enterText(find.byType(TextFormField).last, '-7000');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(MyBotonAccion, 'Agregar cargo'));
      await tester.pumpAndSettle();

      expect(repo.montoCargado, -7000);
    });

    testWidgets('el formulario dice que un negativo devuelve', (tester) async {
      await abrir(tester, _LiquidacionesFalso());

      expect(find.textContaining('negativo se lo devuelve'), findsOneWidget);
      // El rótulo de antes solo hablaba de descontar.
      expect(find.text('Monto a descontarle'), findsNothing);
    });

    testWidgets('un cargo negativo se lee como devolución en la lista',
        (tester) async {
      await abrir(tester, _LiquidacionesFalso(), cargos: [cargo(monto: -7000)]);

      expect(find.textContaining('se le devuelve'), findsOneWidget);
    });
  });

  group('Borrar un cargo', () {
    testWidgets('el ya liquidado no ofrece el botón', (tester) async {
      await abrir(tester, _LiquidacionesFalso(), cargos: [cargo(liquidado: true)]);

      expect(find.textContaining('ya liquidado'), findsOneWidget);
      expect(find.byTooltip('Borrar'), findsNothing);
    });

    testWidgets('si la base lo rebota, se ve por qué', (tester) async {
      // La carrera: la liquidación se cerró desde otro dispositivo y el evento
      // todavía no llegó, así que el botón sigue dibujado.
      final repo = _LiquidacionesFalso(
        alBorrar: const ErrorModoYa(
          'Ese cargo ya está liquidado: cargale uno negativo para devolvérselo',
          codigo: 'MY004',
        ),
      );
      await abrir(tester, repo, cargos: [cargo()]);

      await tester.tap(find.byTooltip('Borrar'));
      await tester.pumpAndSettle();

      expect(repo.borrado, 'cg1');
      // Antes el toque no hacía nada y no se entendía por qué.
      expect(find.textContaining('ya está liquidado'), findsOneWidget);
    });
  });
}
