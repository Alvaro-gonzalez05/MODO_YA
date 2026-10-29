// Ayudas para las pruebas de pantallas a distintos anchos.
//
// No termina en `_test.dart` a propósito: no es una prueba, la usan las otras.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los tres anchos en los que tiene que andar cada pantalla de la
/// administración: celular, tableta y compu.
const anchos = [('celular', Size(360, 800)), ('tableta', Size(768, 1024)), ('compu', Size(1280, 900))];

/// Pone la ventana de la prueba en [tamanio] y la deja como estaba al final.
void enPantalla(WidgetTester tester, Size tamanio) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Corre [cuerpo] dejando pasar un solo desborde: el de la atribución de
/// flutter_map ("© OpenStreetMap…") en un mapa angosto.
///
/// En las pruebas cada letra mide lo mismo que el alto de la fuente (no se
/// bajan las tipografías), así que ese renglón sale casi el doble de largo que
/// en un celular de verdad. No es nuestro y no se puede tocar desde acá; todo
/// otro desborde, incluido el de nuestras tarjetas alrededor del mapa, sigue
/// haciendo fallar la prueba.
///
/// Se restaura en un `finally` y no en `addTearDown`: el binding revisa que
/// `FlutterError.onError` haya vuelto a su lugar antes de correr los tearDown.
Future<void> sinLaAtribucionDelMapa(Future<void> Function() cuerpo) async {
  final anterior = FlutterError.onError;
  FlutterError.onError = (detalle) {
    final texto = detalle.toString();
    if (texto.contains('overflowed') && texto.contains('attribution_layer')) return;
    anterior?.call(detalle);
  };
  try {
    await cuerpo();
  } finally {
    FlutterError.onError = anterior;
  }
}
