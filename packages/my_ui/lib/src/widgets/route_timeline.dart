import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import 'controls.dart';

/// Un punto del recorrido (retiro o entrega).
class MyRouteStop {
  const MyRouteStop({
    required this.overline,
    required this.title,
    this.subtitle,
    this.badge,
    this.icon = Symbols.storefront,
    this._iconBackground,
  });

  /// Rotulo chico en mayusculas: "PUNTO DE RETIRO".
  final String overline;

  /// Nombre del comercio o direccion de entrega.
  final String title;

  /// Detalle: calle, distancia, tiempo estimado.
  final String? subtitle;

  /// Pastilla a la derecha del rotulo ("A preparar", "Casa particular").
  final String? badge;

  final IconData icon;
  final Color? _iconBackground;
  Color get iconBackground => _iconBackground ?? MyColors.primary;
}

/// Recorrido retiro -> entrega con conector punteado entre los dos discos.
///
/// Aparece en la oferta de servicio, en el seguimiento del comercio y en el
/// detalle de envio del administrador.
class MyRouteTimeline extends StatelessWidget {
  const MyRouteTimeline({
    super.key,
    required this.stops,
    this.padding = const EdgeInsets.all(MySpacing.md),
    this._background,
  });

  final List<MyRouteStop> stops;
  final EdgeInsetsGeometry padding;
  final Color? _background;
  Color get background => _background ?? MyColors.surfaceContainerLow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(MyRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stops.length; i++)
            _Stop(
              stop: stops[i],
              isLast: i == stops.length - 1,
            ),
        ],
      ),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.stop, required this.isLast});

  final MyRouteStop stop;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: stop.iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  stop.icon,
                  size: 18,
                  color: MyColors.onPrimary,
                  fill: 1,
                ),
              ),
              if (!isLast)
                const Expanded(
                  child: _DashedConnector(),
                ),
            ],
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : MySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: MyOverline(stop.overline)),
                      if (stop.badge != null)
                        MyBadge(stop.badge!, tone: MyBadgeTone.info),
                    ],
                  ),
                  const SizedBox(height: MySpacing.xxs),
                  Text(
                    stop.title,
                    style: MyType.headlineSm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (stop.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      stop.subtitle!,
                      style:
                          MyType.bodyMd.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Linea vertical punteada que une dos paradas.
class _DashedConnector extends StatelessWidget {
  const _DashedConnector();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(2, double.infinity),
      painter: _DashedLinePainter(),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MyColors.outlineVariant
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dash = 4.0;
    const gap = 5.0;
    var y = 4.0;
    while (y < size.height - 2) {
      canvas.drawLine(Offset(1, y), Offset(1, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
