// El menú de un local, sin base.
//
// Existe por un panel que se iba con el scroll: en la compu "Tu pedido"
// estaba adentro de la misma lista que el menú, y a mitad de un menú largo no
// quedaba ningún botón para ir a pagar. En el celular, la barra flotante con
// el total es lo único que lleva al carrito, y a 360 px no puede desbordar.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/cliente/carrito.dart';
import 'package:modo_ya/features/cliente/local_page.dart';

/// El carrito arranca con lo que diga cada prueba.
class _CarritoCon extends CarritoNotifier {
  _CarritoCon(this.inicial);

  final Carrito inicial;

  @override
  Carrito build() => inicial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  const comercio = Comercio(
    id: 'c1',
    nombre: 'La Pizzería de la Esquina con un nombre bien largo',
    rubro: 'Pizzería',
    direccion: Direccion(calle: 'San Martín 100'),
    telefono: '2604000000',
    aprobacion: EstadoAprobacion.aprobado,
    abierto: true,
  );

  // Tres secciones de ocho productos: un menú que no entra en ninguna pantalla.
  final secciones = [
    for (final (i, n) in ['Pizzas', 'Empanadas', 'Bebidas'].indexed)
      SeccionMenu(id: 's$i', comercioId: 'c1', nombre: n, orden: i),
  ];
  final productos = [
    for (final s in secciones)
      for (var i = 0; i < 8; i++)
        Producto(
          id: '${s.id}-$i',
          comercioId: 'c1',
          seccionId: s.id,
          nombre: '${s.nombre} número $i',
          descripcion: 'Una descripción que ocupa un par de renglones para que la tarjeta tenga alto de verdad.',
          precio: 9500 + i * 100,
        ),
  ];
  final menu = Menu(secciones: secciones, productos: productos);

  final carrito = Carrito(
    comercio: comercio,
    items: [
      ItemCarrito(producto: productos[0], cantidad: 2),
      ItemCarrito(producto: productos[9], cantidad: 1),
    ],
  );

  Future<void> abrir(WidgetTester tester, Size pantalla, {Carrito? enElCarrito}) async {
    tester.view.physicalSize = pantalla;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        carritoProvider.overrideWith(() => _CarritoCon(enElCarrito ?? carrito)),
        comercioPorIdProvider('c1').overrideWith((ref) => Stream.value(comercio)),
        menuPublicoProvider('c1').overrideWith((ref) => Stream.value(menu)),
        // Sin dirección guardada: el envío todavía no se sabe.
        direccionesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const LocalPage(comercioId: 'c1')),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('En la compu', () {
    const compu = Size(1440, 900);

    testWidgets('el resumen del pedido sigue a la vista al bajar por el menú', (tester) async {
      await abrir(tester, compu);

      expect(find.text('Tu pedido'), findsOneWidget);
      expect(find.text('Ir a pagar').hitTestable(), findsOneWidget);
      // Productos (19.000 + 9.600) sin envío, porque no hay dirección.
      expect(find.text(Formato.pesos(28600)), findsOneWidget);

      // Hasta el último producto del menú.
      await tester.scrollUntilVisible(
        find.text('Bebidas número 7'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 500));

      // El 0 también está en el panel: se mira uno que no se pidió.
      expect(find.text('Pizzas número 1').hitTestable(), findsNothing, reason: 'el menú tiene que haber bajado');
      expect(find.text('Ir a pagar').hitTestable(), findsOneWidget, reason: 'el botón para pagar no se va con el scroll');
      expect(tester.takeException(), isNull);
    });

    testWidgets('cambiar la cantidad desde el panel actualiza el total', (tester) async {
      await abrir(tester, compu);

      await tester.tap(find.byTooltip('Uno más').first);
      // Un cuadro para que cambie el número y otro para que termine de contar.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Una pizza más: 28.600 + 9.500.
      expect(find.text(Formato.pesos(38100)), findsOneWidget);
    });

    testWidgets('con el carrito vacío lo dice en el panel', (tester) async {
      await abrir(tester, compu, enElCarrito: const Carrito());

      expect(find.textContaining('Todavía no agregaste nada'), findsOneWidget);
      expect(find.text('Ir a pagar'), findsNothing);
    });
  });

  group('En el celular', () {
    const celular = Size(360, 740);

    testWidgets('la barra con el total y "Ver pedido" está y no desborda', (tester) async {
      await abrir(tester, celular);

      expect(find.text('Ver pedido').hitTestable(), findsOneWidget);
      expect(find.text(Formato.pesos(28600)), findsOneWidget);
      expect(find.text('Sin contar el envío'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('al bajar, los chips de secciones y la barra quedan a mano', (tester) async {
      await abrir(tester, celular);

      await tester.scrollUntilVisible(
        find.text('Bebidas número 7'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Todo').hitTestable(), findsOneWidget, reason: 'los chips quedan fijos arriba');
      expect(find.text('Ver pedido').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin nada en el carrito no hay barra', (tester) async {
      await abrir(tester, celular, enElCarrito: const Carrito());

      expect(find.text('Ver pedido'), findsNothing);
    });
  });

  testWidgets('en la tableta, la barra flotante lleva al pedido', (tester) async {
    await abrir(tester, const Size(800, 1000));

    expect(find.text('Ver pedido').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
