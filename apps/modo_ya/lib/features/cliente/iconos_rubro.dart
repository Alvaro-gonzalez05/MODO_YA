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
