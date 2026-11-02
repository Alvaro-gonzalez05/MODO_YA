// El interruptor que se mueve apenas se toca (stock, recibir pedidos).
//
// Fija las dos cosas que importan: que se mueva antes de que conteste la
// base, y que si guardar falla vuelva a donde estaba en vez de mentir.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_ui/my_ui.dart';

void main() {
  Future<void> mostrar(WidgetTester tester, Future<void> Function(bool) onChanged) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: MyInterruptor(valor: false, onChanged: onChanged))));

  bool prendido(WidgetTester tester) => tester.widget<Switch>(find.byType(Switch)).value;

  testWidgets('se mueve antes de que conteste la base', (tester) async {
    final respuesta = Completer<void>();
    await mostrar(tester, (_) => respuesta.future);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(prendido(tester), isTrue);

    respuesta.complete();
    await tester.pumpAndSettle();
    expect(prendido(tester), isTrue);
  });

  testWidgets('si guardar falla vuelve a donde estaba', (tester) async {
    final respuesta = Completer<void>();
    await mostrar(tester, (_) => respuesta.future);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(prendido(tester), isTrue);

    respuesta.completeError(Exception('Sin conexión'));
    await tester.pumpAndSettle();
    expect(prendido(tester), isFalse);
  });

  testWidgets('mientras guarda no manda dos veces', (tester) async {
    var llamadas = 0;
    final respuesta = Completer<void>();
    await mostrar(tester, (_) {
      llamadas++;
      return respuesta.future;
    });

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(llamadas, 1);

    respuesta.complete();
    await tester.pumpAndSettle();
  });
}
