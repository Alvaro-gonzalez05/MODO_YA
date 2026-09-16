import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';

/// Tarjeta blanca sobre el lienzo. Es el contenedor base de casi todo el
/// contenido: listados de envios, bloques de formulario, resumenes.
class MyCard extends StatefulWidget {
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
  State<MyCard> createState() => _MyCardState();
}

class _MyCardState extends State<MyCard> {
  var _encima = false;
  var _presionada = false;

  @override
  Widget build(BuildContext context) {
    final fondo = widget.color ?? Theme.of(context).cardTheme.color ?? MyColors.surfaceContainerLowest;
    final tocable = widget.onTap != null;
    // Las tarjetas blancas sobre fondo blanco necesitan un borde finito ademas
    // de la sombra; las de color (amarillo palido, gris) no.
    final conBorde = fondo == MyColors.surfaceContainerLowest;

    final contenido = Padding(padding: widget.padding, child: widget.child);
    final radio = BorderRadius.circular(widget.radius);

    final decorated = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, tocable && _encima && !_presionada ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: radio,
        border: conBorde ? Border.all(color: _encima && tocable ? MyColors.primary.withValues(alpha: 0.6) : MyColors.outlineVariant) : null,
        boxShadow: tocable && _encima ? MyShadows.control : widget.shadows,
      ),
      child: tocable
          ? Material(
              color: Colors.transparent,
              borderRadius: radio,
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: widget.onTap, borderRadius: radio, child: contenido),
            )
          : contenido,
    );

    if (!tocable) return decorated;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _presionada = true),
        onPointerUp: (_) => setState(() => _presionada = false),
        onPointerCancel: (_) => setState(() => _presionada = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: _presionada ? 0.98 : 1,
          child: decorated,
        ),
      ),
    );
  }
}

/// Tarjeta hero: el unico bloque negro de una pantalla blanca, con un brillo
/// amarillo en una esquina (como el banner "El mejor sabor en tu casa" de la
/// referencia).
///
/// Es el bloque de maxima jerarquia de cada pantalla (el "Pedir un rider" del
/// inicio del comercio, el resumen de ganancia del rider, el CTA flotante del
/// carrito). El texto que va adentro es blanco y los acentos, amarillos.
class MyHeroCard extends StatelessWidget {
  const MyHeroCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MySpacing.cardInner),
    this.radius = MyRadius.hero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1D18), MyColors.primaryContainer, MyColors.dock],
        ),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: MyShadows.hero,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: IgnorePointer(
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [Color(0x59FFC800), Color(0x00FFC800)],
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
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
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 520),
            curve: Curves.elasticOut,
            builder: (context, t, hijo) => Transform.scale(scale: t, child: hijo),
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: MyColors.primaryFixed,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: MyColors.onPrimaryFixed),
            ),
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
