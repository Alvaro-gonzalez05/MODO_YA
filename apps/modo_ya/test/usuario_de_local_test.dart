// Los usuarios de locales y riders pasaron de @modoya.com a @modoya.app (0074).

import 'package:flutter_test/flutter_test.dart';
import 'package:my_core/my_core.dart';

void main() {
  test('el usuario viejo se traduce al nuevo, sin importar mayúsculas', () {
    expect(AuthRepository.usuarioActual(' Pizzeria.Don.Luis@MODOYA.COM '), 'Pizzeria.Don.Luis@modoya.app');
    expect(AuthRepository.usuarioActual('rider.juan.perez@modoya.com'), 'rider.juan.perez@modoya.app');
  });

  test('un email de cliente queda como está', () {
    expect(AuthRepository.usuarioActual('ana@gmail.com'), 'ana@gmail.com');
    // Un dominio que solo termina parecido no es el nuestro.
    expect(AuthRepository.usuarioActual('ana@otromodoya.com.ar'), 'ana@otromodoya.com.ar');
  });

  test('a un usuario generado no se le ofrece recuperar por mail', () {
    expect(AuthRepository.esUsuarioGenerado('pizzeria.don.luis@modoya.app'), isTrue);
    expect(AuthRepository.esUsuarioGenerado('pizzeria.don.luis@modoya.com'), isTrue);
    expect(AuthRepository.esUsuarioGenerado('ana@gmail.com'), isFalse);
  });
}
