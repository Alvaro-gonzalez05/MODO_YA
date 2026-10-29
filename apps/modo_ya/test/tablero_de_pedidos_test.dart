// El tablero de pedidos del local en todos los anchos, y el detalle que se
// abre al tocar un pedido.
//
// Existe porque el tablero eran cuatro columnas fijas: en una tableta (o una
// compu angosta, con la barra lateral) cada columna quedaba en ~140 px y las
// tarjetas desbordaban. Y porque tocar un pedido desde el inicio mandaba a otra
// pestaña en vez de mostrarlo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/comercio/pedidos_local_page.dart';

/// Anota lo que se le pide en vez de pegarle a la base.
class _PedidosFalso implements PedidosRepository {
  String? aceptado;
  (String, String)? rechazado;

  @override
  Future<void> aceptar(String id) async => aceptado = id;

  @override
  Future<void> rechazar(String id, String motivo) async => rechazado = (id, motivo);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  final ahora = DateTime.now();

  Pedido pedido(String id, EstadoPedido estado, {String? nota}) => Pedido(
        id: id,
        codigo: 'MY-$id',
        estado: estado,
        // Nombres y direcciones largos a propósito: es lo que desborda.
        clienteNombre: 'María Fernanda de los Ángeles Gutiérrez',
        clienteTelefono: '2604 555-1290',
        comercioId: 'c1',
        comercioNombre: 'El Local',
        entrega: const Direccion(calle: 'Avenida General San Martín 1450', referencia: 'Portón verde al lado del kiosco'),
        subtotal: 1250000,
        costoEnvio: 4200,
        total: 1254200,
        creadoEn: ahora.subtract(const Duration(minutes: 7)),
        pagadoEn: ahora.subtract(const Duration(minutes: 6)),
        metodoPago: MetodoPago.mercadoPago,
        nota: nota,
        items: const [
          PedidoItem(
            nombreProducto: 'Pizza muzzarella grande con aceitunas y morrones asados',
            cantidad: 2,
            precioUnitario: 500000,
            subtotal: 1000000,
            opciones: ['Tamaño: Grande', 'Agregados: Extra queso, Jamón cocido'],
            nota: 'sin cebolla por favor',
          ),
          PedidoItem(nombreProducto: 'Coca-Cola 1,5 L', cantidad: 1, precioUnitario: 250000, subtotal: 250000),
        ],
      );

  final todos = [
    pedido('0001', EstadoPedido.pagado, nota: 'Tocar timbre de arriba, el de abajo no anda desde hace un mes'),
    pedido('0002', EstadoPedido.aceptado),
    pedido('0003', EstadoPedido.enPreparacion),
    pedido('0004', EstadoPedido.listo),
    pedido('0005', EstadoPedido.enCamino),
    pedido('0006', EstadoPedido.entregado),
  ];

  Future<void> mostrar(
    WidgetTester tester, {
    required double ancho,
    List<Pedido>? lista,
    PedidosRepository? repo,
  }) async {
    tester.view.physicalSize = Size(ancho, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pedidosDelComercioProvider.overrideWith((ref) => Stream.value(lista ?? todos)),
        if (repo != null) pedidosRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: PedidosLocalPage())),
    ));
    await tester.pumpAndSettle();
  }

  group('El tablero no desborda', () {
    // Un desborde de Flutter es una excepción: si alguna tarjeta no entra, el
    // test se cae solo.
    for (final ancho in [360.0, 768.0, 964.0, 1280.0]) {
      testWidgets('a $ancho px', (tester) async {
        await mostrar(tester, ancho: ancho);

        expect(tester.takeException(), isNull);
        expect(find.text('MY-0001'), findsOneWidget);
      });
    }

    testWidgets('en el celular las columnas pasan a grupos', (tester) async {
      await mostrar(tester, ancho: 360);

      // Los tres grupos de "Por atender", uno debajo del otro.
      expect(find.text('Nuevos'), findsOneWidget);
      expect(find.text('En cocina'), findsOneWidget);
      expect(find.text('Listos'), findsOneWidget);
      // Lo que está en camino va en su pestaña, no en la lista de por atender.
      expect(find.text('MY-0005'), findsNothing);

      // Los filtros se deslizan de costado: en 360 px el segundo puede quedar
      // asomando.
      await tester.ensureVisible(find.text('En camino (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('En camino (1)'));
      await tester.pumpAndSettle();
      expect(find.text('MY-0005'), findsOneWidget);
      expect(find.text('MY-0001'), findsNothing);
    });

    testWidgets('en la compu es un tablero de cuatro columnas', (tester) async {
      await mostrar(tester, ancho: 1280);

      for (final columna in ['Nuevos', 'En cocina', 'Listos', 'En camino']) {
        expect(find.text(columna), findsOneWidget);
      }
      expect(find.text('MY-0005'), findsOneWidget);
      // Los cerrados no ensucian el tablero: tienen su filtro.
      expect(find.text('MY-0006'), findsNothing);
    });

    testWidgets('el pedido nuevo sigue diciendo hasta qué hora hay para responder', (tester) async {
      await mostrar(tester, ancho: 360);

      expect(find.textContaining('Respondé antes de las'), findsOneWidget);
    });
  });

  group('Tocar un pedido abre el detalle', () {
    testWidgets('en el celular, con todo lo que pidió y sus botones', (tester) async {
      final repo = _PedidosFalso();
      await mostrar(tester, ancho: 360, lista: [todos.first], repo: repo);

      await tester.tap(find.text('MY-0001'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Pedido MY-0001'), findsOneWidget);
      expect(find.textContaining('QUÉ PIDIÓ'), findsOneWidget);
      // Las opciones van enteras en el detalle, una por renglón.
      expect(find.text('Agregados: Extra queso, Jamón cocido'), findsOneWidget);
      expect(find.text('2604 555-1290'), findsOneWidget);
      expect(find.text('Pagado con tarjeta en la app'), findsOneWidget);
      // El aviso del vencimiento está en la tarjeta y en el detalle.
      expect(find.textContaining('Respondé antes de las'), findsNWidgets(2));

      // El botón del detalle es el último (la hoja va encima de la lista).
      await tester.tap(find.text('Aceptar pedido').last);
      await tester.pumpAndSettle();
      expect(repo.aceptado, '0001');
    });

    testWidgets('rechazar avisa de la penalidad y manda el motivo', (tester) async {
      final repo = _PedidosFalso();
      await mostrar(tester, ancho: 1280, lista: [todos.first], repo: repo);

      await tester.tap(find.text('MY-0001'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rechazar').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('penalidad en la liquidación'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Nos quedamos sin muzzarella');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Rechazar').last);
      await tester.pumpAndSettle();

      expect(repo.rechazado, ('0001', 'Nos quedamos sin muzzarella'));
    });

    testWidgets('un pedido en cocina muestra el paso siguiente', (tester) async {
      await mostrar(tester, ancho: 360, lista: [todos[1]]);

      await tester.tap(find.text('MY-0002'));
      await tester.pumpAndSettle();

      expect(find.text('Empezar a preparar'), findsNWidgets(2));
      expect(find.text('Aceptar pedido'), findsNothing);
    });
  });
}
