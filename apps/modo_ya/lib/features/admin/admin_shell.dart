import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Contenedor del panel de administracion.
///
/// Se usa sobre todo en Windows: riel lateral en ventanas anchas, barra
/// inferior cuando la ventana es angosta (o en el celular).
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinos = [
    (icon: Symbols.dashboard, label: 'Resumen'),
    (icon: Symbols.receipt_long, label: 'Pedidos'),
    (icon: Symbols.storefront, label: 'Locales'),
    (icon: Symbols.sports_motorsports, label: 'Riders'),
    (icon: Symbols.package_2, label: 'Envios'),
    (icon: Symbols.tune, label: 'Tarifas'),
  ];

  void _ir(int i) => navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compacto = MediaQuery.sizeOf(context).width < 900;
    final pendientes = ref.watch(pedidosPendientesDePagoProvider).value?.length ?? 0;

    if (compacto) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _ir,
          backgroundColor: MyColors.surfaceContainerLowest,
          indicatorColor: MyColors.primaryFixed,
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          destinations: [
            for (var i = 0; i < _destinos.length; i++)
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: i == 1 && pendientes > 0,
                  label: Text('$pendientes'),
                  child: Icon(_destinos[i].icon),
                ),
                label: _destinos[i].label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Riel(
            seleccionado: navigationShell.currentIndex,
            onSelect: _ir,
            pendientes: pendientes,
            onSalir: () => ref.read(authRepositoryProvider).salir(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

class _Riel extends ConsumerWidget {
  const _Riel({
    required this.seleccionado,
    required this.onSelect,
    required this.pendientes,
    required this.onSalir,
  });

  final int seleccionado;
  final ValueChanged<int> onSelect;
  final int pendientes;
  final VoidCallback onSalir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    return Container(
      width: 236,
      color: MyColors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(MySpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: MyColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Symbols.bolt, size: 20, color: MyColors.onPrimary, fill: 1),
                ),
                const SizedBox(width: MySpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MODO YA', style: MyType.headlineSm),
                      Text('Administracion', style: MyType.labelSm.copyWith(color: MyColors.secondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: MySpacing.sm),
          for (var i = 0; i < AdminShell._destinos.length; i++)
            _ItemRiel(
              icon: AdminShell._destinos[i].icon,
              label: AdminShell._destinos[i].label,
              activo: i == seleccionado,
              contador: i == 1 ? pendientes : 0,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Symbols.account_circle, color: MyColors.secondary),
            title: Text(sesion.nombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(sesion.email ?? '', style: MyType.bodySm, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          ListTile(
            leading: const Icon(Symbols.logout, color: MyColors.secondary),
            title: Text('Salir', style: MyType.labelLg),
            onTap: onSalir,
          ),
          const SizedBox(height: MySpacing.xs),
        ],
      ),
    );
  }
}

class _ItemRiel extends StatelessWidget {
  const _ItemRiel({
    required this.icon,
    required this.label,
    required this.activo,
    required this.onTap,
    this.contador = 0,
  });

  final IconData icon;
  final String label;
  final bool activo;
  final int contador;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MySpacing.sm, vertical: 2),
      child: Material(
        color: activo ? MyColors.primaryFixed : Colors.transparent,
        borderRadius: BorderRadius.circular(MyRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MyRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(MySpacing.sm),
            child: Row(
              children: [
                Icon(icon, size: 21, color: activo ? MyColors.primary : MyColors.secondary, fill: activo ? 1 : 0),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: MyType.labelLg.copyWith(color: activo ? MyColors.primary : MyColors.onSurface),
                  ),
                ),
                if (contador > 0) MyBadge('$contador', tone: MyBadgeTone.ember),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Encabezado comun de las pantallas del panel.
class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.titulo,
    required this.bajada,
    this.acciones = const [],
  });

  final String titulo;
  final String bajada;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.lg),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: MySpacing.md,
        runSpacing: MySpacing.sm,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo, style: MyType.headlineLg),
              const SizedBox(height: MySpacing.xxs),
              Text(bajada, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
            ],
          ),
          if (acciones.isNotEmpty) Wrap(spacing: MySpacing.sm, children: acciones),
        ],
      ),
    );
  }
}

/// Tono de pastilla para un estado de aprobacion.
MyBadgeTone tonoAprobacion(EstadoAprobacion e) => switch (e) {
      EstadoAprobacion.aprobado => MyBadgeTone.success,
      EstadoAprobacion.pendiente => MyBadgeTone.ember,
      _ => MyBadgeTone.danger,
    };
