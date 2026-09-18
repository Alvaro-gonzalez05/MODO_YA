import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Contenedor de la app del cadete con el dock flotante.
///
/// Mientras tenga una oferta abierta suena en loop, en cualquier pestaña,
/// hasta que la acepta, la rechaza o vence.
class RepartidorShell extends ConsumerWidget {
  const RepartidorShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _items = [
    MyDockItem(icon: Symbols.sports_motorsports, label: 'Inicio'),
    MyDockItem(icon: Symbols.local_shipping, label: 'Servicios'),
    MyDockItem(icon: Symbols.payments, label: 'Ganancias'),
    MyDockItem(icon: Symbols.account_circle, label: 'Perfil'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hayOferta = ref.watch(ofertasProvider).value?.isNotEmpty ?? false;

    return MyAlarma(
      activa: hayOferta,
      sonido: MySonido.ofertaRider,
      child: MyDockScaffold(
        items: _items,
        currentIndex: navigationShell.currentIndex,
        onSelect: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        body: navigationShell,
      ),
    );
  }
}
