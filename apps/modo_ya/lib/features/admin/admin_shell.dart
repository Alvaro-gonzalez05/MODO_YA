import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/menu_usuario.dart';

export '../../comun/estados_ui.dart';

/// Contenedor del panel de administración.
///
/// En la PC: barra lateral navy y barra superior con el estado de la operación
/// y el menú del usuario. En el celular: dock con Resumen, Pedidos, Locales,
/// Riders y "Más" (Envíos, Tarifas, Carteles, contraseña y cerrar sesión).
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.navigationShell, required this.enRaiz});

  final StatefulNavigationShell navigationShell;

  /// false en pantallas de detalle (alta de cuenta): en el celular se oculta el dock.
  final bool enRaiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    final porCobrar = ref.watch(pedidosPendientesDePagoProvider).value?.length ?? 0;
    final riders = ref.watch(todosLosRepartidoresProvider).value ?? const <Repartidor>[];
    final conectados = riders.where((r) => r.conectado).length;

    return MyAppShell(
      seccion: 'Admin',
      destinos: [
        const MyDestino(icon: Symbols.space_dashboard, label: 'Resumen'),
        MyDestino(icon: Symbols.receipt_long, label: 'Pedidos', contador: porCobrar),
        const MyDestino(icon: Symbols.storefront, label: 'Locales'),
        const MyDestino(icon: Symbols.sports_motorsports, label: 'Riders'),
        const MyDestino(icon: Symbols.route, label: 'Envíos'),
        const MyDestino(icon: Symbols.tune, label: 'Tarifas y reglas'),
        const MyDestino(icon: Symbols.campaign, label: 'Carteles'),
      ],
      indice: navigationShell.currentIndex,
      onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
      usuarioNombre: sesion.nombre,
      usuarioDetalle: 'Administración',
      accionesUsuario: accionesDeUsuario(context, ref),
      estado: MyPastillaEstado(
        texto: 'Servicio operativo',
        detalle: conectados == 1 ? '1 rider conectado' : '$conectados riders conectados',
        color: conectados > 0 ? MyColors.success : MyColors.outline,
      ),
      version: versionVisible,
      mostrarDock: enRaiz,
      body: navigationShell,
    );
  }
}
