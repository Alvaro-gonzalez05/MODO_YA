import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

/// Tono semantico de las pastillas de estado.
enum MyBadgeTone { ember, info, success, danger, neutral, dark }

extension on MyBadgeTone {
  Color get background => switch (this) {
        MyBadgeTone.ember => MyColors.primaryFixed,
        MyBadgeTone.info => MyColors.secondaryContainer,
        MyBadgeTone.success => MyColors.successContainer,
        MyBadgeTone.danger => MyColors.errorContainer,
        MyBadgeTone.neutral => MyColors.surfaceContainerLowest,
        MyBadgeTone.dark => MyColors.dock,
      };

  Color get foreground => switch (this) {
        MyBadgeTone.ember => MyColors.onPrimaryFixedVariant,
        MyBadgeTone.info => MyColors.onSecondaryContainer,
        MyBadgeTone.success => const Color(0xFF0C5138),
        MyBadgeTone.danger => MyColors.onErrorContainer,
        MyBadgeTone.neutral => MyColors.onSurface,
        MyBadgeTone.dark => MyColors.inverseOnSurface,
      };
}

/// Pastilla de estado: "En camino", "Buscando cadete", "20% OFF".
///
/// Con [dot] en true dibuja el puntito de estado en vez de un icono.
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
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MySpacing.sm,
        vertical: MySpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(MyRadius.full),
        boxShadow: tone == MyBadgeTone.neutral ? MyShadows.subtle : null,
      ),
      child: Row(
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
    );
  }
}

/// Chip de categoria o filtro. Activo: navy solido. Inactivo: blanco.
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
    return Material(
      color: selected ? MyColors.dock : MyColors.surfaceContainerLowest,
      shape: const StadiumBorder(),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MySpacing.lg,
            vertical: MySpacing.sm,
          ),
          child: Text(
            label,
            style: MyType.labelLg.copyWith(
              color: selected ? MyColors.inverseOnSurface : MyColors.secondary,
            ),
          ),
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
    this.background = MyColors.secondaryContainer,
    this.valueColor = MyColors.onSurface,
  });

  final String value;
  final String label;
  final IconData? icon;
  final Color background;
  final Color valueColor;

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
  const MyOverline(this.text, {super.key, this.color = MyColors.secondary});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: MyType.labelSm.copyWith(color: color),
    );
  }
}
