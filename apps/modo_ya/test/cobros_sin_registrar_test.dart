// La pantalla de cobros de la administración, sin base.
//
// Quedó como antes de que en la app se pagara solo con tarjeta (0058): el
// diálogo ofrecía `MetodoPago.values` entero, con efectivo y transferencia
// adentro. Elegir efectivo no es un dato administrativo: el trigger
// `copiar_cobro_del_pedido` le pone al envío `cobrar_al_entregar = total` y el
// rider sale a cobrar en la puerta algo que el cliente quizá ya pagó.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/admin/pedidos_pago_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Pedido pedido({MetodoPago? metodo}) => Pedido(
        id: 'p1',
        codigo: 'MY-0009',
        estado: EstadoPedido.aceptado,
        clienteNombre: 'Clienta',
        clienteTelefono: '2604555000',
        comercioId: 'c1',
        comercioNombre: 'El Local',
        entrega: const Direccion(calle: 'San Martín 100'),
        subtotal: 10000,
        costoEnvio: 4200,
        total: 14200,
        metodoPago: metodo,
        creadoEn: DateTime(2026, 10, 21, 20, 30),
      );

  Future<void> mostrar(WidgetTester tester, List<Pedido> lista) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pedidosPendientesDePagoProvider.overrideWith((ref) => Stream.value(lista)),
      ],
      child: MaterialApp(
        theme: MyTheme.claro,
        home: const Scaffold(body: PedidosPagoPage()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('Qué dice la pantalla', () {
    testWidgets('sin nada, explica que el cobro con tarjeta entra solo',
        (tester) async {
      await mostrar(tester, const []);

      expect(find.text('Nada sin registrar'), findsOneWidget);
      // El texto de antes invitaba justamente a lo que no hay que hacer.
      expect(find.textContaining('Cada pedido nuevo aparece acá'), findsNothing);
    });
  });

  group('Con qué se puede registrar un cobro', () {
    testWidgets('solo lo que eligió el cliente y "Otro"', (tester) async {
      await mostrar(tester, [pedido(metodo: MetodoPago.mercadoPago)]);

      await tester.tap(find.widgetWithText(MyBoton, 'Cobrado').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('lo que eligió el cliente'), findsOneWidget);
      expect(find.textContaining('Otro'), findsOneWidget);
      // Los dos que sacó 0058: ofrecerlos acá le hace cobrar al rider en la
      // puerta un pedido que ya se pagó con tarjeta.
      expect(find.text('Efectivo'), findsNothing);
      expect(find.text('Transferencia'), findsNothing);
    });

    testWidgets('sin método elegido queda solo "Otro"', (tester) async {
      await mostrar(tester, [pedido()]);

      await tester.tap(find.widgetWithText(MyBoton, 'Cobrado').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Otro'), findsOneWidget);
      expect(find.textContaining('lo que eligió el cliente'), findsNothing);
    });
  });
}
