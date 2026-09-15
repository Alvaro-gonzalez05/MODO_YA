import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';

/// Tarjeta blanca sobre el lienzo. Es el contenedor base de casi todo el
/// contenido: listados de envios, bloques de formulario, resumenes.
class MyCard extends StatelessWidget {
  const MyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MySpacing.cardInner),
    this.radius = MyRadius.card,
    this.color,
    this.shadows = MyShadows.card,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Color de fondo. Si es null, toma el de la tarjeta del tema ambiente
  /// (`CardThemeData.color`), que cambia entre [MyTheme.dark] y
  /// [MyTheme.claro] segun la pantalla.
  final Color? color;
  final List<BoxShadow> shadows;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).cardTheme.color ?? MyColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return decorated;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      ),
    );
  }
}

/// Tarjeta hero: fondo oscuro con tinte ambar y brillo amarillo propio.
///
/// Es el bloque de maxima jerarquia de cada pantalla (el "Pedir Cadete
/// Express" del inicio del comercio, el resumen de ganancia del cadete).
/// El texto que va adentro es blanco: por eso el fondo se mantiene oscuro
/// (el amarillo de marca queda solo como brillo/acento, no como relleno).
class MyHeroCard extends StatelessWidget {
  const MyHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MySpacing.cardInner),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MyColors.primaryContainer, MyColors.surfaceContainerHigh],
        ),
        borderRadius: BorderRadius.circular(MyRadius.hero),
        boxShadow: MyShadows.hero,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Encabezado de seccion: titulo grande, bajada opcional y accion a la derecha
/// ("Envios de hoy" / "Ver historial").
class MySectionHeader extends StatelessWidget {
  const MySectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: MyType.headlineMd),
              if (subtitle != null) ...[
                const SizedBox(height: MySpacing.xxs),
                Text(
                  subtitle!,
                  style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: MySpacing.xs),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// Estado vacio con icono, titulo y texto de ayuda.
class MyEmptyState extends StatelessWidget {
  const MyEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Symbols.inbox,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    // Column en vez de Center: este estado suele ir dentro de un ListView, y
    // Center pide toda la altura disponible (infinita en un scroll).
    return Padding(
      padding: const EdgeInsets.all(MySpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: esquema.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: esquema.onSurfaceVariant),
          ),
          const SizedBox(height: MySpacing.md),
          Text(title, style: MyType.headlineSm, textAlign: TextAlign.center),
          const SizedBox(height: MySpacing.xs),
          Text(
            message,
            style: MyType.bodyMd.copyWith(color: esquema.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: MySpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
