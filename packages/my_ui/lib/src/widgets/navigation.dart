import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import 'animaciones.dart';
import 'marca.dart';

/// Un destino del dock inferior.
class MyDockItem {
  const MyDockItem({required this.icon, required this.label, this.contador = 0});

  final IconData icon;
  final String label;

  /// Numero en el icono (pedidos nuevos, por cobrar). 0 = nada.
  final int contador;
}

/// Dock de navegacion flotante: capsula blanca suspendida sobre el contenido,
/// con una pastilla amarilla marcando la pestana activa (como la barra
/// inferior de la referencia).
///
/// Va dentro de un `Stack` alineado abajo, no como `bottomNavigationBar`,
/// porque flota por encima del scroll (por eso [MySpacing.dockClearance]
/// al final de cada lista). Entra deslizandose desde abajo al montarse.
class MyDock extends StatelessWidget {
  const MyDock({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<MyDockItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: MySpacing.screenEdge,
        right: MySpacing.screenEdge,
        bottom: MySpacing.dockOffset + MediaQuery.paddingOf(context).bottom,
      ),
      child: MyApareceEn(
        desplazamiento: 32,
        duracion: const Duration(milliseconds: 460),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: MySpacing.xs),
          decoration: BoxDecoration(
            color: MyColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(MyRadius.full),
            border: Border.all(color: MyColors.outlineVariant),
            boxShadow: MyShadows.dock,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < items.length; i++)
                _DockSlot(
                  item: items[i],
                  active: i == currentIndex,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockSlot extends StatelessWidget {
  const _DockSlot({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final MyDockItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: item.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              height: 52,
              padding: EdgeInsets.symmetric(horizontal: active ? 12 : 8),
              decoration: BoxDecoration(
                color: active ? MyColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(MyRadius.full),
                boxShadow: active ? MyShadows.glow : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Badge(
                    isLabelVisible: item.contador > 0,
                    label: Text('${item.contador}'),
                    backgroundColor: active ? MyColors.dock : MyColors.error,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: active ? 1 : 0),
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.elasticOut,
                      builder: (context, t, hijo) => Transform.scale(scale: 1 + 0.12 * t, child: hijo),
                      child: Icon(
                        item.icon,
                        size: 22,
                        color: active ? MyColors.onPrimary : MyColors.secondary,
                        fill: active ? 1 : 0,
                      ),
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(height: 2),
                    // Con cinco botones en un celular angosto el texto no entra
                    // entero: se achica en vez de cortarse ("Res...").
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        style: MyType.labelSm.copyWith(color: MyColors.onPrimary),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra superior de las apps moviles: marca, selector de zona y avatar.
class MyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MyTopBar({
    super.key,
    this.zona = 'Malargüe, Mza',
    this.onZona,
    this.onPerfil,
    this.trailing,
  });

  final String zona;
  final VoidCallback? onZona;
  final VoidCallback? onPerfil;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MyColors.surface,
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: SizedBox(
        height: 64,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: MySpacing.screenEdge),
          child: Row(
            children: [
              const _BrandMark(),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ZonaPill(zona: zona, onTap: onZona),
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: MySpacing.xs),
              ],
              GestureDetector(
                onTap: onPerfil,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: MyColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Symbols.person,
                    size: 20,
                    color: MyColors.onPrimary,
                    fill: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MyLogoMark(size: 30),
        const SizedBox(width: MySpacing.xs),
        Text(
          'MODO YA',
          style: MyType.headlineSm.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _ZonaPill extends StatelessWidget {
  const _ZonaPill({required this.zona, this.onTap});

  final String zona;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MySpacing.sm,
          vertical: MySpacing.xs,
        ),
        decoration: BoxDecoration(
          color: MyColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(MyRadius.full),
          border: Border.all(color: MyColors.outlineVariant),
          boxShadow: MyShadows.subtle,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.location_on,
                size: 16, color: MyColors.primary, fill: 1),
            const SizedBox(width: MySpacing.xxs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                zona,
                style: MyType.labelMd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Symbols.keyboard_arrow_down,
                size: 16, color: MyColors.outline),
          ],
        ),
      ),
    );
  }
}

/// Andamio con dock flotante ya posicionado.
///
/// [body] se dibuja a pantalla completa y el dock queda encima; acordate de
/// dejar [MySpacing.dockClearance] de padding inferior en el scroll.
class MyDockScaffold extends StatelessWidget {
  const MyDockScaffold({
    super.key,
    required this.body,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    this.appBar,
    this.backgroundColor = MyColors.surface,
  });

  final Widget body;
  final List<MyDockItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final PreferredSizeWidget? appBar;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Align(
            alignment: Alignment.bottomCenter,
            child: MyDock(
              items: items,
              currentIndex: currentIndex,
              onSelect: onSelect,
            ),
          ),
        ],
      ),
    );
  }
}
