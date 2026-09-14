import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_ui/my_ui.dart';

/// El aviso contra un servidor HTTP local que sirve un ultima.json, como el
/// que publica el workflow. No instala nada: solo que aparezca (o no) el aviso.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter test bloquea la red por defecto; aca hace falta localhost.
  HttpOverrides.global = null;
  // Lo que se prueba es el aviso, no la tipografia: sin bajar fuentes por HTTPS
  // (dejan temporizadores de socket pendientes al cerrar el test).
  GoogleFonts.config.allowRuntimeFetching = false;

  late HttpServer servidor;
  late Map<String, dynamic> manifiesto;

  setUp(() async {
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor.listen((pedido) {
      pedido.response.headers.contentType = ContentType.json;
      pedido.response.write(jsonEncode(manifiesto));
      pedido.response.close();
    });
  });

  tearDown(() => servidor.close(force: true));

  String url() => 'http://127.0.0.1:${servidor.port}/ultima.json';

  Future<void> montar(WidgetTester tester, {required String version}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyAvisoActualizacion(
          app: 'modo_ya',
          versionActual: version,
          urlManifiesto: url(),
          child: const Scaffold(body: Text('app')),
        ),
      ),
    );
    // El aviso espera 4 s (reloj falso del test) y despues hace un pedido
    // HTTP real, que necesita el reloj de verdad para completarse.
    await tester.pump(const Duration(seconds: 5));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }
  }

  /// google_fonts baja las fuentes por HTTPS: se deja terminar antes de cerrar
  /// el test, si no quedan temporizadores del socket pendientes.
  Future<void> terminar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }
  }

  Map<String, dynamic> version(String v, {bool obligatoria = false}) => {
        'version': v,
        'notas': 'Mejoras en el panel',
        'obligatoria': obligatoria,
        'archivos': {
          'modo_ya-windows': 'http://127.0.0.1/MODO_YA-Windows-Setup.exe',
          'modo_ya-android-arm64': 'http://127.0.0.1/MODO_YA-Android.apk',
          'modo_ya-android-arm32': 'http://127.0.0.1/MODO_YA-Android-32bits.apk',
        },
      };

  testWidgets('con una versión más nueva aparece el aviso', (tester) async {
    manifiesto = version('1.2.0');
    await montar(tester, version: '1.1.0');
    expect(find.text('Hay una versión nueva'), findsOneWidget);
    expect(find.text('Mejoras en el panel'), findsOneWidget);
    expect(find.text('Más tarde'), findsOneWidget);

    await tester.tap(find.text('Más tarde'));
    await tester.pump();
    expect(find.text('Hay una versión nueva'), findsNothing);
    await terminar(tester);
  });

  testWidgets('con la misma versión no aparece nada', (tester) async {
    manifiesto = version('1.1.0');
    await montar(tester, version: '1.1.0');
    expect(find.text('Hay una versión nueva'), findsNothing);
    await terminar(tester);
  });

  testWidgets('obligatoria: no se puede descartar', (tester) async {
    manifiesto = version('2.0.0', obligatoria: true);
    await montar(tester, version: '1.1.0');
    expect(find.text('Tenés que actualizar'), findsOneWidget);
    expect(find.text('Más tarde'), findsNothing);
    await terminar(tester);
  });

  testWidgets('sin versión instalada (desarrollo) no consulta', (tester) async {
    manifiesto = version('9.0.0');
    await montar(tester, version: '');
    expect(find.text('Hay una versión nueva'), findsNothing);
    await terminar(tester);
  });
}
