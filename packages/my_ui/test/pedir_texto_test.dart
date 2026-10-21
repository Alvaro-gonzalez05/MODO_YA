// El diálogo que pide un motivo (cancelar un envío, rechazar un pedido, que un
// rider se baje).
//
// Existe por el mismo error que tenía el código de entrega: el botón de
// confirmar se veía habilitado con el campo vacío y al tocarlo no pasaba nada.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_ui/my_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<String?> abrir(WidgetTester tester, {String? ayuda}) async {
    String? elegido;
    var abierto = false;

    await tester.pumpWidget(MaterialApp(
      theme: MyTheme.claro,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                abierto = true;
                elegido = await pedirTexto(
                  context,
                  titulo: 'Cancelar el envío',
                  label: 'Motivo',
                  aceptar: 'Cancelar envío',
                  ayuda: ayuda,
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(abierto, isTrue);
    return elegido;
  }

  VoidCallback? boton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Cancelar envío')).onPressed;

  testWidgets('con el campo vacío no se puede confirmar', (tester) async {
    await abrir(tester);

    expect(boton(tester), isNull);

    // Espacios no cuentan: el motivo se guarda y tiene que decir algo.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(boton(tester), isNull);

    await tester.enterText(find.byType(TextField), 'Se cayó el pedido');
    await tester.pump();
    expect(boton(tester), isNotNull);
  });

  testWidgets('la ayuda avisa la consecuencia antes de confirmar', (tester) async {
    await abrir(tester, ayuda: 'Te puede quedar un cargo.');

    expect(find.text('Te puede quedar un cargo.'), findsOneWidget);
  });
}
