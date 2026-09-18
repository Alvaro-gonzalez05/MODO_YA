import 'package:flutter/material.dart';

/// Tokens de diseno de MODO YA.
///
/// Identidad de marca: **fondo blanco, acento amarillo, texto negro**. El
/// negro se usa solo como superficie fuerte y puntual (splash, banner hero,
/// barra lateral de escritorio, pantalla de pedido confirmado); nunca como
/// fondo de una pantalla comun. Desde 2026-09 hay ademas un modo oscuro que
/// el usuario elige: misma jerarquia y mismo amarillo, sobre grises casi
/// negros. Los nombres siguen los roles de un `ColorScheme` de Material 3
/// para que toda la app (colores, botones, tarjetas, campos) se actualice
/// desde este unico archivo.

/// Una paleta completa: la del modo claro o la del oscuro.
///
/// Las pantallas no usan esta clase directamente: leen [MyColors], que
/// devuelve siempre la paleta del modo activo.
class MyPaleta {
  const MyPaleta({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.primaryFixed,
    required this.primaryFixedDim,
    required this.onPrimaryFixed,
    required this.onPrimaryFixedVariant,
    required this.inversePrimary,
    required this.surfaceTint,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.secondaryFixed,
    required this.secondaryFixedDim,
    required this.onSecondaryFixed,
    required this.onSecondaryFixedVariant,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.tertiaryFixed,
    required this.tertiaryFixedDim,
    required this.onTertiaryFixed,
    required this.onTertiaryFixedVariant,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.inverseSurface,
    required this.inverseOnSurface,
    required this.dock,
    required this.outline,
    required this.outlineVariant,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  final Brightness brightness;

  // --- Marca: amarillo ----------------------------------------------------
  /// Amarillo MODO YA. CTAs principales, iconos activos, circulos de rubro.
  final Color primary;

  /// Negro sobre amarillo: el amarillo puro no soporta texto blanco encima.
  final Color onPrimary;

  /// Negro de marca con tinte ambar: tarjetas hero / banner y CTA flotante
  /// del carrito. Encima va texto blanco y detalles amarillos.
  final Color primaryContainer;
  final Color onPrimaryContainer;

  /// Amarillo palido: relleno suave de paneles destacados, fila seleccionada,
  /// avisos ("info" de marca). Encima va texto oscuro.
  final Color primaryFixed;
  final Color primaryFixedDim;
  final Color onPrimaryFixed;
  final Color onPrimaryFixedVariant;
  final Color inversePrimary;
  final Color surfaceTint;

  // --- Secundario (gris neutro, sin tinte azul) ----------------------------
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color secondaryFixed;
  final Color secondaryFixedDim;
  final Color onSecondaryFixed;
  final Color onSecondaryFixedVariant;

  // --- Terciario (ambar calido para texto de precios) ----------------------
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color tertiaryFixed;
  final Color tertiaryFixedDim;
  final Color onTertiaryFixed;
  final Color onTertiaryFixedVariant;

  // --- Superficies ---------------------------------------------------------
  /// Fondo base de pantalla.
  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;

  /// Tarjetas; los "escalones" son para campos, chips y paneles secundarios.
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color onSurface;
  final Color onSurfaceVariant;

  /// Superficie invertida: snackbars, tooltips, chips seleccionados en
  /// "oscuro". Encima va [inverseOnSurface].
  final Color inverseSurface;
  final Color inverseOnSurface;

  /// Negro de marca: barra lateral de escritorio, splash, pantalla de pedido
  /// confirmado y pastillas "dark". Es negro en los dos modos.
  final Color dock;

  final Color outline;
  final Color outlineVariant;

  // --- Estado ------------------------------------------------------------
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;

  /// Verde de "conectado / disponible / entregado". Uso puntual, no
  /// reemplaza al amarillo como color de marca.
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  bool get esOscura => brightness == Brightness.dark;

  /// Modo claro: la identidad de marca. Fondo blanco puro, tarjetas blancas
  /// con borde suave, texto negro.
  static const clara = MyPaleta(
    brightness: Brightness.light,
    primary: Color(0xFFFFC800),
    onPrimary: Color(0xFF171200),
    primaryContainer: Color(0xFF17150C),
    onPrimaryContainer: Color(0xFFFFE9A6),
    primaryFixed: Color(0xFFFFF3C4),
    primaryFixedDim: Color(0xFFFFD84D),
    onPrimaryFixed: Color(0xFF3D2E00),
    onPrimaryFixedVariant: Color(0xFF6B5300),
    inversePrimary: Color(0xFFFFD84D),
    surfaceTint: Color(0xFFFFC800),
    secondary: Color(0xFF6B6B75),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF2F2F4),
    onSecondaryContainer: Color(0xFF2B2B30),
    secondaryFixed: Color(0xFFE6E6EA),
    secondaryFixedDim: Color(0xFFD8D8DE),
    onSecondaryFixed: Color(0xFF1F1F24),
    onSecondaryFixedVariant: Color(0xFF3F3F47),
    tertiary: Color(0xFF8A6100),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFE9A6),
    onTertiaryContainer: Color(0xFF4A3800),
    tertiaryFixed: Color(0xFFFFE9A6),
    tertiaryFixedDim: Color(0xFFFFD84D),
    onTertiaryFixed: Color(0xFF4A3800),
    onTertiaryFixedVariant: Color(0xFF6B5300),
    surface: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFFE6E6EA),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F7F9),
    surfaceContainer: Color(0xFFF1F1F4),
    surfaceContainerHigh: Color(0xFFE9E9ED),
    surfaceContainerHighest: Color(0xFFDEDEE3),
    onSurface: Color(0xFF141416),
    onSurfaceVariant: Color(0xFF5C5C66),
    inverseSurface: Color(0xFF1A1A1D),
    inverseOnSurface: Color(0xFFFFFFFF),
    dock: Color(0xFF141416),
    outline: Color(0xFF9A9AA3),
    outlineVariant: Color(0xFFE6E6EC),
    error: Color(0xFFC22C2C),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    success: Color(0xFF2E9E5B),
    successContainer: Color(0xFFD7F5E3),
    onSuccessContainer: Color(0xFF0C5138),
  );

  /// Modo oscuro: mismo amarillo y misma jerarquia sobre grises casi negros
  /// (no negro puro, para que las tarjetas hero y el dock sigan destacando).
  /// Los rellenos palidos pasan a ambar profundo, el texto secundario a gris
  /// claro y los precios al amarillo claro. Los inversos (snackbars,
  /// tooltips) quedan gris oscuro con texto blanco, asi el texto de las
  /// tarjetas hero, que usa [inverseOnSurface], sigue siendo blanco.
  static const oscura = MyPaleta(
    brightness: Brightness.dark,
    primary: Color(0xFFFFC800),
    onPrimary: Color(0xFF171200),
    primaryContainer: Color(0xFF1F1C10),
    onPrimaryContainer: Color(0xFFFFE9A6),
    primaryFixed: Color(0xFF3A2E00),
    primaryFixedDim: Color(0xFFFFD84D),
    onPrimaryFixed: Color(0xFFFFE9A6),
    onPrimaryFixedVariant: Color(0xFFFFD84D),
    inversePrimary: Color(0xFF8A6100),
    surfaceTint: Color(0xFFFFC800),
    secondary: Color(0xFFA7A7B1),
    onSecondary: Color(0xFF141416),
    secondaryContainer: Color(0xFF2A2A30),
    onSecondaryContainer: Color(0xFFE6E6EA),
    secondaryFixed: Color(0xFF2E2E34),
    secondaryFixedDim: Color(0xFF38383F),
    onSecondaryFixed: Color(0xFFECECF0),
    onSecondaryFixedVariant: Color(0xFFC4C4CC),
    tertiary: Color(0xFFFFD84D),
    onTertiary: Color(0xFF2B2000),
    tertiaryContainer: Color(0xFF4A3800),
    onTertiaryContainer: Color(0xFFFFE9A6),
    tertiaryFixed: Color(0xFF4A3800),
    tertiaryFixedDim: Color(0xFF6B5300),
    onTertiaryFixed: Color(0xFFFFE9A6),
    onTertiaryFixedVariant: Color(0xFFFFD84D),
    surface: Color(0xFF121214),
    surfaceDim: Color(0xFF0E0E10),
    surfaceBright: Color(0xFF2C2C32),
    surfaceContainerLowest: Color(0xFF1A1A1E),
    surfaceContainerLow: Color(0xFF1F1F24),
    surfaceContainer: Color(0xFF26262B),
    surfaceContainerHigh: Color(0xFF2E2E34),
    surfaceContainerHighest: Color(0xFF38383F),
    onSurface: Color(0xFFF4F4F6),
    onSurfaceVariant: Color(0xFFB6B6C0),
    inverseSurface: Color(0xFF2E2E34),
    inverseOnSurface: Color(0xFFFFFFFF),
    dock: Color(0xFF09090B),
    outline: Color(0xFF7A7A85),
    outlineVariant: Color(0xFF2F2F36),
    error: Color(0xFFFF6E6E),
    onError: Color(0xFF3A0000),
    errorContainer: Color(0xFF4E1A1A),
    onErrorContainer: Color(0xFFFFDAD6),
    success: Color(0xFF4FCB84),
    successContainer: Color(0xFF12361F),
    onSuccessContainer: Color(0xFFBDF2D0),
  );
}

/// Colores de MODO YA, siempre los del modo activo (claro u oscuro).
///
/// Se leen como `MyColors.primary`. Son getters, no constantes: no entran en
/// expresiones `const`. El cambio de modo lo hace [MyTema] (theme.dart), que
/// actualiza [paleta] y vuelve a dibujar toda la app.
abstract final class MyColors {
  /// La paleta activa. La cambia [MyTema]; el resto de la app solo la lee.
  static MyPaleta paleta = MyPaleta.clara;

  static bool get esOscuro => paleta.esOscura;

  // --- Marca: amarillo ----------------------------------------------------
  static Color get primary => paleta.primary;
  static Color get onPrimary => paleta.onPrimary;
  static Color get primaryContainer => paleta.primaryContainer;
  static Color get onPrimaryContainer => paleta.onPrimaryContainer;
  static Color get primaryFixed => paleta.primaryFixed;
  static Color get primaryFixedDim => paleta.primaryFixedDim;
  static Color get onPrimaryFixed => paleta.onPrimaryFixed;
  static Color get onPrimaryFixedVariant => paleta.onPrimaryFixedVariant;
  static Color get inversePrimary => paleta.inversePrimary;
  static Color get surfaceTint => paleta.surfaceTint;

  // --- Secundario ---------------------------------------------------------
  static Color get secondary => paleta.secondary;
  static Color get onSecondary => paleta.onSecondary;
  static Color get secondaryContainer => paleta.secondaryContainer;
  static Color get onSecondaryContainer => paleta.onSecondaryContainer;
  static Color get secondaryFixed => paleta.secondaryFixed;
  static Color get secondaryFixedDim => paleta.secondaryFixedDim;
  static Color get onSecondaryFixed => paleta.onSecondaryFixed;
  static Color get onSecondaryFixedVariant => paleta.onSecondaryFixedVariant;

  // --- Terciario ----------------------------------------------------------
  static Color get tertiary => paleta.tertiary;
  static Color get onTertiary => paleta.onTertiary;
  static Color get tertiaryContainer => paleta.tertiaryContainer;
  static Color get onTertiaryContainer => paleta.onTertiaryContainer;
  static Color get tertiaryFixed => paleta.tertiaryFixed;
  static Color get tertiaryFixedDim => paleta.tertiaryFixedDim;
  static Color get onTertiaryFixed => paleta.onTertiaryFixed;
  static Color get onTertiaryFixedVariant => paleta.onTertiaryFixedVariant;

  // --- Superficies --------------------------------------------------------
  static Color get surface => paleta.surface;
  static Color get surfaceDim => paleta.surfaceDim;
  static Color get surfaceBright => paleta.surfaceBright;
  static Color get surfaceContainerLowest => paleta.surfaceContainerLowest;
  static Color get surfaceContainerLow => paleta.surfaceContainerLow;
  static Color get surfaceContainer => paleta.surfaceContainer;
  static Color get surfaceContainerHigh => paleta.surfaceContainerHigh;
  static Color get surfaceContainerHighest => paleta.surfaceContainerHighest;
  static Color get surfaceVariant => paleta.surfaceContainerHighest;
  static Color get onSurface => paleta.onSurface;
  static Color get onSurfaceVariant => paleta.onSurfaceVariant;
  static Color get inverseSurface => paleta.inverseSurface;
  static Color get inverseOnSurface => paleta.inverseOnSurface;
  static Color get dock => paleta.dock;
  static Color get outline => paleta.outline;
  static Color get outlineVariant => paleta.outlineVariant;

  // --- Estado -------------------------------------------------------------
  static Color get error => paleta.error;
  static Color get onError => paleta.onError;
  static Color get errorContainer => paleta.errorContainer;
  static Color get onErrorContainer => paleta.onErrorContainer;
  static Color get success => paleta.success;
  static Color get successContainer => paleta.successContainer;
  static Color get onSuccessContainer => paleta.onSuccessContainer;

  // --- Alias "claro" -------------------------------------------------------
  //
  // El flujo de pedidos (carrito, direcciones, seguimiento) se escribio
  // cuando el tema claro era la excepcion y referencia estos nombres. Hoy son
  // los mismos tonos que el resto de la app.
  static Color get claroFondo => surface;
  static Color get claroSuperficie => surfaceContainerLowest;
  static Color get claroSuperficieAlt => surfaceContainerLow;
  static Color get claroBorde => outlineVariant;
  static Color get claroTexto => onSurface;
  static Color get claroTextoSecundario => onSurfaceVariant;

  /// Amarillo de marca oscurecido para texto sobre blanco: el amarillo puro
  /// no tiene contraste suficiente para leerse (precios, montos).
  static Color get claroAcento => tertiary;

  static Color get claroError => error;
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

/// Sombras. Sobre fondo blanco alcanza con sombras muy suaves: una tarjeta
/// blanca "flota" con apenas un 6-10% de negro difuso.
abstract final class MyShadows {
  /// Nivel 1 - tarjeta sobre el lienzo blanco.
  static const card = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 6),
      spreadRadius: -4,
    ),
  ];

  /// Nivel 2 - tarjeta hero negra, con brillo amarillo de marca.
  static const hero = <BoxShadow>[
    BoxShadow(
      color: Color(0x33FFC800),
      blurRadius: 28,
      offset: Offset(0, 12),
      spreadRadius: -8,
    ),
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 24,
      offset: Offset(0, 10),
      spreadRadius: -6,
    ),
  ];

  /// Nivel 3 - dock de navegacion flotante.
  static const dock = <BoxShadow>[
    BoxShadow(
      color: Color(0x24000000),
      blurRadius: 32,
      offset: Offset(0, 12),
      spreadRadius: -6,
    ),
  ];

  /// Controles chicos: botones circulares, badges, contadores.
  static const control = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Sombra muy sutil de los chips y pastillas.
  static const subtle = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F000000),
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
  ];

  /// Brillo amarillo para el elemento activo (rubro elegido, CTA).
  static const glow = <BoxShadow>[
    BoxShadow(
      color: Color(0x59FFC800),
      blurRadius: 18,
      offset: Offset(0, 6),
      spreadRadius: -2,
    ),
  ];
}
