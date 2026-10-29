// Las pantallas del rider en un celular angosto (360 px), sin base.
//
// Existe porque el rider usa la app en la calle, con un celular cualquiera:
// la oferta dejaba "Aceptar" debajo del borde en un teléfono bajo (había que
// bajar con el reloj corriendo) y varias filas con nombres largos desbordaban.
//
// Ojo al leer los tests: la tipografía de flutter_test dibuja cada letra como
// un cuadrado, bastante más ancha que la real. Si algo entra acá, entra de
// sobra en el teléfono.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya_repartidor/features/inicio_page.dart';
import 'package:modo_ya_repartidor/features/oferta_sheet.dart';
import 'package:modo_ya_repartidor/features/servicio_page.dart';
import 'package:modo_ya_repartidor/features/servicios_page.dart';
import 'package:modo_ya_repartidor/features/ubicacion.dart';

/// La ubicación ya "andando": así el inicio de un rider conectado no intenta
/// prender el GPS, que en un test no existe.
class _UbicacionQuieta extends UbicacionRider {
  @override
  bool get activo => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  const celular = Size(360, 640);

  // Sin coordenadas a propósito: el mapa baja mosaicos de la red.
  Envio envio(
    String id,
    EstadoEnvio estado, {
    String local = 'Rotisería La Esquina de Malargüe',
    String comercioId = 'c1',
  }) =>
      Envio(
        id: id,
        codigo: 'MY-E-00$id',
        comercioId: comercioId,
        comercioNombre: local,
        origen: const Direccion(calle: 'Avenida General Roca 900, entre Saturnino Torres y Rodríguez'),
        destino: const Direccion(calle: 'San Martín 1240, barrio Pueblo Nuevo', referencia: 'Portón verde'),
        cliente: const DatosCliente(
          nombre: 'María Fernanda Gutiérrez de la Fuente',
          telefono: '2604 555-000',
          indicaciones: 'Tocar timbre dos veces',
        ),
        cotizacion: const Cotizacion(distanciaKm: 3.4, gananciaRepartidor: 3200, comision: 1200),
        quienPaga: QuienPaga.cliente,
        estado: estado,
        creadoEn: DateTime(2026, 10, 21, 20, 30),
        repartidorId: 'r1',
        repartidorNombre: 'Rider',
        cobrarAlEntregar: 15000,
        cobroMetodo: MetodoPago.efectivo,
      );

  void pantalla(WidgetTester tester, Size tam) {
    tester.view.physicalSize = tam;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // Pumps a mano y no pumpAndSettle: el anillo de la oferta y algunos
  // indicadores nunca se quedan quietos.
  Future<void> esperar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('El servicio en curso', () {
    for (final (estado, paso) in [
      (EstadoEnvio.asignado, 'Paso 1 de 4'),
      (EstadoEnvio.enLocal, 'Paso 2 de 4'),
      (EstadoEnvio.retirado, 'Paso 3 de 4'),
      (EstadoEnvio.enCamino, 'Paso 4 de 4'),
    ]) {
      testWidgets('${estado.label}: no desborda y dice en qué paso va', (tester) async {
        pantalla(tester, celular);
        final e = envio('1', estado);
        await tester.pumpWidget(ProviderScope(
          overrides: [
            sesionActualProvider.overrideWith((ref) async => null),
            envioProvider(e.id).overrideWith((ref) => Stream.value(e)),
            // Lleva otro más: tiene que verse el aviso del segundo envío.
            enviosDelRepartidorProvider.overrideWith((ref) => Stream.value([e, envio('2', EstadoEnvio.asignado)])),
          ],
          child: MaterialApp(theme: MyTheme.claro, home: ServicioEnCursoPage(envioId: e.id)),
        ));
        await esperar(tester);

        expect(find.textContaining(paso), findsOneWidget);
        // La lista es perezosa: lo de abajo recién existe al bajar.
        await tester.scrollUntilVisible(find.textContaining('MY-E-002'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('MY-E-002'), findsOneWidget, reason: 'el otro envío que lleva');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('con el pedido encima se puede llamar al cliente de un toque', (tester) async {
      pantalla(tester, celular);
      final e = envio('1', EstadoEnvio.enCamino);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sesionActualProvider.overrideWith((ref) async => null),
          envioProvider(e.id).overrideWith((ref) => Stream.value(e)),
        ],
        child: MaterialApp(theme: MyTheme.claro, home: ServicioEnCursoPage(envioId: e.id)),
      ));
      await esperar(tester);

      await tester.scrollUntilVisible(find.byTooltip('Llamar'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.byTooltip('Llamar'), findsOneWidget);
      expect(find.text('Confirmar entrega').hitTestable(), findsOneWidget, reason: 'el botón está fijo abajo');
    });
  });

  group('La oferta', () {
    Future<void> abrirOferta(WidgetTester tester, {List<Envio> lleva = const []}) async {
      pantalla(tester, celular);
      final oferta = OfertaServicio(
        id: 'o1',
        envio: envio('9', EstadoEnvio.buscandoRepartidor, local: 'Pizzería Don Pepe'),
        distanciaAlRetiroKm: 1.2,
        expiraEn: DateTime.now().add(const Duration(minutes: 2)),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sesionActualProvider.overrideWith((ref) async => null),
          enviosDelRepartidorProvider.overrideWith((ref) => Stream.value(lleva)),
        ],
        child: MaterialApp(
          theme: MyTheme.claro,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(onPressed: () => OfertaSheet.mostrar(context, oferta), child: const Text('abrir')),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await esperar(tester);
    }

    testWidgets('en un celular bajo, Aceptar y Rechazar se ven sin bajar', (tester) async {
      await abrirOferta(tester);

      expect(find.text('Aceptar').hitTestable(), findsOneWidget);
      expect(find.text('Rechazar').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si ya lleva uno de otro local, se lo avisa', (tester) async {
      await abrirOferta(tester, lleva: [envio('1', EstadoEnvio.enCamino, local: 'Heladería Otra', comercioId: 'c2')]);

      expect(find.textContaining('Ya llevás 1 envío'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('el inicio con dos envíos encima no desborda y avisa que no llegan más ofertas', (tester) async {
    pantalla(tester, celular);
    const rider = Repartidor(
      id: 'r1',
      nombre: 'Maximiliano Rodríguez',
      telefono: '2604555111',
      vehiculo: Vehiculo.bicicleta,
      aprobacion: EstadoAprobacion.aprobado,
      conectado: true,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionActualProvider.overrideWith((ref) async => null),
        repartidorActualProvider.overrideWith((ref) => Stream.value(rider)),
        enviosDelRepartidorProvider.overrideWith(
          (ref) => Stream.value([envio('1', EstadoEnvio.retirado), envio('2', EstadoEnvio.asignado)]),
        ),
        ofertasProvider.overrideWith((ref) => Stream.value(const [])),
        miCarpetaProvider.overrideWith((ref) => const AsyncValue.loading()),
        misNotificacionesProvider.overrideWith((ref) => Stream.value(const [])),
        ubicacionRiderProvider.overrideWith(_UbicacionQuieta.new),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: InicioRepartidorPage())),
    ));
    await esperar(tester);

    expect(find.text('Llevás 2 envíos'), findsOneWidget);
    expect(find.textContaining('Salí para'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final lista = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.textContaining('Andá a retirarlo'), 200, scrollable: lista);
    await tester.scrollUntilVisible(find.textContaining('no te llegan ofertas nuevas'), 200, scrollable: lista);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en Servicios, uno entregado abre su detalle encima de la lista', (tester) async {
    pantalla(tester, celular);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionActualProvider.overrideWith((ref) async => null),
        enviosDelRepartidorProvider.overrideWith((ref) => Stream.value([envio('5', EstadoEnvio.entregado)])),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: ServiciosPage())),
    ));
    await esperar(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('MY-E-005'));
    await esperar(tester);

    expect(find.text('Ganaste'), findsOneWidget);
    expect(find.textContaining('Juntaste'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
