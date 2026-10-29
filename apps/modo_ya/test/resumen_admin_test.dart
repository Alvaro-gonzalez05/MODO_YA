// El resumen de la administración, sin base.
//
// Existe por un error concreto: el panel leía sus consultas con
// `.value ?? const []`, así que una consulta caída se veía igual que una sin
// datos — ceros y un cartel verde diciendo "Todo en orden". Estas pruebas
// fijan que un error se vea como error y que el "Todo en orden" solo salga
// cuando todas las consultas contestaron.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/comun/credenciales.dart';
import 'package:modo_ya/features/admin/dashboard_page.dart';

import 'soporte.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin bajar tipografias por HTTPS: dejan temporizadores pendientes al cerrar.
  GoogleFonts.config.allowRuntimeFetching = false;
  // Lo mismo que hace main(): sin esto `Formato.hora` no sabe formatear en es_AR.
  initializeDateFormatting('es_AR');

  // El Scaffold lo pone el contenedor de cada rol, no la pantalla.
  Widget app(Widget pantalla) => MaterialApp(
    theme: MyTheme.claro,
    home: Scaffold(body: pantalla),
  );

  // Las consultas del panel, vacias salvo las que se pisen. Sin tipo de
  // retorno a proposito: `Override` no sale del paquete publico de Riverpod.
  consultas({
    Stream<List<Comercio>>? comercios,
    Stream<List<Repartidor>>? riders,
    Stream<List<Envio>>? envios,
    Stream<List<Preinscripcion>>? preinscripciones,
  }) => [
    todosLosComerciosProvider.overrideWith((ref) => comercios ?? Stream.value(const [])),
    todosLosRepartidoresProvider.overrideWith((ref) => riders ?? Stream.value(const [])),
    enviosActivosProvider.overrideWith((ref) => envios ?? Stream.value(const [])),
    preinscripcionesProvider.overrideWith((ref) => preinscripciones ?? Stream.value(const [])),
  ];

  group('Cuando una consulta falla', () {
    testWidgets('se ve el error y se puede reintentar, no "Todo en orden"', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: consultas(envios: Stream.error(const ErrorModoYa('Sin conexión.'))),
          child: app(const DashboardPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar esto'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.textContaining('Todo en orden'), findsNothing);
      // Lo peor del error anterior: los numeros en cero como si fueran ciertos.
      // El rotulo del indicador va en mayusculas (MyKpi).
      expect(find.text('ENVÍOS EN LA CALLE'), findsNothing);
    });

    testWidgets('alcanza con que falle una', (tester) async {
      for (final override in [
        consultas(comercios: Stream.error(const ErrorModoYa('x'))),
        consultas(riders: Stream.error(const ErrorModoYa('x'))),
        consultas(envios: Stream.error(const ErrorModoYa('x'))),
        consultas(preinscripciones: Stream.error(const ErrorModoYa('x'))),
      ]) {
        await tester.pumpWidget(ProviderScope(overrides: override, child: app(const DashboardPage())));
        await tester.pumpAndSettle();

        expect(find.text('No pudimos cargar esto'), findsOneWidget);
      }
    });
  });

  group('Cuando todas contestan', () {
    testWidgets('sin nada pendiente dice que esta todo en orden', (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: consultas(), child: app(const DashboardPage())));
      await tester.pumpAndSettle();

      expect(find.textContaining('Todo en orden'), findsOneWidget);
      expect(find.text('No pudimos cargar esto'), findsNothing);
      expect(find.text('ENVÍOS EN LA CALLE'), findsOneWidget);
    });

    testWidgets('ya no habla de pedidos por cobrar', (tester) async {
      // Era de cuando se pagaba en efectivo: desde 0058 el cobro lo acredita
      // Mercado Pago y no hay nada que registrar a mano.
      await tester.pumpWidget(ProviderScope(overrides: consultas(), child: app(const DashboardPage())));
      await tester.pumpAndSettle();

      expect(find.text('PEDIDOS POR COBRAR'), findsNothing);
      expect(find.textContaining('sin cobrar'), findsNothing);
    });
  });

  // Antes cada tarjeta y cada aviso mandaba a otra sección, y ahí había que
  // volver a buscar de qué se hablaba. Sin GoRouter en la prueba, un
  // `context.go` revienta: si pasa, es que volvió a navegar en vez de abrir en
  // el lugar.
  group('Lo que se toca se abre en el lugar', () {
    final envio = Envio(
      id: 'e1',
      codigo: 'MY-0042',
      comercioId: 'c1',
      comercioNombre: 'Pizzería Don Luis',
      origen: const Direccion(calle: 'San Martín 100'),
      destino: const Direccion(calle: 'Rufino Ortega 455'),
      cliente: const DatosCliente(nombre: 'Ana', telefono: '2604000000'),
      cotizacion: const Cotizacion(distanciaKm: 2.3, gananciaRepartidor: 3500, comision: 700),
      quienPaga: QuienPaga.cliente,
      estado: EstadoEnvio.asignado,
      creadoEn: DateTime(2026, 10, 27, 20),
      repartidorNombre: 'Juan Pérez',
    );

    const sinUbicacion = Comercio(
      id: 'c2',
      nombre: 'Heladería del Sur',
      rubro: 'Heladería',
      direccion: Direccion(calle: 'Saturnino Torres 300'),
      telefono: '2604111222',
      aprobacion: EstadoAprobacion.aprobado,
    );

    Future<void> mostrar(WidgetTester tester, Size tamanio) async {
      enPantalla(tester, tamanio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...consultas(envios: Stream.value([envio]), comercios: Stream.value(const [sinUbicacion])),
            usuarioDeCuentaProvider.overrideWith((ref, _) async => 'heladeria.del.sur@modoya.app'),
          ],
          child: app(const DashboardPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (formato, tamanio) in anchos) {
      testWidgets('un envío en curso abre su ficha ($formato)', (tester) async {
        await sinLaAtribucionDelMapa(() async {
          await mostrar(tester, tamanio);

          final fila = find.text('MY-0042');
          await tester.ensureVisible(fila);
          await tester.pumpAndSettle();
          await tester.tap(fila);
          await tester.pumpAndSettle();

          expect(find.text('Cancelar envío'), findsOneWidget);
          expect(find.text('Juan Pérez'), findsWidgets);
        });
      });

      testWidgets('un local sin ubicación abre su ficha ($formato)', (tester) async {
        await sinLaAtribucionDelMapa(() async {
          await mostrar(tester, tamanio);

          final boton = find.widgetWithText(MyBoton, 'Ver local');
          await tester.ensureVisible(boton);
          await tester.pumpAndSettle();
          await tester.tap(boton);
          await tester.pumpAndSettle();

          expect(find.text('Suspender cuenta'), findsOneWidget);
          expect(find.text('heladeria.del.sur@modoya.app'), findsOneWidget);
        });
      });
    }

    testWidgets('una pre-inscripción de la web se ve sin salir del resumen', (tester) async {
      await sinLaAtribucionDelMapa(() async {
        enPantalla(tester, const Size(360, 800));
        await tester.pumpWidget(
          ProviderScope(
            overrides: consultas(
              preinscripciones: Stream.value([
                Preinscripcion(
                  id: 'p1',
                  tipo: TipoPreinscripcion.rider,
                  nombre: 'Lucas Gómez',
                  whatsapp: '2604999888',
                  estado: EstadoPreinscripcion.pendiente,
                  creadoEn: DateTime(2026, 10, 26),
                  datos: const {'vehiculo': 'Moto'},
                ),
              ]),
            ),
            child: app(const DashboardPage()),
          ),
        );
        await tester.pumpAndSettle();

        final boton = find.widgetWithText(MyBoton, 'Ver');
        await tester.ensureVisible(boton);
        await tester.pumpAndSettle();
        await tester.tap(boton);
        await tester.pumpAndSettle();

        expect(find.text('Lucas Gómez'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Ya lo contacté'), findsOneWidget);
      });
    });
  });
}
