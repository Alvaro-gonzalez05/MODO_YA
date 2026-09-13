import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// Contenedor de las pantallas del comercio con el dock flotante.
class ComercioShell extends StatelessWidget {
  const ComercioShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    MyDockItem(icon: Symbols.home, label: 'Inicio'),
    MyDockItem(icon: Symbols.local_shipping, label: 'Envios'),
    MyDockItem(icon: Symbols.receipt_long, label: 'Historial'),
    MyDockItem(icon: Symbols.account_circle, label: 'Cuenta'),
  ];

  @override
  Widget build(BuildContext context) {
    return MyDockScaffold(
      items: _items,
      currentIndex: navigationShell.currentIndex,
      onSelect: (i) => navigationShell.goBranch(
        i,
        initialLocation: i == navigationShell.currentIndex,
      ),
      body: navigationShell,
    );
  }
}
