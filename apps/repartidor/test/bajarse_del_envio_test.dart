// El rider se baja de un envío que ya aceptó.
//
// La base tiene `abandonar_envio` desde la migración 0061 y al mismo tiempo le
// sacó al rider el permiso de cancelar. Pero no se llamaba desde ningún lado:
// un rider que no podía seguir se quedaba con el envío para siempre, y
// `abandonos_envio` nunca tenía una fila (así que la liquidación tampoco podía
// explicar un cargo por bajarse).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya_repartidor/features/servicio_page.dart';

/// Repositorio de prueba: anota la bajada en vez de pegarle a la base.
class _EnviosFalso implements EnviosRepository {
  String? envio;
  String? motivo;

  @override
  Future<void> abandonar(String envioId, String m) async {
    envio = envioId;
    motivo = m;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Envio envioEn(EstadoEnvio estado) => Envio(
        id: 'e1',
        codigo: 'MY-E-001',
        comercioId: 'c1',
        comercioNombre: 'El Local',
        origen: const Direccion(calle: 'Roca 900'),
        destino: const Direccion(calle: 'San Martín 100'),
        cliente: const DatosCliente(nombre: 'Clienta', telefono: '2604555000'),
        cotizacion: const Cotizacion(distanciaKm: 1.2, gananciaRepartidor: 3000, comision: 1200),
        quienPaga: QuienPaga.cliente,
        estado: estado,
        creadoEn: DateTime(2026, 10, 21, 20, 30),
        repartidorId: 'r1',
        repartidorNombre: 'Rider',
        codigoEntrega: '1234',
      );

  Future<void> abrir(WidgetTester tester, Envio envio, _EnviosFalso repo) async {
    // Con router propio: al bajarse la pantalla vuelve al inicio.
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => ServicioEnCursoPage(envioId: envio.id))],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sesionActualProvider.overrideWith((ref) async => null),
        envioProvider(envio.id).overrideWith((ref) => Stream.value(envio)),
        enviosRepositoryProvider.overrideWith((ref) => repo),
      ],
      child: MaterialApp.router(theme: MyTheme.claro, routerConfig: router),
    ));

    // Pumps a mano: el mapa del servicio nunca se queda quieto.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('Bajarse del envío', () {
    testWidgets('se ofrece antes de retirar', (tester) async {
      await abrir(tester, envioEn(EstadoEnvio.asignado), _EnviosFalso());
      expect(find.text('No puedo seguir con este envío'), findsOneWidget);

      await abrir(tester, envioEn(EstadoEnvio.enLocal), _EnviosFalso());
      expect(find.text('No puedo seguir con este envío'), findsOneWidget);
    });

    testWidgets('con el pedido encima ya no se ofrece', (tester) async {
      // `abandonar_envio` lo rechaza desde `retirado`: no tiene sentido
      // ofrecer un botón que la base va a rebotar.
      await abrir(tester, envioEn(EstadoEnvio.retirado), _EnviosFalso());
      expect(find.text('No puedo seguir con este envío'), findsNothing);

      await abrir(tester, envioEn(EstadoEnvio.enCamino), _EnviosFalso());
      expect(find.text('No puedo seguir con este envío'), findsNothing);
    });

    testWidgets('avisa del cargo y manda el motivo a la base', (tester) async {
      final repo = _EnviosFalso();
      await abrir(tester, envioEn(EstadoEnvio.asignado), repo);

      await tester.tap(find.text('No puedo seguir con este envío'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('te puede cobrar un cargo'), findsOneWidget);
      // Sin motivo escrito no se puede confirmar: es lo único que después lee
      // la administración para decidir el cargo.
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Me bajo')).onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Se me pinchó la rueda');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Me bajo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repo.envio, 'e1');
      expect(repo.motivo, 'Se me pinchó la rueda');
    });
  });
}
