import 'dart:ui';

import 'package:flutter/widgets.dart';

/// Deja arrastrar con el mouse una fila que se desplaza de costado (chips de
/// filtros, carruseles).
///
/// Flutter, de entrada, solo arrastra con el dedo, el lápiz y el touchpad: en
/// la compu una fila de chips que no entra queda cortada y la rueda del mouse
/// no la mueve, así que lo que queda a la derecha no se puede ver.
class MyArrastreConMouse extends StatelessWidget {
  const MyArrastreConMouse({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: child,
    );
  }
}
