import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Los rubros guardan el nombre del icono como texto en la base ("local_pizza").
/// Material Symbols no permite buscar un icono por nombre en tiempo de
/// ejecucion sin incluir la fuente entera, asi que se mapean los que usamos.
IconData iconoDeRubro(String? nombre) => switch (nombre) {
      'local_pizza' => Symbols.local_pizza,
      'lunch_dining' => Symbols.lunch_dining,
      'bakery_dining' => Symbols.bakery_dining,
      'restaurant' => Symbols.restaurant,
      'outdoor_grill' => Symbols.outdoor_grill,
      'icecream' => Symbols.icecream,
      'local_cafe' => Symbols.local_cafe,
      'local_pharmacy' => Symbols.local_pharmacy,
      'storefront' => Symbols.storefront,
      'local_grocery_store' => Symbols.local_grocery_store,
      _ => Symbols.restaurant,
    };

/// Fotos de comida (recortadas en alta resolucion) para los botoncitos de
/// rubro del home del cliente. Se buscan primero por el nombre del rubro
/// ("Pizzas", "Sushi", ...) y, si no matchea nada, por el icono guardado en
/// la base -- asi un rubro nuevo cargado desde el admin con un nombre
/// reconocible ya sale con foto sin tocar código.
///
/// Devuelve `null` cuando no hay una foto para ese rubro: en ese caso el
/// botón cae al icono de Material de [iconoDeRubro].
String? imagenDeRubro({String? nombre, String? icono}) {
  final n = _normalizar(nombre ?? '');

  for (final regla in _reglasPorNombre) {
    if (regla.$1.any(n.contains)) return _asset(regla.$2);
  }

  return switch (icono) {
    'local_pizza' => _asset('pizzas'),
    'lunch_dining' => _asset('lomos'),
    'bakery_dining' => _asset('empanadas'),
    'restaurant' => _asset('hamburguesas'),
    'outdoor_grill' => _asset('pollo'),
    'icecream' => _asset('helados'),
    'local_cafe' => _asset('cafeteria'),
    'local_grocery_store' => _asset('supermercado'),
    _ => null,
  };
}

String _asset(String nombreArchivo) => 'assets/rubros/$nombreArchivo.png';

String _normalizar(String texto) {
  const conAcento = 'áéíóúñÁÉÍÓÚÑ';
  const sinAcento = 'aeiounAEIOUN';
  var resultado = texto.toLowerCase();
  for (var i = 0; i < conAcento.length; i++) {
    resultado = resultado.replaceAll(conAcento[i], sinAcento[i].toLowerCase());
  }
  return resultado;
}

/// (palabras clave, nombre del archivo en `assets/rubros/`)
const _reglasPorNombre = <(List<String>, String)>[
  (['hamburg'], 'hamburguesas'),
  (['pizza'], 'pizzas'),
  (['lomo', 'sandwich', 'sanguche'], 'lomos'),
  (['sushi'], 'sushi'),
  (['empanada'], 'empanadas'),
  (['papas', 'fritas'], 'papas_fritas'),
  (['pollo'], 'pollo'),
  (['ensalada'], 'ensaladas'),
  (['postre', 'dulce', 'reposteria'], 'postres'),
  (['cafe', 'cafeteria'], 'cafeteria'),
  (['bebida', 'gaseosa', 'kiosco', 'kiosko'], 'bebidas'),
  (['desayuno', 'merienda'], 'desayunos'),
  (['helado', 'heladeria'], 'helados'),
  (['saludable', 'fit', 'vegetarian', 'vegan'], 'saludables'),
  (['supermercado', 'almacen', 'market', 'autoservicio'], 'supermercado'),
];
