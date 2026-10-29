// Las campañas del local, sin base.
//
// Existe por dos cosas: los planes iban en un GridView con proporción fija y
// en el celular la tarjeta no alcanzaba para el botón; y "Sumar fondo" era un
// texto suelto sin punto de miles, donde "50000" había que contarlo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/comercio/campanias_page.dart';

class _CampaniasFalso implements CampaniasRepository {
  ({int presupuesto, int? diario})? creada;
  int? nuevoTope;

  @override
  Future<void> crear({
    required String comercioId,
    required TipoCampania tipo,
    required int presupuesto,
    int? presupuestoDiario,
    DateTime? hasta,
  }) async =>
      creada = (presupuesto: presupuesto, diario: presupuestoDiario);

  @override
  Future<void> cambiarPresupuesto(String id, int presupuesto, {int? diario}) async => nuevoTope = presupuesto;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  final publicidad = Campania(
    id: 'k1',
    comercioId: 'c1',
    tipo: TipoCampania.publicidad,
    estado: EstadoCampania.activa,
    presupuesto: 60000,
    gastado: 15000,
    disponible: 45000,
    presupuestoDiario: 9000,
    desde: DateTime(2026, 10, 1),
  );

  Future<_CampaniasFalso> mostrar(WidgetTester tester, List<Campania> campanias) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _CampaniasFalso();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionProvider.overrideWithValue(
          const Sesion(usuarioId: 'u1', rol: RolUsuario.comercio, nombre: 'El Local', comercioId: 'c1'),
        ),
        campaniasDelComercioProvider.overrideWith((ref) => Stream.value(campanias)),
        campaniasRepositoryProvider.overrideWithValue(repo),
        rendimientoCampaniaProvider('k1').overrideWith(
          (ref) async => const RendimientoCampania(ingresos: 0, pedidos: 0, costo: 0, retorno: 0),
        ),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: CampaniasPage())),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('los planes entran en el celular, con su botón', (tester) async {
    await mostrar(tester, const []);

    expect(tester.takeException(), isNull);
    expect(find.text('Empezar'), findsNWidgets(3));
  });

  testWidgets('una publicidad nueva lee los montos con punto y dice cuánto dura', (tester) async {
    final repo = await mostrar(tester, const []);

    await tester.tap(find.text('Empezar').last);
    await tester.pumpAndSettle();

    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), '9000');
    await tester.enterText(campos.at(1), '60000');
    await tester.pump();

    expect(find.text('9.000'), findsOneWidget);
    expect(find.text('60.000'), findsOneWidget);
    expect(find.textContaining('Te alcanza para 6 días'), findsOneWidget);

    await tester.tap(find.text('Activar'));
    await tester.pumpAndSettle();
    expect(repo.creada, (presupuesto: 60000, diario: 9000));
  });

  testWidgets('sumar fondo lee "30.000" y dice en cuánto queda el tope', (tester) async {
    final repo = await mostrar(tester, [publicidad]);

    await tester.ensureVisible(find.text('Sumar fondo'));
    await tester.tap(find.text('Sumar fondo'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '30000');
    await tester.pump();
    expect(find.text('30.000'), findsOneWidget);
    expect(find.text('El tope pasa a \$90.000.'), findsOneWidget);

    await tester.tap(find.text('Sumar'));
    await tester.pumpAndSettle();
    expect(repo.nuevoTope, 90000);
  });
}
