import 'package:flutter/material.dart';

/// Cual de los dos logos de marca dibuja [MyLogoMark].
enum MyLogoVariant {
  /// Logo de la app de clientes/comercios: "MODO YA".
  cliente,

  /// Logo de la app del repartidor: "MODO YA RIDERS".
  riders,
}

/// Isotipo de MODO YA: un pin de ubicacion con un repartidor en moto adentro
/// y lineas de velocidad saliendo hacia la izquierda.
///
/// Son los logos reales de la marca (`assets/branding/logo_modo_ya.png` y
/// `assets/branding/logo_riders.png` en este paquete), en alta resolucion:
/// se usan igual en el splash, la barra lateral de cada app y la hoja de
/// navegacion movil, para que la marca se vea siempre igual en toda la app.
class MyLogoMark extends StatelessWidget {
  const MyLogoMark({
    super.key,
    this.size = 96,
    this.color,
    this.variant = MyLogoVariant.cliente,
  });

  /// Lado del cuadrado en el que se dibuja la marca.
  final double size;

  /// Si se pasa, tine el isotipo de este color (por ejemplo para usarlo en
  /// blanco sobre un fondo de color). Por defecto conserva el amarillo del
  /// archivo original.
  final Color? color;

  /// App a la que pertenece este logo: cliente/comercio o rider.
  final MyLogoVariant variant;

  @override
  Widget build(BuildContext context) {
    final archivo = switch (variant) {
      MyLogoVariant.cliente => 'assets/branding/logo_modo_ya.png',
      MyLogoVariant.riders => 'assets/branding/logo_riders.png',
    };
    final imagen = Image.asset(
      archivo,
      package: 'my_ui',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
    );
    return SizedBox(width: size, height: size, child: imagen);
  }
}
