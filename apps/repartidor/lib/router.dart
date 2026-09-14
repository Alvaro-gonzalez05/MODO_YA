import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_core/my_core.dart';

import 'features/cargando_page.dart';
import 'features/ganancias_page.dart';
import 'features/inicio_page.dart';
import 'features/login_page.dart';
import 'features/perfil_page.dart';
import 'features/repartidor_shell.dart';
import 'features/servicio_page.dart';
import 'features/servicios_page.dart';

class _CambiosDeSesion extends ChangeNotifier {
  _CambiosDeSesion(Ref ref) {
    ref.listen(sesionActualProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final cambios = _CambiosDeSesion(ref);
  ref.onDispose(cambios.dispose);

  return GoRouter(
    initialLocation: '/cargando',
    refreshListenable: cambios,
    redirect: (context, state) {
      final sesion = ref.read(sesionActualProvider);
      final aca = state.matchedLocation;

      if (!sesion.hasValue) return aca == '/cargando' ? null : '/cargando';
      final s = sesion.value;
      if (s == null) return aca == '/entrar' ? null : '/entrar';

      // Solo riders. Un local o un cliente que entra aca ve el aviso en la
      // pantalla de login y puede cerrar sesion.
      if (s.rol != RolUsuario.repartidor) return aca == '/entrar' ? null : '/entrar';

      if (aca == '/entrar' || aca == '/cargando') return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/cargando', builder: (_, _) => const CargandoPage()),
      GoRoute(path: '/entrar', builder: (_, _) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RepartidorShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const InicioRepartidorPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/servicios', builder: (_, _) => const ServiciosPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/ganancias', builder: (_, _) => const GananciasPage())]),
          StatefulShellBranch(routes: [GoRoute(path: '/perfil', builder: (_, _) => const PerfilPage())]),
        ],
      ),
      GoRoute(
        path: '/servicio/:id',
        builder: (_, st) => ServicioEnCursoPage(envioId: st.pathParameters['id']!),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(body: Center(child: Text('No existe ${state.uri}'))),
  );
});
