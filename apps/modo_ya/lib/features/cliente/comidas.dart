import 'package:my_core/my_core.dart';

/// Una de las comidas de los botoncitos del home del cliente.
///
/// Son fijas (vienen de la lamina `comidas.png` de la clienta, recortada en
/// `packages/my_ui/assets/rubros/`) y no dependen de los rubros cargados en
/// la base: al tocar una se filtran los locales cuyo rubro o nombre matchea
/// alguna de sus [claves].
class Comida {
  const Comida(this.nombre, this.archivo, this.claves);

  final String nombre;
  final String archivo;
  final List<String> claves;

  String get asset => 'assets/rubros/$archivo.png';

  bool coincideCon(Comercio c, Iterable<Rubro> rubros) {
    final rubro = _normalizar(c.rubro);
    final nombre = _normalizar(c.nombre);
    if (claves.any((k) => rubro.contains(k) || nombre.contains(k))) return true;
    // El rubro cargado en el admin (por id) tambien cuenta: "Pizzeria" -> pizzas.
    if (c.rubroId != null) {
      for (final r in rubros) {
        if (r.id == c.rubroId && claves.any(_normalizar(r.nombre).contains)) return true;
      }
    }
    return false;
  }
}

/// Las 15 comidas, en el orden de la lamina.
const comidas = <Comida>[
  Comida('Hamburguesas', 'hamburguesas', ['hamburg', 'burger']),
  Comida('Pizzas', 'pizzas', ['pizz']),
  Comida('Lomos', 'lomos', ['lomo', 'sandwich', 'sanguch', 'lomiter']),
  Comida('Sushi', 'sushi', ['sushi', 'japon']),
  Comida('Empanadas', 'empanadas', ['empanada']),
  Comida('Papas fritas', 'papas_fritas', ['papas', 'fritas']),
  Comida('Pollo', 'pollo', ['pollo', 'rotiser', 'parrilla', 'asado']),
  Comida('Ensaladas', 'ensaladas', ['ensalada']),
  Comida('Postres', 'postres', ['postre', 'dulce', 'reposter', 'pasteler', 'torta']),
  Comida('Cafetería', 'cafeteria', ['cafe', 'confiter', 'panader']),
  Comida('Bebidas', 'bebidas', ['bebida', 'gaseosa', 'kiosc', 'kiosk', 'drink', 'vinoter']),
  Comida('Desayunos', 'desayunos', ['desayuno', 'merienda', 'brunch']),
  Comida('Helados', 'helados', ['helad']),
  Comida('Saludable', 'saludables', ['saludable', 'fit', 'vegetarian', 'vegan', 'natural']),
  Comida('Supermercado', 'supermercado', ['supermercado', 'almacen', 'market', 'autoservicio', 'despensa']),
];

String _normalizar(String texto) {
  const conAcento = 'áéíóúñÁÉÍÓÚÑ';
  const sinAcento = 'aeiounaeioun';
  var r = texto.toLowerCase();
  for (var i = 0; i < conAcento.length; i++) {
    r = r.replaceAll(conAcento[i], sinAcento[i]);
  }
  return r;
}
