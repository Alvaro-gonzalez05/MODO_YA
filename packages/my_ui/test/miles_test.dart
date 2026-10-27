// El punto de miles mientras se escribe un número.
//
// Existe porque en un precio de 15000 había que contar ceros: un cero de más
// en el tope de una campaña es diez veces la plata. Lo que más se rompe en un
// formateador así no es el texto sino el cursor, así que se prueba también
// dónde queda.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_ui/my_ui.dart';

TextEditingValue _escribir(String viejo, String nuevo, {int? cursor, bool negativos = false}) =>
    MilesFormatter(negativos: negativos).formatEditUpdate(
      TextEditingValue(text: viejo, selection: TextSelection.collapsed(offset: viejo.length)),
      TextEditingValue(text: nuevo, selection: TextSelection.collapsed(offset: cursor ?? nuevo.length)),
    );

void main() {
  test('formatear y leer van y vuelven', () {
    expect(MilesFormatter.formatear(0), '0');
    expect(MilesFormatter.formatear(999), '999');
    expect(MilesFormatter.formatear(1000), '1.000');
    expect(MilesFormatter.formatear(9800), '9.800');
    expect(MilesFormatter.formatear(1250000), '1.250.000');
    expect(MilesFormatter.formatear(-15000), '-15.000');
    expect(MilesFormatter.leer('1.250.000'), 1250000);
    expect(MilesFormatter.leer(r'-$15.000'), -15000);
    expect(MilesFormatter.leer(''), isNull);
    expect(MilesFormatter.leer('-'), isNull);
  });

  test('pone el punto al escribir', () {
    expect(_escribir('100', '1000').text, '1.000');
    expect(_escribir('1.000', '1.0000').text, '10.000');
    expect(_escribir('', '0015').text, '15');
  });

  test('el cursor queda al final al escribir al final', () {
    final v = _escribir('100', '1000');
    expect(v.selection.end, v.text.length);
  });

  test('escribir en el medio deja el cursor después del dígito nuevo', () {
    // "1.000" con el cursor después del 1, se escribe un 5: "15.000"
    final v = _escribir('1.000', '15.000', cursor: 2);
    expect(v.text, '15.000');
    expect(v.selection.end, 2);
  });

  test('borrar un punto borra el número de antes', () {
    // "12.345" con el cursor después del punto; backspace se come el punto.
    final v = MilesFormatter().formatEditUpdate(
      const TextEditingValue(text: '12.345', selection: TextSelection.collapsed(offset: 3)),
      const TextEditingValue(text: '12345', selection: TextSelection.collapsed(offset: 2)),
    );
    expect(v.text, '1.345');
  });

  test('borrar todo deja el campo vacío', () {
    expect(_escribir('5', '').text, '');
  });

  test('sin permiso no hay negativos, con permiso sí', () {
    expect(_escribir('', '-7000').text, '7.000');
    expect(_escribir('', '-7000', negativos: true).text, '-7.000');
    expect(_escribir('', '-', negativos: true).text, '-');
  });
}
