import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/menu_usuario.dart';

/// Contenedor de las pantallas del local: barra lateral en la PC, dock en el
/// celular. Avisa de los pedidos nuevos esté donde esté: el timbre suena en
/// loop hasta que no quede ninguno sin aceptar.
class ComercioShell extends ConsumerWidget {
  const ComercioShell({super.key, required this.navigationShell, required this.enRaiz});

  final StatefulNavigationShell navigationShell;
  final bool enRaiz;

  static const raices = {
    '/local', '/local/pedidos', '/local/campanias', '/local/menu', '/local/envios', '/local/cuenta',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se escucha acá, y no en la pantalla de pedidos, para que el aviso de un
    // pedido nuevo llegue aunque el local esté en otra pestaña.
    ref.listen(pedidosDelComercioProvider, (antes, ahora) {
      final previos = antes?.value?.where((p) => p.estado == EstadoPedido.pagado).map((p) => p.id).toSet();
      final nuevos = ahora.value?.where((p) => p.estado == EstadoPedido.pagado) ?? const [];
      if (previos == null) return;
      final recienLlegados = nuevos.where((p) => !previos.contains(p.id)).toList();
      if (recienLlegados.isEmpty) return;
      mostrarAviso(
        context,
        'Nuevo pedido ${recienLlegados.first.codigo} · ${Formato.pesos(recienLlegados.first.total)}',
        accion: 'Ver',
        onAccion: () => navigationShell.goBranch(1),
      );
    });

    final sesion = ref.watch(sesionProvider);
    final comercio = ref.watch(comercioActualProvider).value;
    final pedidos = ref.watch(pedidosDelComercioProvider).value ?? const <Pedido>[];
    final nuevos = pedidos.where((p) => p.estado == EstadoPedido.pagado).length;

    return MyAlarma(
      activa: nuevos > 0,
      sonido: MySonido.pedidoNuevo,
      child: MyAppShell(
      seccion: 'Local',
      subtitulo: comercio?.nombre ?? 'Malargüe · Mendoza',
      destinos: [
        const MyDestino(icon: Symbols.home, label: 'Inicio'),
        MyDestino(icon: Symbols.receipt_long, label: 'Pedidos', contador: nuevos),
        const MyDestino(icon: Symbols.campaign, label: 'Campañas'),
        const MyDestino(icon: Symbols.menu_book, label: 'Menú'),
        const MyDestino(icon: Symbols.sports_motorsports, label: 'Envíos'),
        const MyDestino(icon: Symbols.storefront, label: 'Mi local'),
      ],
      indice: navigationShell.currentIndex,
      onSelect: (i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex),
      usuarioNombre: comercio?.nombre ?? sesion.nombre,
      usuarioDetalle: sesion.email,
      accionesUsuario: accionesDeUsuario(context, ref),
      estado: comercio == null
          ? null
          : MyPastillaEstado(
              texto: comercio.abierto ? 'Recibiendo pedidos' : (comercio.aceptaPedidos ? 'Fuera de horario' : 'Pausado'),
              detalle: nuevos > 0 ? '$nuevos pedido${nuevos == 1 ? '' : 's'} nuevo${nuevos == 1 ? '' : 's'}' : null,
              color: comercio.abierto ? MyColors.success : MyColors.outline,
            ),
      version: versionVisible,
      mostrarDock: enRaiz,
      body: navigationShell,
      ),
    );
  }
}
