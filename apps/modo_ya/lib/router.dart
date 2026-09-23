import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_core/my_core.dart';

import 'comun/cargando_page.dart';
import 'features/admin/admin_shell.dart';
import 'features/admin/alta_cuenta_page.dart';
import 'features/admin/carteles_page.dart';
import 'features/admin/comercios_page.dart';
import 'features/admin/dashboard_page.dart';
import 'features/admin/envios_page.dart';
import 'features/admin/liquidaciones_page.dart';
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
import 'features/cliente/pago_page.dart';
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
        builder: (_, state, shell) => ClienteShell(
          navigationShell: shell,
          enRaiz: ClienteShell.raices.contains(state.uri.path),
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/cliente',
              builder: (_, _) => const HomeClientePage(),
              routes: [
                GoRoute(path: 'local/:id', builder: (_, st) => LocalPage(comercioId: st.pathParameters['id']!)),
                GoRoute(path: 'carrito', builder: (_, _) => const CarritoPage()),
                GoRoute(path: 'pagar/:id', builder: (_, st) => PagoPage(pedidoId: st.pathParameters['id']!)),
                GoRoute(path: 'direcciones', builder: (_, _) => const DireccionesPage()),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/cliente/pedidos',
              builder: (_, _) => const MisPedidosPage(),
              routes: [
                GoRoute(path: ':id', builder: (_, st) => PedidoSeguimientoPage(pedidoId: st.pathParameters['id']!)),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/cliente/cuenta', builder: (_, _) => const CuentaClientePage()),
          ]),
        ],
      ),

      // ---- Local ----------------------------------------------------------
      // Las pantallas de detalle van anidadas en su pestaña: en la PC siguen
      // con la barra lateral, y en el celular el dock se oculta.
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) => ComercioShell(
          navigationShell: shell,
          enRaiz: ComercioShell.raices.contains(state.uri.path),
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/local', builder: (_, _) => const InicioComercioPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/local/pedidos', builder: (_, _) => const PedidosLocalPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/local/menu',
              builder: (_, _) => const MenuPage(),
              routes: [
                GoRoute(path: 'producto', builder: (_, st) => ProductoFormPage(producto: st.extra as Producto?)),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/local/envios',
              builder: (_, _) => const HistorialPage(),
              routes: [
                GoRoute(path: 'nuevo', builder: (_, _) => const CrearEnvioPage()),
                GoRoute(path: ':id', builder: (_, st) => SeguimientoPage(envioId: st.pathParameters['id']!)),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/local/cuenta',
              builder: (_, _) => const CuentaLocalPage(),
              routes: [GoRoute(path: 'horarios', builder: (_, _) => const HorariosPage())],
            ),
          ]),
        ],
      ),

      // ---- Administracion -------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) => AdminShell(
          navigationShell: shell,
          enRaiz: const {'/admin', '/admin/pedidos', '/admin/liquidaciones', '/admin/locales', '/admin/riders', '/admin/envios', '/admin/tarifas', '/admin/carteles'}
              .contains(state.uri.path),
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin', builder: (_, _) => const DashboardPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/pedidos', builder: (_, _) => const PedidosPagoPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/liquidaciones', builder: (_, _) => const LiquidacionesPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin/locales',
              builder: (_, _) => const AdminComerciosPage(),
              routes: [GoRoute(path: 'nuevo', builder: (_, _) => const AltaCuentaPage(esLocal: true))],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin/riders',
              builder: (_, _) => const AdminRepartidoresPage(),
              routes: [GoRoute(path: 'nuevo', builder: (_, _) => const AltaCuentaPage(esLocal: false))],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/envios', builder: (_, _) => const AdminEnviosPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/tarifas', builder: (_, _) => const AdminTarifasPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/admin/carteles', builder: (_, _) => const AdminCartelesPage()),
          ]),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('No existe la pantalla ${state.uri}')),
    ),
  );
});
