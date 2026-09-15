import 'package:flutter/material.dart';

/// Tokens de diseno de MODO YA.
///
/// Identidad de marca: fondo negro, acento amarillo, texto blanco. Los
/// nombres de los tokens siguen los roles de un `ColorScheme` de Material 3
/// para que toda la app (colores, botones, tarjetas, campos) se actualice
/// desde este unico archivo.
abstract final class MyColors {
  // --- Marca: amarillo ----------------------------------------------------
  /// Amarillo MODO YA. CTAs principales, iconos activos, precios destacados.
  static const primary = Color(0xFFFFC800);
  static const onPrimary = Color(0xFF171200);

  /// Relleno de tarjetas hero / paneles destacados con tinte amarillo.
  static const primaryContainer = Color(0xFF2E2610);
  static const onPrimaryContainer = Color(0xFFFFE9A6);

  static const primaryFixed = Color(0xFF473A12);
  static const primaryFixedDim = Color(0xFF6B5818);
  static const onPrimaryFixed = Color(0xFFFFF3D1);
  static const onPrimaryFixedVariant = Color(0xFFFFE9A6);
  static const inversePrimary = Color(0xFF7A5B00);
  static const surfaceTint = Color(0xFFFFC800);

  // --- Secundario (gris pizarra frio) -------------------------------------
  static const secondary = Color(0xFFB9C2D6);
  static const onSecondary = Color(0xFF1E2430);
  static const secondaryContainer = Color(0xFF232733);
  static const onSecondaryContainer = Color(0xFFD7DEEC);
  static const secondaryFixed = Color(0xFF3A4152);
  static const secondaryFixedDim = Color(0xFF232733);
  static const onSecondaryFixed = Color(0xFFE6EAF3);
  static const onSecondaryFixedVariant = Color(0xFFC3CADA);

  // --- Terciario (ambar calido, acento secundario) ------------------------
  static const tertiary = Color(0xFFFFB74D);
  static const onTertiary = Color(0xFF2B1600);
  static const tertiaryContainer = Color(0xFF3A2400);
  static const onTertiaryContainer = Color(0xFFFFDBB0);
  static const tertiaryFixed = Color(0xFF4A2E00);
  static const tertiaryFixedDim = Color(0xFF6B4300);
  static const onTertiaryFixed = Color(0xFFFFE8CC);
  static const onTertiaryFixedVariant = Color(0xFFFFCE94);

  // --- Superficies ---------------------------------------------------------
  /// Fondo base de pantalla: negro MODO YA.
  static const surface = Color(0xFF0D0D0D);
  static const surfaceDim = Color(0xFF000000);
  static const surfaceBright = Color(0xFF2C2C31);

  /// Tarjetas: un escalon mas claro que el fondo para que "floten".
  static const surfaceContainerLowest = Color(0xFF17171A);
  static const surfaceContainerLow = Color(0xFF1C1C20);
  static const surfaceContainer = Color(0xFF212126);
  static const surfaceContainerHigh = Color(0xFF28282E);
  static const surfaceContainerHighest = Color(0xFF313138);
  static const surfaceVariant = Color(0xFF313138);
  static const onSurface = Color(0xFFFFFFFF);
  static const onSurfaceVariant = Color(0xFFB4B4BE);

  /// Superficie "invertida" (clara), para snackbars/tooltips sobre la app oscura.
  static const inverseSurface = Color(0xFFEDEDF0);
  static const inverseOnSurface = Color(0xFF1A1A1D);

  /// Dock de navegacion flotante: un gris carbon distinguible del fondo negro.
  static const dock = Color(0xFF141416);

  static const outline = Color(0xFF4A4A52);
  static const outlineVariant = Color(0xFF2A2A2E);

  // --- Estado ------------------------------------------------------------
  static const error = Color(0xFFFF6B6B);
  static const onError = Color(0xFF3A0A0A);
  static const errorContainer = Color(0xFF3A1414);
  static const onErrorContainer = Color(0xFFFFDAD6);

  /// Verde de "conectado / disponible". Uso puntual (estado de conexion del
  /// repartidor), no reemplaza al amarillo como color de marca.
  static const success = Color(0xFF3DDC84);
  static const successContainer = Color(0xFF16301F);
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

/// Sombras. Sobre fondo negro una sombra oscura no se ve: la elevacion se
/// resuelve con brillos claros/ambar en vez de sombras oscuras difusas.
abstract final class MyShadows {
  /// Nivel 1 - tarjeta elevada sobre el lienzo negro.
  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 20,
      offset: Offset(0, 8),
      spreadRadius: -6,
    ),
  ];

  /// Nivel 2 - tarjeta hero, con brillo amarillo de marca.
  static const hero = <BoxShadow>[
    BoxShadow(
      color: Color(0x40FFC800),
      blurRadius: 32,
      offset: Offset(0, 16),
      spreadRadius: -8,
    ),
  ];

  /// Nivel 3 - dock de navegacion flotante.
  static const dock = <BoxShadow>[
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 40,
      offset: Offset(0, 20),
      spreadRadius: -10,
    ),
  ];

  /// Controles chicos: botones circulares, badges, contadores.
  static const control = <BoxShadow>[
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Sombra muy sutil de los chips y pastillas sobre fondo oscuro.
  static const subtle = <BoxShadow>[
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];
}
