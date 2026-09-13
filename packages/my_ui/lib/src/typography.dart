import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Tipografia de MODO YA.
///
/// Dos familias, con roles bien separados:
/// - **Outfit** para titulos, numeros y precios (geometrica, alto contraste).
/// - **Be Vietnam Pro** para cuerpo y etiquetas (legible en tamanos chicos).
abstract final class MyType {
  static TextStyle _outfit({
    required double size,
    required FontWeight weight,
    required double height,
    double? tracking,
    Color? color,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        height: height / size,
        letterSpacing: tracking == null ? null : tracking * size,
        color: color ?? MyColors.onSurface,
      );

  static TextStyle _vietnam({
    required double size,
    required FontWeight weight,
    required double height,
    double? tracking,
    Color? color,
  }) =>
      GoogleFonts.beVietnamPro(
        fontSize: size,
        fontWeight: weight,
        height: height / size,
        letterSpacing: tracking == null ? null : tracking * size,
        color: color ?? MyColors.onSurface,
      );

  // --- Display / Headline (Outfit) ---------------------------------------
  static TextStyle get displayLg =>
      _outfit(size: 36, weight: FontWeight.w700, height: 44, tracking: -0.02);

  static TextStyle get headlineLg =>
      _outfit(size: 28, weight: FontWeight.w700, height: 36, tracking: -0.015);

  static TextStyle get headlineMd =>
      _outfit(size: 22, weight: FontWeight.w600, height: 28, tracking: -0.01);

  static TextStyle get headlineSm =>
      _outfit(size: 18, weight: FontWeight.w600, height: 24);

  /// Precio grande (tarifa del envio, ganancia del cadete).
  static TextStyle get priceHero =>
      _outfit(size: 30, weight: FontWeight.w700, height: 36, tracking: -0.02);

  // --- Body (Be Vietnam Pro) ---------------------------------------------
  static TextStyle get bodyLg =>
      _vietnam(size: 16, weight: FontWeight.w400, height: 24);

  static TextStyle get bodyMd =>
      _vietnam(size: 14, weight: FontWeight.w400, height: 20);

  static TextStyle get bodySm =>
      _vietnam(size: 12, weight: FontWeight.w400, height: 16);

  // --- Labels (Be Vietnam Pro) -------------------------------------------
  static TextStyle get labelLg =>
      _vietnam(size: 14, weight: FontWeight.w600, height: 20);

  static TextStyle get labelMd =>
      _vietnam(size: 12, weight: FontWeight.w600, height: 16, tracking: 0.02);

  /// Etiqueta chica en mayusculas: "PUNTO DE RETIRO", "PEDIDO #MY-8492".
  static TextStyle get labelSm =>
      _vietnam(size: 10, weight: FontWeight.w700, height: 14, tracking: 0.04);

  /// El `TextTheme` de Material mapeado a los roles de arriba, para que los
  /// widgets estandar (`ListTile`, `AppBar`, etc.) hereden la tipografia.
  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLg,
        displayMedium: headlineLg,
        displaySmall: headlineMd,
        headlineLarge: headlineLg,
        headlineMedium: headlineMd,
        headlineSmall: headlineSm,
        titleLarge: headlineSm,
        titleMedium: labelLg,
        titleSmall: labelMd,
        bodyLarge: bodyLg,
        bodyMedium: bodyMd,
        bodySmall: bodySm,
        labelLarge: labelLg,
        labelMedium: labelMd,
        labelSmall: labelSm,
      );
}
