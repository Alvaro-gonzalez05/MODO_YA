import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/menu_usuario.dart';
import '../../comun/notificaciones.dart';
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
    // Timbre cuando un pedido pasa a "en camino": el rider sale para su casa.
    // Se escucha aca para que suene en cualquier pantalla.
    ref.listen(pedidosDelClienteProvider, (antes, ahora) {
      final previos = {for (final p in antes?.value ?? const <Pedido>[]) p.id: p.estado};
      if (antes?.value == null) return;
      final salio = (ahora.value ?? const <Pedido>[]).any(
        (p) => p.estado == EstadoPedido.enCamino && previos[p.id] != null && previos[p.id] != EstadoPedido.enCamino,
      );
      if (salio) MySonidos.tocar(MySonido.riderEnCamino);
    });

    final sesion = ref.watch(sesionProvider);
    final direccion = ref.watch(direccionActualProvider);
    final pedidos = ref.watch(pedidosDelClienteProvider).value ?? const <Pedido>[];
    final enCurso = pedidos.where((p) => !p.estado.esFinal && p.estado != EstadoPedido.carrito).toList();
    final activos = enCurso.length;

    // La barra lleva al seguimiento, asi que en el seguimiento sobra. Si hay
    // mas de uno en curso mostramos el ultimo: es el que la persona acaba de
    // hacer y del que esta pendiente.
    final ruta = GoRouterState.of(context).uri.path;
    final enSeguimiento = RegExp(r'^/cliente/pedidos/.+').hasMatch(ruta);
    final aMostrar = enCurso.isEmpty || enSeguimiento ? null : enCurso.last;

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
      // En el celular la campanita va en la cabecera del inicio; en la PC esa
      // cabecera no existe y sin esto no habria manera de ver las novedades.
      accionBarra: const MiCampanita(),
      // El pedido en curso no se pierde de vista al navegar: la barra queda
      // fija abajo y lleva al seguimiento de un toque. Va dentro de una
      // columna y no apilada, para que nunca tape el final del contenido.
      body: aMostrar == null
          ? navigationShell
          : Column(
              children: [
                Expanded(child: navigationShell),
                _BarraPedidoEnCurso(pedido: aMostrar, conDock: enRaiz),
              ],
            ),
    );
  }
}

/// Barra fija con el pedido que esta en curso, al pie de todas las pantallas
/// del cliente. Es el mismo gesto que hacen Uber Eats o PedidosYa: mientras
/// hay algo en camino, siempre hay un acceso a mano para ver por donde va.
class _BarraPedidoEnCurso extends StatelessWidget {
  const _BarraPedidoEnCurso({required this.pedido, required this.conDock});

  final Pedido pedido;

  /// En el celular el dock es una pildora que **flota encima** del contenido
  /// (MyAppShell lo arma con un Stack, no con un bottomNavigationBar). Sin
  /// dejarle su lugar, la barra queda abajo de todo y el dock la tapa.
  final bool conDock;

  @override
  Widget build(BuildContext context) {
    // Textos cortos a proposito: en la barra entra un renglon. El detalle
    // completo esta en la pantalla de seguimiento, que es a donde lleva.
    final (rotulo, icono) = switch (pedido.estado) {
      EstadoPedido.pendientePago => ('Falta pagarlo', Symbols.credit_card),
      EstadoPedido.pagado => ('Esperando al local', Symbols.hourglass_top),
      EstadoPedido.aceptado => ('Pedido aceptado', Symbols.check_circle),
      EstadoPedido.enPreparacion => ('En preparacion', Symbols.skillet),
      EstadoPedido.listo => ('Buscando rider', Symbols.search),
      EstadoPedido.enCamino => ('En camino', Symbols.sports_motorsports),
      _ => ('En curso', Symbols.receipt_long),
    };
    final minutos = pedido.minutosEstimados;

    // 68 es el alto del dock y dockOffset lo que lo separa del borde.
    const altoDelDock = 68.0 + MySpacing.dockOffset;

    return Padding(
      padding: EdgeInsets.only(bottom: conDock ? altoDelDock : 0),
      child: Material(
        color: MyColors.primary,
        child: InkWell(
          onTap: () => context.go('/cliente/pedidos/${pedido.id}'),
          child: SafeArea(
            top: false,
            bottom: !conDock,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
              child: Row(
                children: [
                  Icon(icono, size: 22, color: MyColors.onPrimary),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          rotulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MyType.labelLg.copyWith(color: MyColors.onPrimary),
                        ),
                        Text(
                          minutos == null
                              ? pedido.comercioNombre
                              : '${pedido.comercioNombre} · ~$minutos min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MyType.bodySm.copyWith(color: MyColors.onPrimary.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MySpacing.sm),
                  Icon(Symbols.chevron_right, size: 22, color: MyColors.onPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
