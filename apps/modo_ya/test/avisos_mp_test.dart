// El buzón de avisos de Mercado Pago.
//
// La tabla `mp_notificaciones` existe desde 0044 con el comentario "los mira
// la administración", pero no se referenciaba desde ningún .dart: lo que
// guardaba el webhook no lo veía nadie. Esto solo muestra lo guardado; no toca
// el pago ni el pedido.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/admin/liquidaciones_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  // Lo mismo que hace main(): sin esto `Formato.fechaHora` no sabe formatear
  // en es_AR.
  initializeDateFormatting('es_AR');

  final aviso = AvisoMercadoPago(
    id: 'a1',
    recibidoEn: DateTime(2026, 10, 13, 14, 43),
    tipo: 'order',
    accion: 'order.failed',
    recursoId: 'ORD01M4V5T0H4W92X9ZFRTMJZ1PKT',
    requestId: 'cc1d7977-df96-4056-b7ea-01af71be84f4',
    firmaValida: true,
    cuerpo: const {
      'data': {'id': 'ORD01M4V5T0H4W92X9ZFRTMJZ1PKT', 'status': 'failed', 'currency_id': 'ARS'},
    },
  );

  Future<void> abrir(WidgetTester tester, List<AvisoMercadoPago> avisos) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pendientesComerciosProvider.overrideWith((ref, _) => Stream.value(const [])),
        pendientesRidersProvider.overrideWith((ref, _) => Stream.value(const [])),
        historialLiquidacionesProvider.overrideWith((ref) => Stream.value(const [])),
        avisosMercadoPagoProvider.overrideWith((ref) => Stream.value(avisos)),
      ],
      child: MaterialApp(
        theme: MyTheme.claro,
        home: const Scaffold(body: LiquidacionesPage()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(MyBoton, 'Avisos de Mercado Pago'));
    await tester.pumpAndSettle();
  }

  // Antes colgaba de la pantalla de cobros, que salió con el pago en efectivo:
  // si se va con ella, el buzón vuelve a quedar sin pantalla.
  testWidgets('se llega desde Liquidaciones', (tester) async {
    await abrir(tester, [aviso]);

    expect(find.text('order.failed'), findsOneWidget);
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('Firma verificada'), findsOneWidget);
    expect(find.text('ORD01M4V5T0H4W92X9ZFRTMJZ1PKT'), findsOneWidget);
  });

  testWidgets('al abrirlo se ve el aviso crudo', (tester) async {
    await abrir(tester, [aviso]);

    expect(find.textContaining('currency_id'), findsNothing);

    await tester.tap(find.text('order.failed'));
    await tester.pumpAndSettle();

    expect(find.textContaining('currency_id'), findsOneWidget);
  });

  testWidgets('sin avisos lo dice y explica para qué sirve', (tester) async {
    await abrir(tester, const []);

    expect(find.text('Todavía no llegó ningún aviso'), findsOneWidget);
  });

  testWidgets('un aviso sin firma verificada se marca', (tester) async {
    await abrir(tester, [
      AvisoMercadoPago(
        id: 'a2',
        recibidoEn: DateTime(2026, 10, 13, 14, 43),
        accion: 'payment.updated',
        firmaValida: false,
        cuerpo: const {},
      ),
    ]);

    // Un aviso con firma inválida no lo mandó Mercado Pago: no hay que creerle.
    expect(find.text('Firma inválida'), findsOneWidget);
  });
}
