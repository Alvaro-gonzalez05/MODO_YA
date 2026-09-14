import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

class ClienteShell extends StatelessWidget {
  const ClienteShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return MyDockScaffold(
      items: const [
        MyDockItem(icon: Symbols.home, label: 'Inicio'),
        MyDockItem(icon: Symbols.receipt_long, label: 'Pedidos'),
        MyDockItem(icon: Symbols.account_circle, label: 'Cuenta'),
      ],
      currentIndex: navigationShell.currentIndex,
      onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
      body: navigationShell,
    );
  }
}
