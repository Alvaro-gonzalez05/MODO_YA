// Las pantallas de notificaciones, sin base: que se dibujen sin romperse y que
// digan lo que tienen que decir.
//
// Existe porque el resto de la verificacion es SQL, que prueba la base pero no
// que la pantalla arme bien el arbol de widgets. Un error de layout o un nulo
// mal manejado no lo ve ninguna prueba de la base.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/comun/notificaciones.dart';
import 'package:modo_ya/features/admin/notificaciones_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin bajar tipografias por HTTPS: dejan temporizadores pendientes al cerrar.
  GoogleFonts.config.allowRuntimeFetching = false;

  // El Scaffold no es adorno: las pantallas no lo traen (lo pone el contenedor
  // de cada rol), y sin el un Switch no encuentra su Material y explota.
  Widget app(Widget pantalla) =>
      MaterialApp(theme: MyTheme.claro, home: Scaffold(body: pantalla));

  group('Panel de notificaciones', () {
    testWidgets('muestra las dos automaticas aunque no haya ninguna escrita',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [notificacionesProvider.overrideWith((ref) => Stream.value(const []))],
        child: app(const AdminNotificacionesPage()),
      ));
      await tester.pumpAndSettle();

      // La pantalla tiene que contar que la app puede hacer esto, no solo lo
      // que ya se hizo.
      expect(find.text('Carrito abandonado'), findsOneWidget);
      expect(find.text('Cliente dormido'), findsOneWidget);
      expect(find.text('Sin escribir'), findsNWidgets(2));
      expect(find.text('Todavía no mandaste ninguna a mano'), findsOneWidget);
    });

    testWidgets('una enviada dice a cuantos llego y cuantos la abrieron',
        (tester) async {
      final enviada = Notificacion(
        id: 'n1',
        titulo: 'Hoy tenés envío gratis',
        cuerpo: 'Pedí en cualquier local adherido.',
        segmento: SegmentoNotificacion.clientes,
        enviada: true,
        alcance: 140,
        leidas: 12,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [notificacionesProvider.overrideWith((ref) => Stream.value([enviada]))],
        child: app(const AdminNotificacionesPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Enviadas'), findsOneWidget);
      expect(find.text('Hoy tenés envío gratis'), findsOneWidget);
      expect(
        find.text('Clientes · llegó a 140, la abrieron 12'),
        findsOneWidget,
      );
    });

    testWidgets('una automatica prendida muestra su interruptor y su cuenta',
        (tester) async {
      final auto = Notificacion(
        id: 'n2',
        titulo: '{nombre}, te quedó un pedido sin pagar',
        cuerpo: 'Terminá de pagarlo.',
        disparador: DisparadorNotificacion.carritoAbandonado,
        minutosEspera: 10,
        alcance: 37,
        leidas: 9,
      );

      await tester.pumpWidget(ProviderScope(
        overrides: [notificacionesProvider.overrideWith((ref) => Stream.value([auto]))],
        child: app(const AdminNotificacionesPage()),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Switch), findsOneWidget);
      expect(find.text('A los 10 min · salió 37 veces, abrieron 9'), findsOneWidget);
      // La que no esta escrita sigue ofreciendose.
      expect(find.text('Sin escribir'), findsOneWidget);
    });
  });

  group('Campanita', () {
    MiNotificacion aviso({required bool leida}) => MiNotificacion(
          envioId: 'e1',
          titulo: 'Novedad',
          cuerpo: 'Algo pasó',
          destino: DestinoNotificacion.inicio,
          leida: leida,
        );

    testWidgets('sin nada sin leer no muestra globito', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          misNotificacionesProvider.overrideWith((ref) => Stream.value([aviso(leida: true)])),
        ],
        child: app(const Center(child: MiCampanita())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsNothing);
    });

    testWidgets('cuenta las no leidas', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          misNotificacionesProvider.overrideWith(
            (ref) => Stream.value([aviso(leida: false), aviso(leida: false), aviso(leida: true)]),
          ),
        ],
        child: app(const Center(child: MiCampanita())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('con muchas corta en 9+', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          misNotificacionesProvider.overrideWith(
            (ref) => Stream.value([for (var i = 0; i < 14; i++) aviso(leida: false)]),
          ),
        ],
        child: app(const Center(child: MiCampanita())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('9+'), findsOneWidget);
    });
  });

  group('A dónde lleva cada aviso', () {
    MiNotificacion con({DestinoNotificacion? destino, String? destinoId, String? pedidoId}) =>
        MiNotificacion(
          envioId: 'e1',
          titulo: 't',
          cuerpo: 'c',
          destino: destino ?? DestinoNotificacion.ninguno,
          destinoId: destinoId,
          pedidoId: pedidoId,
        );

    test('sin destino no lleva a ningún lado', () {
      expect(con().ruta, isNull);
    });

    test('cada destino tiene su ruta', () {
      expect(con(destino: DestinoNotificacion.inicio).ruta, '/cliente');
      expect(con(destino: DestinoNotificacion.misPedidos).ruta, '/cliente/pedidos');
      expect(con(destino: DestinoNotificacion.plus).ruta, '/cliente/plus');
      expect(
        con(destino: DestinoNotificacion.local, destinoId: 'abc').ruta,
        '/cliente/local/abc',
      );
    });

    test('un local sin id no lleva a una pantalla rota', () {
      expect(con(destino: DestinoNotificacion.local).ruta, isNull);
    });

    test('el carrito abandonado manda a pagar ese pedido, por encima del destino', () {
      // Es la razon de ser del aviso: si salio porque quedo un pedido sin
      // pagar, lo unico que sirve es abrir el pago de ese pedido.
      expect(
        con(destino: DestinoNotificacion.inicio, pedidoId: 'p9').ruta,
        '/cliente/pagar/p9',
      );
    });
  });
}
