// El inicio del local, sin base.
//
// Existe por dos cosas:
//
// - Mientras llegaba la primera lectura, los indicadores decían "0": un local
//   con tres pedidos esperando veía "0 pedidos nuevos" y no hacía nada.
// - Tocar un pedido o un envío del inicio mandaba a otra pestaña. Ahora se
//   abre encima, con sus botones.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/comercio/inicio_page.dart';
import 'package:modo_ya/features/comercio/widgets/kpi_cargando.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  final ahora = DateTime.now();

  Pedido nuevo(String id) => Pedido(
        id: id,
        codigo: 'MY-$id',
        estado: EstadoPedido.pagado,
        clienteNombre: 'Ana',
        comercioId: 'c1',
        comercioNombre: 'El Local',
        entrega: const Direccion(calle: 'San Martín 100'),
        subtotal: 12000,
        costoEnvio: 4200,
        total: 16200,
        creadoEn: ahora,
        items: const [PedidoItem(nombreProducto: 'Lomito', cantidad: 1, precioUnitario: 12000, subtotal: 12000)],
      );

  final envio = Envio(
    id: 'e1',
    codigo: 'EN-0001',
    comercioId: 'c1',
    comercioNombre: 'El Local',
    // Sin coordenadas: así la hoja no intenta bajar un mapa.
    origen: const Direccion(calle: 'Rivadavia 20'),
    destino: const Direccion(calle: 'Saturnino Torres 300'),
    cliente: const DatosCliente(nombre: 'Beto', telefono: '2604 111222'),
    cotizacion: const Cotizacion(distanciaKm: 2.4, gananciaRepartidor: 3000, comision: 700),
    quienPaga: QuienPaga.cliente,
    estado: EstadoEnvio.enCamino,
    repartidorNombre: 'Juan Rider',
    creadoEn: ahora,
  );

  Future<void> mostrar(
    WidgetTester tester, {
    required Stream<List<Pedido>> pedidos,
    Stream<List<Envio>>? envios,
    double ancho = 360,
  }) async {
    tester.view.physicalSize = Size(ancho, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionProvider.overrideWithValue(
          const Sesion(usuarioId: 'u1', rol: RolUsuario.comercio, nombre: 'El Local', comercioId: 'c1'),
        ),
        comercioActualProvider.overrideWith((ref) => Stream.value(null)),
        tarifarioProvider.overrideWith((ref) => Stream.value(null)),
        pedidosDelComercioProvider.overrideWith((ref) => pedidos),
        enviosDelComercioProvider.overrideWith((ref) => envios ?? Stream.value(const [])),
        miLiquidacionDeComercioProvider.overrideWith((ref, p) => const AsyncValue.data(null)),
        envioProvider('e1').overrideWith((ref) => Stream.value(envio)),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: InicioComercioPage())),
    ));
  }

  testWidgets('mientras cargan los pedidos no dice "0"', (tester) async {
    final pedidos = StreamController<List<Pedido>>();
    final envios = StreamController<List<Envio>>();
    addTearDown(pedidos.close);
    addTearDown(envios.close);

    await mostrar(tester, pedidos: pedidos.stream, envios: envios.stream);
    // pump y no pumpAndSettle: el indicador de carga late en bucle.
    await tester.pump();

    // Pedidos nuevos, en cocina, en la calle y entregados.
    expect(find.byType(KpiCargando), findsNWidgets(4));
    expect(find.text('0'), findsNothing);
    expect(find.text('Sin envíos hoy'), findsNothing);

    pedidos.add([nuevo('0001'), nuevo('0002')]);
    await tester.pump();
    await tester.pump();

    // Llegaron los pedidos; los envíos siguen cargando.
    expect(find.byType(KpiCargando), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('el KPI de pedidos nuevos abre la lista encima, con sus botones', (tester) async {
    await mostrar(tester, pedidos: Stream.value([nuevo('0001'), nuevo('0002')]));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('PEDIDOS NUEVOS'));
    await tester.tap(find.text('PEDIDOS NUEVOS'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // La hoja con los dos, cada uno con su "Aceptar pedido". Los del inicio
    // (sección "para aceptar") quedan debajo.
    expect(find.text('Pedidos nuevos'), findsOneWidget);
    expect(find.text('Aceptar pedido'), findsNWidgets(4));
  });

  testWidgets('con un solo pedido nuevo, el KPI va derecho al detalle', (tester) async {
    await mostrar(tester, pedidos: Stream.value([nuevo('0001')]));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('PEDIDOS NUEVOS'));
    await tester.tap(find.text('PEDIDOS NUEVOS'));
    await tester.pumpAndSettle();

    expect(find.text('Pedido MY-0001'), findsOneWidget);
  });

  testWidgets('tocar un envío de hoy abre su seguimiento en el lugar', (tester) async {
    await mostrar(tester, pedidos: Stream.value(const []), envios: Stream.value([envio]));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Saturnino Torres 300'));
    await tester.tap(find.text('Saturnino Torres 300'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Juan Rider'), findsOneWidget);
    expect(find.text('Cancelar envío'), findsNothing, reason: 'en camino ya no se puede cancelar');
    expect(find.text('Seguimiento'), findsNothing, reason: 'no navegó a la pantalla completa');
  });
}
