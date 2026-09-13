import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// Contenedor del panel de administracion.
///
/// A diferencia de las pantallas del comercio (celular, dock flotante), este
/// panel se usa sobre todo en Windows: por eso usa un riel lateral y se
/// colapsa a un dock inferior solo cuando la ventana es angosta.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinos = [
    (icon: Symbols.dashboard, label: 'Resumen'),
    (icon: Symbols.map, label: 'Mapa'),
    (icon: Symbols.storefront, label: 'Comercios'),
    (icon: Symbols.sports_motorsports, label: 'Cadetes'),
    (icon: Symbols.package_2, label: 'Envios'),
    (icon: Symbols.tune, label: 'Tarifas'),
  ];

  void _ir(int i) => navigationShell.goBranch(
        i,
        initialLocation: i == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final compacto = ancho < 900;

    if (compacto) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _ir,
          backgroundColor: MyColors.surfaceContainerLowest,
          indicatorColor: MyColors.primaryFixed,
          destinations: [
            for (final d in _destinos)
              NavigationDestination(icon: Icon(d.icon), label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _Riel(
            destinos: _destinos,
            seleccionado: navigationShell.currentIndex,
            onSelect: _ir,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

class _Riel extends StatelessWidget {
  const _Riel({
    required this.destinos,
    required this.seleccionado,
    required this.onSelect,
  });

  final List<({IconData icon, String label})> destinos;
  final int seleccionado;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
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
                  child: const Icon(Symbols.bolt,
                      size: 20, color: MyColors.onPrimary, fill: 1),
                ),
                const SizedBox(width: MySpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MODO YA', style: MyType.headlineSm),
                      Text(
                        'Administracion',
                        style: MyType.labelSm
                            .copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: MySpacing.sm),
          for (var i = 0; i < destinos.length; i++)
            _ItemRiel(
              destino: destinos[i],
              activo: i == seleccionado,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Symbols.logout, color: MyColors.secondary),
            title: Text('Salir', style: MyType.labelLg),
            onTap: () => context.goNamed('bienvenida'),
          ),
          const SizedBox(height: MySpacing.xs),
        ],
      ),
    );
  }
}

class _ItemRiel extends StatelessWidget {
  const _ItemRiel({
    required this.destino,
    required this.activo,
    required this.onTap,
  });

  final ({IconData icon, String label}) destino;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MySpacing.sm,
        vertical: 2,
      ),
      child: Material(
        color: activo ? MyColors.primaryFixed : Colors.transparent,
        borderRadius: BorderRadius.circular(MyRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MyRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MySpacing.sm,
              vertical: MySpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  destino.icon,
                  size: 21,
                  color: activo ? MyColors.primary : MyColors.secondary,
                  fill: activo ? 1 : 0,
                ),
                const SizedBox(width: MySpacing.sm),
                Text(
                  destino.label,
                  style: MyType.labelLg.copyWith(
                    color: activo ? MyColors.primary : MyColors.onSurface,
                  ),
                ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: MyType.headlineLg),
                const SizedBox(height: MySpacing.xxs),
                Text(
                  bajada,
                  style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
          ...acciones,
        ],
      ),
    );
  }
}
