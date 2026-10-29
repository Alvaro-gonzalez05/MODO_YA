import 'package:flutter/widgets.dart';

/// Lo que va en un lugar angosto y no se puede cortar con "…", como una
/// pastilla de estado: si no entra, se achica en vez de desbordar.
///
/// `MyBadge` no corta el texto a propósito (una pastilla cortada no se lee), y
/// en la columna "Estado" de una tabla "Rider en camino al local" no entra.
/// Achicarla un poco se sigue leyendo; la franja amarilla y negra, no.
class Encoger extends StatelessWidget {
  const Encoger({super.key, required this.child, this.alineacion = Alignment.centerRight});

  final Widget child;
  final AlignmentGeometry alineacion;

  @override
  Widget build(BuildContext context) {
    return FittedBox(fit: BoxFit.scaleDown, alignment: alineacion, child: child);
  }
}
