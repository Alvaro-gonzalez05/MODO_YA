import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/menu_usuario.dart';
import 'carrito.dart';
import 'cuenta_cliente_page.dart';

/// Contenedor del cliente: barra lateral en la PC, dock en el celular. Las
/// pantallas de detalle (local, carrito, seguimiento) esconden el dock.
class ClienteShell extends ConsumerWidget {
  const ClienteShell({super.key, required this.navigationShell, required this.enRaiz});

  final StatefulNavigationShell navigationShell;
  final bool enRaiz;

  static const raices = {'/cliente', '/cliente/pedidos', '/cliente/cuenta'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    final direccion = ref.watch(direccionActualProvider);
    final activos = ref.watch(pedidosDelClienteProvider).value?.where((p) => !p.estado.esFinal).length ?? 0;

    return MyAppShell(
      seccion: 'Delivery',
      destinos: [
        const MyDestino(icon: Symbols.home, label: 'Inicio'),
        MyDestino(icon: Symbols.receipt_long, label: 'Mis pedidos', contador: activos),
        const MyDestino(icon: Symbols.account_circle, label: 'Mi cuenta'),
      ],
      indice: navigationShell.currentIndex,
      onSelect: (i) {
        // En el celular "Mi cuenta" es una hoja inferior, no una pantalla: la
        // informacion es poca y asi no se pierde de vista donde estaba.
        if (i == 2 && context.esMovil) {
          mostrarCuentaCliente(context, ref);
          return;
        }
        navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);
      },
      usuarioNombre: sesion.nombre,
      usuarioDetalle: sesion.email,
      accionesUsuario: accionesDeUsuario(context, ref),
      estado: MyPastillaEstado(
        texto: direccion == null ? 'Sin dirección de entrega' : 'Entregar en ${direccion.calle}',
        color: direccion == null ? MyColors.outline : MyColors.primary,
      ),
      version: versionVisible,
      mostrarDock: enRaiz,
      body: navigationShell,
    );
  }
}
