import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/eliminar_cuenta.dart';
import '../../comun/menu_usuario.dart';
import '../../comun/notificaciones.dart';

export '../../comun/estados_ui.dart';

/// Contenedor del panel de administración.
///
/// En la PC: barra lateral navy y barra superior con el estado de la operación
/// y el menú del usuario. En el celular: dock con Resumen, Liquidaciones,
/// Locales, Riders y "Más" (Pedidos, Envíos, Tarifas, Carteles, Notificaciones,
/// Reclamos, contraseña y cerrar sesión).
///
/// No hay sección de cobros: desde 0058 en la app se paga solo con tarjeta y
/// el cobro lo acredita Mercado Pago, sin que nadie lo registre a mano. Lo que
/// queda de esa época, los avisos de Mercado Pago, se mira desde Liquidaciones.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.navigationShell, required this.enRaiz});

  final StatefulNavigationShell navigationShell;

  /// false en pantallas de detalle (alta de cuenta): en el celular se oculta el dock.
  final bool enRaiz;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    final riders = ref.watch(todosLosRepartidoresProvider).value ?? const <Repartidor>[];
    final conectados = riders.where((r) => r.conectado).length;
    // Un reclamo sin resolver o un documento sin revisar es gente esperando una
    // respuesta: van con contador para que no queden olvidados.
    final reclamos = ref.watch(reclamosSinResolverProvider);
    final documentos = ref.watch(documentosSinRevisarProvider);

    return MyAppShell(
      seccion: 'Admin',
      // El orden tiene que ser el mismo que el de las ramas en router.dart:
      // el índice de cada destino es el de su rama.
      destinos: [
        const MyDestino(icon: Symbols.space_dashboard, label: 'Resumen'),
        const MyDestino(icon: Symbols.account_balance_wallet, label: 'Liquidaciones'),
        const MyDestino(icon: Symbols.storefront, label: 'Locales'),
        MyDestino(icon: Symbols.sports_motorsports, label: 'Riders', contador: documentos),
        // Antes de Envíos y no en el dock: en el celular el dock se queda como
        // estaba y Pedidos entra en "Más", junto a Envíos.
        const MyDestino(icon: Symbols.receipt_long, label: 'Pedidos'),
        const MyDestino(icon: Symbols.route, label: 'Envíos'),
        const MyDestino(icon: Symbols.tune, label: 'Tarifas y reglas'),
        const MyDestino(icon: Symbols.campaign, label: 'Carteles'),
        const MyDestino(icon: Symbols.notifications, label: 'Notificaciones'),
        MyDestino(icon: Symbols.support_agent, label: 'Reclamos', contador: reclamos),
      ],
      indice: navigationShell.currentIndex,
      onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
      usuarioNombre: sesion.nombre,
      usuarioDetalle: 'Administración',
      accionesUsuario: [
        MyAccionUsuario(
          icon: Symbols.person_remove,
          label: 'Dar de baja a un cliente',
          onTap: () => darDeBajaCliente(context, ref),
        ),
        ...accionesDeUsuario(context, ref),
      ],
      estado: MyPastillaEstado(
        texto: 'Servicio operativo',
        detalle: conectados == 1 ? '1 rider conectado' : '$conectados riders conectados',
        color: conectados > 0 ? MyColors.success : MyColors.outline,
      ),
      version: versionVisible,
      mostrarDock: enRaiz,
      accionBarra: const MiCampanita(),
      body: navigationShell,
    );
  }
}
