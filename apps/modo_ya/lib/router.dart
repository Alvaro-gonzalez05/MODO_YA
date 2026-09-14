import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_core/my_core.dart';

import 'comun/cargando_page.dart';
import 'features/admin/admin_shell.dart';
import 'features/admin/alta_cuenta_page.dart';
import 'features/admin/comercios_page.dart';
import 'features/admin/dashboard_page.dart';
import 'features/admin/envios_page.dart';
import 'features/admin/pedidos_pago_page.dart';
import 'features/admin/repartidores_page.dart';
import 'features/admin/tarifas_page.dart';
import 'features/auth/cuenta_no_habilitada_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/registro_page.dart';
import 'features/cliente/carrito_page.dart';
import 'features/cliente/cliente_shell.dart';
import 'features/cliente/cuenta_cliente_page.dart';
import 'features/cliente/direcciones_page.dart';
import 'features/cliente/home_page.dart';
import 'features/cliente/local_page.dart';
import 'features/cliente/mis_pedidos_page.dart';
import 'features/cliente/pedido_seguimiento_page.dart';
import 'features/comercio/comercio_shell.dart';
import 'features/comercio/crear_envio_page.dart';
import 'features/comercio/cuenta_local_page.dart';
import 'features/comercio/historial_page.dart';
import 'features/comercio/horarios_page.dart';
import 'features/comercio/inicio_page.dart';
import 'features/comercio/menu_page.dart';
import 'features/comercio/pedidos_local_page.dart';
import 'features/comercio/producto_form_page.dart';
import 'features/comercio/seguimiento_page.dart';

/// Avisa a go_router cada vez que cambia la sesion, para que vuelva a decidir
/// a donde tiene que estar cada uno.
class _CambiosDeSesion extends ChangeNotifier {
  _CambiosDeSesion(Ref ref) {
    ref.listen(sesionActualProvider, (_, _) => notifyListeners());
  }
}

String _inicioDe(Sesion s) => switch (s.rol) {
      RolUsuario.admin => '/admin',
      RolUsuario.comercio => s.puedeOperar ? '/local' : '/no-habilitada',
      RolUsuario.cliente => '/cliente',
      // Los riders usan su propia app.
      RolUsuario.repartidor || null => '/no-habilitada',
    };

String? _prefijoDe(RolUsuario? rol) => switch (rol) {
      RolUsuario.admin => '/admin',
      RolUsuario.comercio => '/local',
      RolUsuario.cliente => '/cliente',
      _ => null,
    };

final routerProvider = Provider<GoRouter>((ref) {
  final cambios = _CambiosDeSesion(ref);
  ref.onDispose(cambios.dispose);

  return GoRouter(
    initialLocation: '/cargando',
    refreshListenable: cambios,
    redirect: (context, state) {
      final sesion = ref.read(sesionActualProvider);
      final aca = state.matchedLocation;
      final esPublica = aca == '/entrar' || aca == '/registro';

      // Todavia no se sabe quien es (o fallo la carga): pantalla de espera,
      // que ademas muestra el error con opcion de reintentar.
      if (!sesion.hasValue) return aca == '/cargando' ? null : '/cargando';

      final s = sesion.value;
      if (s == null) return esPublica ? null : '/entrar';

      final inicio = _inicioDe(s);
      if (esPublica || aca == '/cargando') return inicio;
      if (inicio == '/no-habilitada') return aca == inicio ? null : inicio;

      // Nadie entra a las pantallas de otro rol, aunque escriba la ruta.
      final prefijo = _prefijoDe(s.rol);
      if (prefijo == null || !aca.startsWith(prefijo)) return inicio;
      return null;
    },
    routes: [
      GoRoute(path: '/cargando', builder: (_, _) => const CargandoPage()),
      GoRoute(path: '/entrar', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/registro', builder: (_, _) => const RegistroPage()),
      GoRoute(path: '/no-habilitada', builder: (_, _) => const CuentaNoHabilitadaPage()),

      // ---- Cliente --------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ClienteShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/cliente', builder: (_, _) => const HomeClientePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/cliente/pedidos', builder: (_, _) => const MisPedidosPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/cliente/cuenta', builder: (_, _) => const CuentaClientePage()),
          ]),
        ],
      ),
      GoRoute(
        path: '/cliente/local/:id',
        builder: (_, st) => LocalPage(comercioId: st.pathParameters['id']!),
      ),
      GoRoute(path: '/cliente/carrito', builder: (_, _) => const CarritoPage()),
      GoRoute(path: '/cliente/direcciones', builder: (_, _) => const DireccionesPage()),
      GoRoute(
        path: '/cliente/pedido/:id',
        builder: (_, st) => PedidoSeguimientoPage(pedidoId: st.pathParameters['id']!),
      ),

      // ---- Local ----------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => ComercioShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/local', builder: (_, _) => const InicioComercioPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/local/pedidos', builder: (_, _) => const PedidosLocalPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/local/menu', builder: (_, _) => const MenuPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/local/cuenta', builder: (_, _) => const CuentaLocalPage()),
          ]),
        ],
      ),
      GoRoute(path: '/local/envio/nuevo', builder: (_, _) => const CrearEnvioPage()),
      GoRoute(
        path: '/local/envio/:id',
        builder: (_, st) => SeguimientoPage(envioId: st.pathParameters['id']!),
      ),
      GoRoute(path: '/local/historial', builder: (_, _) => const HistorialPage()),
      GoRoute(path: '/local/horarios', builder: (_, _) => const HorariosPage()),
      GoRoute(
        path: '/local/producto',
        builder: (_, st) => ProductoFormPage(producto: st.extra as Producto?),
      ),

      // ---- Administracion -------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AdminShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin', builder: (_, _) => const DashboardPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/pedidos', builder: (_, _) => const PedidosPagoPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/locales', builder: (_, _) => const AdminComerciosPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/riders', builder: (_, _) => const AdminRepartidoresPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/envios', builder: (_, _) => const AdminEnviosPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/tarifas', builder: (_, _) => const AdminTarifasPage()),
          ]),
        ],
      ),
      GoRoute(
        path: '/admin/alta/:tipo',
        builder: (_, st) => AltaCuentaPage(esLocal: st.pathParameters['tipo'] == 'local'),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('No existe la pantalla ${state.uri}')),
    ),
  );
});
