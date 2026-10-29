import 'package:flutter/material.dart';
import 'package:my_ui/my_ui.dart';

/// Lo que ocupa el lugar de un [MyKpi] mientras llega el dato.
///
/// Antes el inicio mostraba "0" hasta que llegaba la primera lectura, y un
/// "0 pedidos nuevos" en un local con tres esperando es peor que no mostrar
/// nada: parece que no hay que hacer nada.
class KpiCargando extends StatefulWidget {
  const KpiCargando({super.key, required this.rotulo, required this.icono});

  final String rotulo;
  final IconData icono;

  @override
  State<KpiCargando> createState() => _KpiCargandoState();
}

class _KpiCargandoState extends State<KpiCargando> with SingleTickerProviderStateMixin {
  late final _latido = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _latido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget barra(double ancho, double alto) => Container(
          width: ancho,
          height: alto,
          decoration: BoxDecoration(
            color: MyColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(MyRadius.md),
          ),
        );

    return Semantics(
      label: '${widget.rotulo}: cargando',
      child: MyCard(
        padding: const EdgeInsets.all(MySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: MySpacing.xxs),
                    child: Text(widget.rotulo.toUpperCase(), style: MyType.labelSm.copyWith(color: MyColors.secondary)),
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: MyColors.surfaceContainerHigh, shape: BoxShape.circle),
                  child: Icon(widget.icono, size: 20, color: MyColors.secondary),
                ),
              ],
            ),
            const SizedBox(height: MySpacing.sm),
            FadeTransition(
              opacity: Tween(begin: 0.35, end: 1.0).animate(_latido),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  barra(64, 36),
                  const SizedBox(height: MySpacing.xs),
                  barra(120, 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
