// La sección Pedidos de la administración, sin base.
//
// Existe porque al sacar Cobros la administración se quedó sin ninguna lista
// de pedidos: si un cliente llamaba por el suyo, no había dónde buscarlo.
// Fija que se pueda buscar por lo que dice quien llama, que la ficha abra en
// el lugar a los tres anchos y que el Resumen avise del pedido que el local no
// acepta.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/admin/dashboard_page.dart';
import 'package:modo_ya/features/admin/pedidos_page.dart';

import 'soporte.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  final ahora = DateTime.now();

  Pedido pedido(String id, EstadoPedido estado, {String? cliente, String? local, String? motivo, int minutos = 7}) => Pedido(
        id: id,
        codigo: 'MY-$id',
        estado: estado,
        // Nombres largos a propósito: es lo que desborda.
        clienteNombre: cliente ?? 'María Fernanda de los Ángeles Gutiérrez',
        clienteTelefono: '2604 555-1290',
        comercioId: 'c1',
        comercioNombre: local ?? 'Pizzería Don Luis de la Avenida San Martín',
        entrega: const Direccion(calle: 'Avenida General San Martín 1450', referencia: 'Portón verde'),
        subtotal: 1250000,
        costoEnvio: 4200,
        total: 1254200,
        creadoEn: ahora.subtract(Duration(minutes: minutos)),
        pagadoEn: estado == EstadoPedido.pendientePago ? null : ahora.subtract(Duration(minutes: minutos - 1)),
        aceptadoEn: estado.index >= EstadoPedido.aceptado.index && estado != EstadoPedido.cancelado
            ? ahora.subtract(const Duration(minutes: 3))
            : null,
        canceladoEn: estado == EstadoPedido.cancelado ? ahora : null,
        motivoCancelacion: motivo,
        metodoPago: MetodoPago.mercadoPago,
        cobrado: estado != EstadoPedido.pendientePago,
        items: const [
          PedidoItem(
            nombreProducto: 'Pizza muzzarella grande con aceitunas y morrones asados',
            cantidad: 2,
            precioUnitario: 500000,
            subtotal: 1000000,
            opciones: ['Tamaño: Grande'],
          ),
        ],
      );

  final todos = [
    pedido('0001', EstadoPedido.pagado),
    pedido('0002', EstadoPedido.enPreparacion, cliente: 'Juan Pérez', local: 'Empanadas La Abuela'),
    pedido('0003', EstadoPedido.pendientePago),
    pedido('0004', EstadoPedido.cancelado, motivo: 'Se nos cortó la luz'),
  ];

  Future<void> mostrar(WidgetTester tester, Size tamanio, Widget pantalla) async {
    enPantalla(tester, tamanio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todosLosPedidosProvider.overrideWith((ref) => Stream.value(todos)),
        enviosActivosProvider.overrideWith((ref) => Stream.value(const [])),
        todosLosComerciosProvider.overrideWith((ref) => Stream.value(const [])),
        todosLosRepartidoresProvider.overrideWith((ref) => Stream.value(const [])),
        preinscripcionesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: Scaffold(body: pantalla)),
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
      testWidgets('tocar un pedido abre su ficha con el recorrido y el cancelar', (tester) async {
        await mostrar(tester, tamanio, const AdminPedidosPage());

        // "En curso" deja afuera el que espera pago y el cancelado.
        expect(find.text('MY-0001'), findsOneWidget);
        expect(find.text('MY-0002'), findsOneWidget);
        expect(find.text('MY-0003'), findsNothing);
        expect(find.text('MY-0004'), findsNothing);

        await tocar(tester, find.text('MY-0002'));

        expect(find.text('Pedido MY-0002'), findsOneWidget);
        expect(find.text('RECORRIDO'), findsOneWidget);
        expect(find.text('El local lo aceptó'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Cancelar pedido'), findsOneWidget);
      });

      testWidgets('se busca por el teléfono o el nombre de quien llama', (tester) async {
        await mostrar(tester, tamanio, const AdminPedidosPage());

        await tester.enterText(find.byType(TextField), 'juan');
        await tester.pumpAndSettle();

        expect(find.text('MY-0002'), findsOneWidget);
        expect(find.text('MY-0001'), findsNothing);
      });

      testWidgets('un cancelado dice por qué y ya no se puede cancelar', (tester) async {
        await mostrar(tester, tamanio, const AdminPedidosPage());

        await tocar(tester, find.textContaining('Cerrados'));
        await tocar(tester, find.text('MY-0004'));

        expect(find.text('Motivo: Se nos cortó la luz'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Cancelar pedido'), findsNothing);
      });
    });
  }

  testWidgets('El resumen avisa del pedido que el local no acepta', (tester) async {
    await sinLaAtribucionDelMapa(() async {
      await mostrar(tester, const Size(1280, 900), const DashboardPage());

      // El 0001 lleva 6 minutos pago y sin aceptar.
      expect(find.textContaining('no acepta el pedido MY-0001'), findsOneWidget);
    });
  });
}
