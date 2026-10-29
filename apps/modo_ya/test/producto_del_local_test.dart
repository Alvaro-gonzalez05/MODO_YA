// El formulario de un producto del menú, sin base.
//
// Existe porque el editor de opciones era confuso (dos campos sin rótulo y no
// se sabía qué era el precio) y porque los precios se escriben con punto de
// miles: "8.200" tiene que llegar como 8200, no como 8,2 ni como 82.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/comercio/producto_form_page.dart';

/// Anota lo que se le manda a guardar.
class _CatalogoFalso implements CatalogoRepository {
  int? precio;
  String? nombre;
  List<OpcionProducto>? opciones;

  @override
  Future<String> guardarProducto({
    required String comercioId,
    required String nombre,
    required int precio,
    String? id,
    String? seccionId,
    String? descripcion,
    bool disponible = true,
    List<OpcionProducto> opciones = const [],
    Uint8List? foto,
    String fotoExtension = 'jpg',
  }) async {
    this.nombre = nombre;
    this.precio = precio;
    this.opciones = opciones;
    return 'p1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  Future<_CatalogoFalso> abrir(WidgetTester tester, {double ancho = 360}) async {
    tester.view.physicalSize = Size(ancho, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _CatalogoFalso();
    final router = GoRouter(
      initialLocation: '/local/menu/producto',
      routes: [
        GoRoute(
          path: '/local/menu',
          builder: (_, _) => const Scaffold(body: Text('El menú')),
          routes: [GoRoute(path: 'producto', builder: (_, _) => const Scaffold(body: ProductoFormPage()))],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionProvider.overrideWithValue(
          const Sesion(usuarioId: 'u1', rol: RolUsuario.comercio, nombre: 'El Local', comercioId: 'c1'),
        ),
        menuDeComercioProvider('c1').overrideWith((ref) => Stream.value(const Menu(secciones: [], productos: []))),
        catalogoRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(theme: MyTheme.claro, routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Finder campo(String rotulo) =>
      find.descendant(of: find.widgetWithText(MyCampo, rotulo.toUpperCase()), matching: find.byType(TextField));

  Future<void> escribir(WidgetTester tester, Finder donde, String texto) async {
    await tester.ensureVisible(donde);
    await tester.enterText(donde, texto);
    await tester.pump();
  }

  testWidgets('en el celular entra en 360 px y el botón queda fijo abajo', (tester) async {
    await abrir(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Lo básico'), findsOneWidget);
    expect(find.text('Precio y sección'), findsOneWidget);
    expect(find.text('Disponibilidad'), findsOneWidget);
    expect(find.text('Opciones para elegir'), findsOneWidget);
    // El botón está a la vista sin bajar: abajo de todo de la pantalla.
    final boton = tester.getRect(find.text('Agregar al menú'));
    expect(boton.bottom, greaterThan(1500));
  });

  testWidgets('lee el precio y el extra de una opción con punto de miles', (tester) async {
    final repo = await abrir(tester);

    await escribir(tester, campo('Nombre'), 'Pizza muzzarella');
    await escribir(tester, campo('Precio'), '8200');
    // Se ve con el punto mientras se escribe.
    expect(find.text('8.200'), findsOneWidget);

    await tester.ensureVisible(find.text('Agregar opciones'));
    await tester.tap(find.text('Agregar opciones'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await escribir(tester, find.widgetWithText(TextFormField, 'Ej: Tamaño, Gustos, Agregados'), 'Tamaño');
    await escribir(tester, find.widgetWithText(TextFormField, 'Ej: Chica'), 'Chica');
    await escribir(tester, find.widgetWithText(TextFormField, 'Ej: Grande'), 'Grande');
    await escribir(tester, find.widgetWithText(TextFormField, '0').last, '1500');

    // La vista previa le dice cómo le va a quedar al cliente.
    expect(find.textContaining('Grande (+\$1.500)'), findsOneWidget);

    await tester.tap(find.text('Agregar al menú'));
    await tester.pumpAndSettle();

    expect(repo.nombre, 'Pizza muzzarella');
    expect(repo.precio, 8200);
    final grupo = repo.opciones!.single;
    expect(grupo.nombre, 'Tamaño');
    expect(grupo.tipo, TipoOpcion.unica);
    expect(grupo.obligatoria, isTrue);
    expect([for (final i in grupo.items) (i.nombre, i.precioExtra)], [('Chica', 0), ('Grande', 1500)]);
  });

  testWidgets('un grupo sin nombre se marca al lado del campo y no se guarda', (tester) async {
    final repo = await abrir(tester);

    await escribir(tester, campo('Nombre'), 'Empanada');
    await escribir(tester, campo('Precio'), '1200');
    await tester.ensureVisible(find.text('Agregar opciones'));
    await tester.tap(find.text('Agregar opciones'));
    await tester.pumpAndSettle();
    await escribir(tester, find.widgetWithText(TextFormField, 'Ej: Chica'), 'Carne');

    await tester.tap(find.text('Agregar al menú'));
    await tester.pumpAndSettle();

    expect(find.text('Ponele un nombre (ej: Tamaño)'), findsOneWidget);
    expect(repo.precio, isNull);
  });
}
