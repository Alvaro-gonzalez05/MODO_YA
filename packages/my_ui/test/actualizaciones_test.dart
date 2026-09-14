import 'package:flutter_test/flutter_test.dart';
import 'package:my_ui/my_ui.dart';

void main() {
  group('compararVersiones', () {
    test('ordena por mayor, menor y parche', () {
      expect(compararVersiones('1.1.0', '1.0.9'), greaterThan(0));
      expect(compararVersiones('1.10.0', '1.9.0'), greaterThan(0), reason: 'no compara como texto');
      expect(compararVersiones('2.0.0', '1.99.99'), greaterThan(0));
      expect(compararVersiones('1.0.0', '1.0.1'), lessThan(0));
    });

    test('iguales aunque tengan v, build o falten partes', () {
      expect(compararVersiones('v1.2.0', '1.2.0'), 0);
      expect(compararVersiones('1.2.0+10200', '1.2.0'), 0);
      expect(compararVersiones('1.2', '1.2.0'), 0);
    });
  });

  test('lee ultima.json como lo escribe el workflow', () {
    final v = VersionPublicada.desdeJson({
      'version': '1.2.0',
      'fecha': '2026-09-14T10:00:00Z',
      'notas': '  Pedidos con propina  ',
      'obligatoria': true,
      'archivos': {
        'modo_ya-windows': 'https://x/MODO_YA-Windows-Setup.exe',
        'rider-android-arm64': 'https://x/MODO_YA-Rider-Android.apk',
      },
    });
    expect(v.version, '1.2.0');
    expect(v.notas, 'Pedidos con propina');
    expect(v.obligatoria, isTrue);
    expect(v.archivos['modo_ya-windows'], endsWith('Setup.exe'));
    expect(v.archivos['modo_ya-android-arm64'], isNull);
  });

  test('un json incompleto no rompe', () {
    final v = VersionPublicada.desdeJson({'version': '1.0.0'});
    expect(v.obligatoria, isFalse);
    expect(v.archivos, isEmpty);
    expect(v.notas, isEmpty);
  });
}
