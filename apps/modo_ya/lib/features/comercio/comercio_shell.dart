import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Contenedor de las pantallas del local, con el dock flotante.
class ComercioShell extends ConsumerWidget {
  const ComercioShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se escucha aca, y no en la pantalla de pedidos, para que el aviso de un
    // pedido nuevo llegue aunque el local este en otra pestana.
    ref.listen(pedidosDelComercioProvider, (antes, ahora) {
      final previos = antes?.value?.where((p) => p.estado == EstadoPedido.pagado).map((p) => p.id).toSet();
      final nuevos = ahora.value?.where((p) => p.estado == EstadoPedido.pagado) ?? const [];
      if (previos == null) return;
      final recienLlegados = nuevos.where((p) => !previos.contains(p.id)).toList();
      if (recienLlegados.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: MyColors.primary,
          content: Text('Nuevo pedido ${recienLlegados.first.codigo} - ${Formato.pesos(recienLlegados.first.total)}'),
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () => navigationShell.goBranch(1),
          ),
        ),
      );
    });

    return MyDockScaffold(
      items: const [
        MyDockItem(icon: Symbols.home, label: 'Inicio'),
        MyDockItem(icon: Symbols.receipt_long, label: 'Pedidos'),
        MyDockItem(icon: Symbols.menu_book, label: 'Menu'),
        MyDockItem(icon: Symbols.account_circle, label: 'Cuenta'),
      ],
      currentIndex: navigationShell.currentIndex,
      onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
      body: navigationShell,
    );
  }
}
