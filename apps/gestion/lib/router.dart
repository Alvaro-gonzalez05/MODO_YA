import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_shell.dart';
import 'features/admin/comercios_page.dart';
import 'features/admin/dashboard_page.dart';
import 'features/admin/envios_page.dart';
import 'features/admin/mapa_page.dart';
import 'features/admin/repartidores_page.dart';
import 'features/admin/tarifas_page.dart';
import 'features/comercio/comercio_shell.dart';
import 'features/comercio/crear_envio_page.dart';
import 'features/comercio/historial_page.dart';
import 'features/comercio/inicio_page.dart';
import 'features/comercio/seguimiento_page.dart';
import 'features/comercio/suscripcion_page.dart';
import 'features/onboarding/bienvenida_page.dart';
import 'features/onboarding/registro_page.dart';
import 'features/onboarding/revision_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'bienvenida',
        builder: (_, _) => const BienvenidaPage(),
      ),
      GoRoute(
        path: '/registro',
        name: 'registro',
        builder: (_, _) => const RegistroComercioPage(),
      ),
      GoRoute(
        path: '/revision',
        name: 'revision',
        builder: (_, _) => const CuentaEnRevisionPage(),
      ),

      // --- Comercio -------------------------------------------------------
      // El dock inferior vive en el shell; cada rama mantiene su propio
      // historial de navegacion.
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            ComercioShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/comercio',
                name: 'comercioInicio',
                builder: (_, _) => const InicioComercioPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/comercio/envios',
                name: 'comercioEnvios',
                builder: (_, _) => const HistorialPage(soloActivos: true),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/comercio/historial',
                name: 'comercioHistorial',
                builder: (_, _) => const HistorialPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/comercio/suscripcion',
                name: 'comercioSuscripcion',
                builder: (_, _) => const SuscripcionPage(),
              ),
            ],
          ),
        ],
      ),

      // Pantallas de flujo, fuera del dock: se abren por encima.
      GoRoute(
        path: '/comercio/nuevo',
        name: 'crearEnvio',
        builder: (_, _) => const CrearEnvioPage(),
      ),
      GoRoute(
        path: '/comercio/envio/:id',
        name: 'seguimiento',
        builder: (_, state) =>
            SeguimientoPage(envioId: state.pathParameters['id']!),
      ),

      // --- Administracion -------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (_, _, navigationShell) =>
            AdminShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                name: 'adminDashboard',
                builder: (_, _) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/mapa',
                name: 'adminMapa',
                builder: (_, _) => const MapaEnVivoPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/comercios',
                name: 'adminComercios',
                builder: (_, _) => const AdminComerciosPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/repartidores',
                name: 'adminRepartidores',
                builder: (_, _) => const AdminRepartidoresPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/envios',
                name: 'adminEnvios',
                builder: (_, _) => const AdminEnviosPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin/tarifas',
                name: 'adminTarifas',
                builder: (_, _) => const AdminTarifasPage(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Ruta no encontrada: ${state.uri}')),
    ),
  );
});
