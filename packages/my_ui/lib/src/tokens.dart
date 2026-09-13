import 'package:flutter/material.dart';

/// Tokens de diseno de MODO YA.
///
/// Los valores salen del design system "Artisanal Ember" exportado desde
/// Stitch (`DESIGN.md` + la config de Tailwind embebida en cada `code.html`).
/// Son la unica fuente de verdad: si una pantalla necesita un color o una
/// medida, sale de aca y no de un literal suelto.
abstract final class MyColors {
  // --- Marca -------------------------------------------------------------
  /// Ember rust. CTAs principales, iconos activos, precios destacados.
  static const primary = Color(0xFFA33900);
  static const onPrimary = Color(0xFFFFFFFF);

  /// Naranja mas encendido: relleno de las tarjetas hero.
  static const primaryContainer = Color(0xFFCC4900);
  static const onPrimaryContainer = Color(0xFFFFFBFF);

  static const primaryFixed = Color(0xFFFFDBCE);
  static const primaryFixedDim = Color(0xFFFFB599);
  static const onPrimaryFixed = Color(0xFF370E00);
  static const onPrimaryFixedVariant = Color(0xFF7F2B00);
  static const inversePrimary = Color(0xFFFFB599);
  static const surfaceTint = Color(0xFFA73A00);

  // --- Secundario (azul pizarra) ----------------------------------------
  static const secondary = Color(0xFF545F73);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFD5E0F8);
  static const onSecondaryContainer = Color(0xFF586377);
  static const secondaryFixed = Color(0xFFD8E3FB);
  static const secondaryFixedDim = Color(0xFFBCC7DE);
  static const onSecondaryFixed = Color(0xFF111C2D);
  static const onSecondaryFixedVariant = Color(0xFF3C475A);

  // --- Terciario ---------------------------------------------------------
  static const tertiary = Color(0xFF994100);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFC05400);
  static const onTertiaryContainer = Color(0xFFFFFBFF);
  static const tertiaryFixed = Color(0xFFFFDBCA);
  static const tertiaryFixedDim = Color(0xFFFFB690);
  static const onTertiaryFixed = Color(0xFF341100);
  static const onTertiaryFixedVariant = Color(0xFF783200);

  // --- Superficies -------------------------------------------------------
  static const surface = Color(0xFFF8F9FF);
  static const surfaceDim = Color(0xFFCBDBF5);
  static const surfaceBright = Color(0xFFF8F9FF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFEFF4FF);
  static const surfaceContainer = Color(0xFFE5EEFF);
  static const surfaceContainerHigh = Color(0xFFDCE9FF);
  static const surfaceContainerHighest = Color(0xFFD3E4FE);
  static const surfaceVariant = Color(0xFFD3E4FE);
  static const onSurface = Color(0xFF0B1C30);
  static const onSurfaceVariant = Color(0xFF5A4138);

  /// Navy del dock flotante y de los fondos "oscuros" (mapa, header rider).
  static const inverseSurface = Color(0xFF213145);
  static const inverseOnSurface = Color(0xFFEAF1FF);
  static const dock = Color(0xFF1E293B);

  static const outline = Color(0xFF8E7166);
  static const outlineVariant = Color(0xFFE2BFB2);

  // --- Estado ------------------------------------------------------------
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  /// Verde de "conectado / disponible". No viene del export de Stitch pero
  /// las pantallas del repartidor lo usan como punto de estado.
  static const success = Color(0xFF1B8A5A);
  static const successContainer = Color(0xFFD3F3E3);
}

/// Escala de espaciado (rem del export -> px logicos).
abstract final class MySpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;

  /// Padding lateral estandar de todas las pantallas.
  static const screenEdge = 20.0;

  /// Padding interno de las tarjetas.
  static const cardInner = 20.0;

  /// Separacion del dock flotante respecto del borde inferior.
  static const dockOffset = 24.0;

  /// Espacio libre al final del scroll para que el dock no tape contenido.
  static const dockClearance = 88.0;
}

/// Radios de esquina.
abstract final class MyRadius {
  static const sm = 4.0;
  static const md = 12.0;
  static const lg = 16.0;

  /// Tarjetas de contenido (`rounded-2xl`).
  static const card = 24.0;

  /// Tarjetas hero y hojas inferiores (`rounded-3xl`).
  static const hero = 28.0;

  static const full = 999.0;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// Sombras. El sistema evita bordes duros y se apoya en sombras difusas.
abstract final class MyShadows {
  /// Nivel 1 - tarjeta elevada sobre el lienzo.
  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F0F172A),
      blurRadius: 24,
      offset: Offset(0, 8),
      spreadRadius: -4,
    ),
  ];

  /// Nivel 2 - tarjeta hero, con brillo ember.
  static const hero = <BoxShadow>[
    BoxShadow(
      color: Color(0x52CC4900),
      blurRadius: 32,
      offset: Offset(0, 16),
      spreadRadius: -8,
    ),
  ];

  /// Nivel 3 - dock de navegacion flotante.
  static const dock = <BoxShadow>[
    BoxShadow(
      color: Color(0x59213145),
      blurRadius: 40,
      offset: Offset(0, 20),
      spreadRadius: -10,
    ),
  ];

  /// Controles chicos: botones circulares, badges, contadores.
  static const control = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Sombra muy sutil de los chips y pastillas sobre fondo claro.
  static const subtle = <BoxShadow>[
    BoxShadow(
      color: Color(0x0D0B1C30),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];
}
