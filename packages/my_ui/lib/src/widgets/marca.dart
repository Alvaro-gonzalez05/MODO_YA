import 'package:flutter/material.dart';

/// Isotipo de MODO YA: un pin de ubicacion con un repartidor en moto adentro
/// y lineas de velocidad saliendo hacia la izquierda.
///
/// Es el logo real de la marca (`assets/branding/logo.png` en este paquete),
/// no un dibujo aproximado: se usa igual en el splash, la barra lateral de
/// cada app y la hoja de navegacion movil, para que la marca se vea siempre
/// igual en toda la app.
class MyLogoMark extends StatelessWidget {
  const MyLogoMark({super.key, this.size = 96, this.color});

  /// Lado del cuadrado en el que se dibuja la marca.
  final double size;

  /// Si se pasa, tine el isotipo de este color (por ejemplo para usarlo en
  /// blanco sobre un fondo de color). Por defecto conserva el amarillo del
  /// archivo original.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final imagen = Image.asset(
      'assets/branding/logo.png',
      package: 'my_ui',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
    );
    return SizedBox(width: size, height: size, child: imagen);
  }
}
