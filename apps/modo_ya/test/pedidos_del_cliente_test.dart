// "Mis pedidos" y el seguimiento del cliente, sin base.
//
// Existe por dos cosas: tocar un pedido ya terminado llevaba a la pantalla de
// seguimiento (pensada para el mapa) solo para leer tres renglones, y a 360 px
// el seguimiento desbordaba con estados largos como "Listo, buscando rider".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/cliente/direcciones_page.dart';
import 'package:modo_ya/features/cliente/mis_pedidos_page.dart';
import 'package:modo_ya/features/cliente/pedido_seguimiento_page.dart';
import 'package:modo_ya/features/cliente/producto_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  Pedido pedido(String id, EstadoPedido estado, {List<PedidoItem> items = const []}) => Pedido(
        id: id,
        codigo: 'MY-000$id',
        estado: estado,
        comercioId: 'c1',
        comercioNombre: 'Lomitería de Malargüe con nombre largo',
        // Sin coordenadas: así no se dibuja el mapa, que baja mosaicos de red.
        entrega: const Direccion(calle: 'Avenida General San Martín 1240, barrio Centro'),
        subtotal: 12000,
        costoEnvio: 1550,
        total: 13550,
        creadoEn: DateTime(2026, 10, 21, 20, 30),
        items: items,
      );

  const items = [
    PedidoItem(nombreProducto: 'Lomo completo', cantidad: 2, precioUnitario: 6000, subtotal: 12000, opciones: ['Pan: árabe']),
  ];

  void pantalla(WidgetTester tester, Size tam) {
    tester.view.physicalSize = tam;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Mis pedidos', () {
    final enCurso = pedido('1', EstadoPedido.enPreparacion);
    final entregado = pedido('2', EstadoPedido.entregado);

    Future<void> abrir(WidgetTester tester, Size tam) async {
      pantalla(tester, tam);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          pedidosDelClienteProvider.overrideWith((ref) => Stream.value([enCurso, entregado])),
          // La lista no trae los productos: el detalle los lee aparte.
          pedidoProvider('2').overrideWith((ref) => Stream.value(pedido('2', EstadoPedido.entregado, items: items))),
          reclamosProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: MisPedidosPage())),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('en el celular, tocar uno entregado abre su detalle encima de la lista', (tester) async {
      await abrir(tester, const Size(360, 740));
      expect(tester.takeException(), isNull);

      await tester.tap(find.textContaining('MY-0002'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Pedido MY-0002'), findsNothing, reason: 'en el celular la hoja no lleva título de panel');
      expect(find.text('Lomo completo'), findsOneWidget);
      expect(find.text('¿Algo salió mal con este pedido?'), findsOneWidget);
      // La lista sigue abajo: no se navegó a otra pantalla.
      expect(find.text('Mis pedidos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en la compu, el detalle entra como panel al costado', (tester) async {
      await abrir(tester, const Size(1440, 900));

      await tester.tap(find.textContaining('MY-0002'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Pedido MY-0002'), findsOneWidget);
      expect(find.text('Lomo completo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('El seguimiento a 360 px', () {
    Future<void> abrir(WidgetTester tester, Pedido p, SeguimientoPedido? s) async {
      pantalla(tester, const Size(360, 740));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          pedidoProvider(p.id).overrideWith((ref) => Stream.value(p)),
          seguimientoDelPedidoProvider(p.id).overrideWith((ref) => Stream.value(s)),
          reclamosProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(theme: MyTheme.claro, home: Scaffold(body: PedidoSeguimientoPage(pedidoId: p.id))),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('listo y buscando rider no desborda', (tester) async {
      await abrir(tester, pedido('3', EstadoPedido.listo, items: items), null);

      expect(find.text('Listo, buscando rider'), findsOneWidget);
      expect(find.text('Pedido MY-0003'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en camino muestra el código de entrega entero', (tester) async {
      await abrir(
        tester,
        pedido('4', EstadoPedido.enCamino, items: items),
        const SeguimientoPedido(repartidorNombre: 'Juan Ignacio Fernández', codigoEntrega: '4821'),
      );

      expect(find.text('4 8 2 1'), findsOneWidget);
      expect(find.text('Decile este código al rider cuando te entregue.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un pedido entregado trae el detalle abierto', (tester) async {
      await abrir(tester, pedido('5', EstadoPedido.entregado, items: items), null);

      expect(find.text('Lomo completo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Guardar una dirección', () {
    Future<List<DatosDireccion>> abrir(WidgetTester tester) async {
      // Más ancho que un celular a propósito: lo que se prueba son los chips, y
      // con la tipografía cuadrada de los tests la atribución del mapa (que
      // dibuja flutter_map) no entra en 360 px.
      pantalla(tester, const Size(600, 900));
      final guardadas = <DatosDireccion>[];
      await tester.pumpWidget(MaterialApp(
        theme: MyTheme.claro,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FormularioDireccion(
              punto: const LatLng(-35.47, -69.58),
              onGuardar: (d) async => guardadas.add(d),
            ),
          ),
        ),
      ));
      await tester.pump();
      return guardadas;
    }

    testWidgets('el nombre se elige con chips y "Otro" pide escribirlo', (tester) async {
      final guardadas = await abrir(tester);

      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Trabajo'), findsOneWidget);
      expect(find.text('Otro'), findsOneWidget);
      expect(find.text('NOMBRE'), findsNothing, reason: 'el campo libre aparece solo con "Otro"');

      await tester.enterText(find.byType(TextFormField).first, 'Rodríguez 55');
      await tester.tap(find.text('Guardar dirección'));
      await tester.pump();
      expect(find.text('Elegí cómo guardarla'), findsOneWidget);
      expect(guardadas, isEmpty);

      await tester.tap(find.text('Otro'));
      await tester.pump();
      expect(find.text('NOMBRE'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).last, 'Casa de mi mamá');
      await tester.tap(find.text('Guardar dirección'));
      await tester.pump();

      expect(guardadas.single.alias, 'Casa de mi mamá');
      expect(guardadas.single.calle, 'Rodríguez 55');
      expect(tester.takeException(), isNull);
    });

    testWidgets('con "Trabajo" se guarda ese nombre', (tester) async {
      final guardadas = await abrir(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Saturnino Torres 300');
      await tester.tap(find.text('Trabajo'));
      await tester.pump();
      await tester.tap(find.text('Guardar dirección'));
      await tester.pump();

      expect(guardadas.single.alias, 'Trabajo');
    });
  });

  group('El producto antes de agregarlo', () {
    const producto = Producto(
      id: 'p1',
      comercioId: 'c1',
      nombre: 'Pizza muzzarella',
      precio: 8000,
      precioLista: 10000,
      descuento: 20,
      opciones: [
        OpcionProducto(
          nombre: 'Tamaño',
          obligatoria: true,
          items: [OpcionItem(id: 'a', nombre: 'Chica'), OpcionItem(id: 'b', nombre: 'Grande', precioExtra: 3000)],
        ),
        OpcionProducto(
          nombre: 'Agregados',
          tipo: TipoOpcion.multiple,
          maxSelecciones: 1,
          items: [OpcionItem(id: 'c', nombre: 'Aceitunas'), OpcionItem(id: 'd', nombre: 'Huevo')],
        ),
      ],
    );

    Future<void> abrir(WidgetTester tester) async {
      pantalla(tester, const Size(360, 740));
      await tester.pumpWidget(MaterialApp(
        theme: MyTheme.claro,
        home: const Scaffold(body: ProductoSheet(producto: producto, enVentana: true)),
      ));
      await tester.pump();
    }

    testWidgets('muestra la promoción y avisa qué grupo falta', (tester) async {
      await abrir(tester);

      expect(find.text('20% OFF'), findsOneWidget);
      expect(find.text('Obligatorio'), findsOneWidget);
      expect(find.text('Elegí Tamaño'), findsOneWidget);

      await tester.tap(find.text('Grande'));
      await tester.pump();

      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Agregar ${Formato.pesos(11000)}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el tope lleno no deja sumar otro agregado', (tester) async {
      await abrir(tester);

      expect(find.text('Elegí hasta 1 · 0 de 1'), findsOneWidget);
      await tester.tap(find.text('Aceitunas'));
      await tester.pump();
      expect(find.text('Elegí hasta 1 · 1 de 1'), findsOneWidget);

      await tester.tap(find.text('Huevo'));
      await tester.pump();
      expect(find.text('Elegí hasta 1 · 1 de 1'), findsOneWidget, reason: 'Huevo está apagado');
    });

    testWidgets('el stepper suma y el precio acompaña', (tester) async {
      await abrir(tester);

      await tester.tap(find.text('Chica'));
      await tester.tap(find.byTooltip('Uno más'));
      await tester.pump();

      expect(find.text('Agregar ${Formato.pesos(16000)}'), findsOneWidget);
    });
  });
}
