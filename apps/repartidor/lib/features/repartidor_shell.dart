import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// Contenedor de la app del cadete con el dock flotante.
class RepartidorShell extends StatelessWidget {
  const RepartidorShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    MyDockItem(icon: Symbols.sports_motorsports, label: 'Inicio'),
    MyDockItem(icon: Symbols.local_shipping, label: 'Servicios'),
    MyDockItem(icon: Symbols.payments, label: 'Ganancias'),
    MyDockItem(icon: Symbols.account_circle, label: 'Perfil'),
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
