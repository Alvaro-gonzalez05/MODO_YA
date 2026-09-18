import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'animaciones.dart';

/// Tono semantico de las pastillas de estado.
///
/// - [ember]: amarillo de marca con texto negro (estado activo / en curso).
/// - [info]: gris claro con texto oscuro (dato neutro: alias, categoria).
/// - [success]: verde claro (entregado, conectado).
/// - [danger]: rojo claro (rechazado, cancelado).
/// - [neutral]: blanco con sombra (sobre fotos).
/// - [dark]: negro con texto blanco (cerrado, inactivo).
enum MyBadgeTone { ember, info, success, danger, neutral, dark }

extension on MyBadgeTone {
  Color get background => switch (this) {
        MyBadgeTone.ember => MyColors.primary,
        MyBadgeTone.info => MyColors.secondaryContainer,
        MyBadgeTone.success => MyColors.successContainer,
        MyBadgeTone.danger => MyColors.errorContainer,
        MyBadgeTone.neutral => MyColors.surfaceContainerLowest,
        MyBadgeTone.dark => MyColors.dock,
      };

  Color get foreground => switch (this) {
        MyBadgeTone.ember => MyColors.onPrimary,
        MyBadgeTone.info => MyColors.onSecondaryContainer,
        MyBadgeTone.success => MyColors.onSuccessContainer,
        MyBadgeTone.danger => MyColors.onErrorContainer,
        MyBadgeTone.neutral => MyColors.onSurface,
        MyBadgeTone.dark => MyColors.inverseOnSurface,
      };
}

/// Pastilla de estado: "En camino", "Buscando cadete", "20% OFF".
///
/// Con [dot] en true dibuja el puntito de estado en vez de un icono. Cuando
/// cambia el texto o el tono, la pastilla hace una transicion animada.
class MyBadge extends StatelessWidget {
  const MyBadge(
    this.label, {
    super.key,
    this.tone = MyBadgeTone.ember,
    this.icon,
    this.dot = false,
  });

  final String label;
  final MyBadgeTone tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(
        horizontal: MySpacing.sm,
        vertical: MySpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(MyRadius.full),
        boxShadow: tone == MyBadgeTone.neutral ? MyShadows.subtle : null,
      ),
      child: MyCambio(
        child: Row(
          key: ValueKey('$label/$tone'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: tone.foreground,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: MySpacing.xs),
            ] else if (icon != null) ...[
              Icon(icon, size: 14, color: tone.foreground),
              const SizedBox(width: MySpacing.xxs + 2),
            ],
            Text(
              label,
              style: MyType.labelMd.copyWith(color: tone.foreground),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip de categoria o filtro. Activo: amarillo con texto negro. Inactivo:
/// blanco con borde suave. El cambio de estado esta animado.
class MyChip extends StatelessWidget {
  const MyChip(
    this.label, {
    super.key,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MyPressable(
      onTap: onTap,
      escala: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: MySpacing.lg,
          vertical: MySpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? MyColors.primary : MyColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(MyRadius.full),
          border: Border.all(color: selected ? MyColors.primary : MyColors.outlineVariant),
          boxShadow: selected ? MyShadows.glow : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: MyType.labelLg.copyWith(
            color: selected ? MyColors.onPrimary : MyColors.onSurfaceVariant,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// Disco circular con icono: volver, favorito, buscar, avatar.
class MyCircleIconButton extends StatelessWidget {
  const MyCircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44,
    this.background,
    this.foreground,
    this.shadows = MyShadows.control,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  /// Si es null, toma `surfaceContainerLowest`/`onSurface` del tema ambiente.
  final Color? background;
  final Color? foreground;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? esquema.surfaceContainerLowest,
        shape: BoxShape.circle,
        boxShadow: shadows,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: size * 0.45, color: foreground ?? esquema.onSurface),
        ),
      ),
    );
  }
}

/// Bloque de metrica: icono + numero grande + etiqueta.
///
/// Se usa en fila de tres en la oferta de servicio (km, minutos, pedidos) y en
/// el dashboard del administrador.
class MyStatTile extends StatelessWidget {
  const MyStatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this._background,
    this._valueColor,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color? _background;
  Color get background => _background ?? MyColors.secondaryContainer;
  final Color? _valueColor;
  Color get valueColor => _valueColor ?? MyColors.onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MySpacing.sm,
        vertical: MySpacing.md,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(MyRadius.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: MyColors.primary),
                const SizedBox(width: MySpacing.xxs + 2),
              ],
              Flexible(
                child: Text(
                  value,
                  style: MyType.headlineMd.copyWith(color: valueColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.xxs),
          Text(
            label,
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Fila de [MyStatTile] con separacion pareja.
class MyStatRow extends StatelessWidget {
  const MyStatRow({super.key, required this.tiles});

  final List<MyStatTile> tiles;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight acota la altura antes del stretch. Sin esto, dentro de
    // un ListView el Row recibe altura sin limite y `stretch` la propaga a los
    // hijos, rompiendo el layout de todo lo que viene despues.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: MySpacing.sm),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

/// Etiqueta chica en mayusculas que rotula un dato ("PUNTO DE RETIRO").
class MyOverline extends StatelessWidget {
  const MyOverline(this.text, {super.key, this._color});

  final String text;
  final Color? _color;
  Color get color => _color ?? MyColors.secondary;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: MyType.labelSm.copyWith(color: color),
    );
  }
}
