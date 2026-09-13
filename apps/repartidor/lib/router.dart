import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/ganancias_page.dart';
import 'features/inicio_page.dart';
import 'features/perfil_page.dart';
import 'features/repartidor_shell.dart';
import 'features/servicio_page.dart';
import 'features/servicios_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            RepartidorShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                name: 'inicio',
                builder: (_, _) => const InicioRepartidorPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/servicios',
                name: 'servicios',
                builder: (_, _) => const ServiciosPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ganancias',
                name: 'ganancias',
                builder: (_, _) => const GananciasPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/perfil',
                name: 'perfil',
                builder: (_, _) => const PerfilPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/servicio/:id',
        name: 'servicio',
        builder: (_, state) =>
            ServicioEnCursoPage(envioId: state.pathParameters['id']!),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Ruta no encontrada: ${state.uri}')),
    ),
  );
});
