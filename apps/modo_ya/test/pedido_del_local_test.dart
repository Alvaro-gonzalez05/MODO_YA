// Lo que el local lee sobre el envío de un pedido de la app.
//
// Existe por el pedido con MODO YA Plus: el cliente no paga el envío, así que
// `costo_envio` viene en 0 y la pantalla decía "El envío ($0) lo cobra MODO
// YA". El envío vale lo que vale y en ese caso lo pone el local con su
// campaña: era un importe falso sobre un gasto propio.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/comercio/pedidos_local_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  // La hora límite del pedido nuevo se escribe con el formato de es_AR.
  initializeDateFormatting('es_AR');

  Widget app(Widget pantalla) =>
      MaterialApp(theme: MyTheme.claro, home: Scaffold(body: pantalla));

  Pedido pedido({
    required int costoEnvio,
    int envioCubierto = 0,
    EstadoPedido estado = EstadoPedido.pagado,
    DateTime? pagadoEn,
  }) =>
      Pedido(
        id: 'p1',
        codigo: 'MY-0001',
        estado: estado,
        pagadoEn: pagadoEn,
        comercioId: 'c1',
        comercioNombre: 'El Local',
        entrega: const Direccion(calle: 'San Martín 100'),
        subtotal: 10000,
        costoEnvio: costoEnvio,
        envioCubierto: envioCubierto,
        total: 10000 + costoEnvio,
        creadoEn: DateTime(2026, 10, 21, 20, 30),
      );

  Future<void> mostrar(WidgetTester tester, Pedido p) async {
    // El tablero del local son tres columnas: en los 800x600 de prueba no
    // entran y lo que se mide se pierde entre avisos de desborde.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [pedidosDelComercioProvider.overrideWith((ref) => Stream.value([p]))],
      child: app(const PedidosLocalPage()),
    ));
    await tester.pumpAndSettle();
  }

  group('El costo del envío que ve el local', () {
    testWidgets('un pedido normal: lo cobra MODO YA', (tester) async {
      await mostrar(tester, pedido(costoEnvio: 4200));

      expect(find.text('El envío (\$4.200) lo cobra MODO YA.'), findsOneWidget);
    });

    testWidgets('con Plus muestra el importe real y de quién es', (tester) async {
      // Lo que guarda `crear_pedido`: el cliente paga 0 y el importe va a
      // `envio_cubierto`, que se le descuenta al local.
      await mostrar(tester, pedido(costoEnvio: 0, envioCubierto: 4200));

      expect(find.textContaining('\$4.200'), findsWidgets);
      expect(find.textContaining('lo ponés vos con tu campaña Plus'), findsOneWidget);
      // El error de antes, textual.
      expect(find.textContaining('(\$0)'), findsNothing);
    });
  });

  group('Pedido.envioReal', () {
    test('sin Plus es lo que pagó el cliente', () {
      expect(pedido(costoEnvio: 4200).envioReal, 4200);
      expect(pedido(costoEnvio: 4200).envioLoPoneElLocal, isFalse);
    });

    test('con Plus es lo que puso el local, no cero', () {
      final p = pedido(costoEnvio: 0, envioCubierto: 4200);
      expect(p.envioReal, 4200);
      expect(p.envioLoPoneElLocal, isTrue);
    });
  });

  // El vencimiento de 0076: si el local no responde en 15 minutos, la base
  // rechaza el pedido y le cobra la penalidad. Antes nada se lo decía.
  group('Cuánto tiene el local para responder', () {
    test('cuenta desde que entró el pago, no desde que se armó el carrito', () {
      final p = pedido(costoEnvio: 4200, pagadoEn: DateTime(2026, 10, 21, 20, 40));
      expect(p.respondeAntesDe, DateTime(2026, 10, 21, 20, 55));
    });

    test('un pedido ya aceptado no vence', () {
      final p = pedido(costoEnvio: 4200, estado: EstadoPedido.aceptado, pagadoEn: DateTime(2026, 10, 21, 20, 40));
      expect(p.respondeAntesDe, isNull);
    });

    testWidgets('la tarjeta del pedido nuevo dice hasta qué hora', (tester) async {
      await mostrar(tester, pedido(costoEnvio: 4200, pagadoEn: DateTime(2026, 10, 21, 20, 40)));

      expect(find.textContaining('Respondé antes de las 20:55'), findsOneWidget);
      expect(find.textContaining('se cobra la penalidad'), findsOneWidget);
    });
  });
}
