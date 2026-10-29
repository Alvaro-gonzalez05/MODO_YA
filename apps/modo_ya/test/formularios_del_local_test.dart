// Los formularios del local en el ancho de un celular (360 px), sin base.
//
// Existe porque varios estaban armados para la compu: botones al costado de
// textos largos, el botón de guardar al fondo de una lista de diez campos, y
// controladores que se liberaban mientras la hoja todavía se cerraba.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/comercio/crear_envio_page.dart';
import 'package:modo_ya/features/comercio/horarios_page.dart';
import 'package:modo_ya/features/comercio/promociones_page.dart';

class _PromocionesFalso implements PromocionesRepository {
  ({String nombre, int porcentaje, bool activa, List<int> dias})? guardada;

  @override
  Future<String> guardar({
    required String comercioId,
    required String nombre,
    required int porcentaje,
    String? id,
    AlcancePromocion alcance = AlcancePromocion.todo,
    List<int> dias = const [],
    DateTime? desde,
    DateTime? hasta,
    bool activa = true,
    List<String> secciones = const [],
    List<String> productos = const [],
  }) async {
    guardada = (nombre: nombre, porcentaje: porcentaje, activa: activa, dias: dias);
    return 'pr1';
  }

  @override
  Future<({List<String> secciones, List<String> productos})> alcanceDe(String id) async =>
      (secciones: const <String>[], productos: const <String>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  const sesion = Sesion(usuarioId: 'u1', rol: RolUsuario.comercio, nombre: 'El Local', comercioId: 'c1');

  Future<void> mostrar(WidgetTester tester, Widget pantalla, List overrides) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [sesionProvider.overrideWithValue(sesion), ...overrides.cast()],
      child: MaterialApp(theme: MyTheme.claro, home: Scaffold(body: pantalla)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('horarios: un interruptor por día y el guardar fijo abajo', (tester) async {
    await mostrar(tester, const HorariosPage(), [
      horariosProvider('c1').overrideWith((ref) => Stream.value(const [
            Horario(dia: 1, abre: '11:00', cierra: '15:00'),
            Horario(dia: 1, abre: '20:00', cierra: '01:00'),
          ])),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.byType(Switch), findsNWidgets(7));
    expect(find.text('cruza medianoche'), findsOneWidget);
    expect(tester.getRect(find.text('Guardar horarios')).bottom, greaterThan(900));

    // Prender el martes le pone un turno para empezar a editar.
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();
    expect(find.text('11:00'), findsNWidgets(2));
  });

  testWidgets('pedir un rider entra en 360 px y quién paga es un selector', (tester) async {
    await mostrar(tester, const CrearEnvioPage(), [
      comercioActualProvider.overrideWith((ref) => Stream.value(null)),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.byType(SegmentedButton<QuienPaga>), findsOneWidget);
    // Sin destino marcado el botón está y dice qué falta.
    expect(tester.getRect(find.text('Marcá el destino para cotizar')).bottom, greaterThan(900));
  });

  testWidgets('promoción: el porcentaje va con menos y más, y editar no la reactiva', (tester) async {
    final repo = _PromocionesFalso();
    final pausada = Promocion(
      id: 'pr1',
      comercioId: 'c1',
      nombre: 'Martes de pizza',
      porcentaje: 20,
      dias: const [2],
      activa: false,
    );
    await mostrar(tester, const PromocionesPage(), [
      promocionesDelComercioProvider.overrideWith((ref) => Stream.value([pausada])),
      promocionesRepositoryProvider.overrideWithValue(repo),
      menuDeComercioProvider('c1').overrideWith((ref) => Stream.value(const Menu(secciones: [], productos: []))),
    ]);
    expect(tester.takeException(), isNull);

    // Tocar la tarjeta abre la promo para editarla.
    await tester.tap(find.text('Martes de pizza'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Editar promoción'), findsOneWidget);
    // El del sello de la tarjeta y el del contador.
    expect(find.text('20%'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Más'));
    await tester.pump();
    expect(find.text('25%'), findsOneWidget);

    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    final g = repo.guardada!;
    expect(g.nombre, 'Martes de pizza');
    expect(g.porcentaje, 25);
    expect(g.dias, [2]);
    expect(g.activa, isFalse, reason: 'estaba pausada y editarla no la prende');
  });
}
