import 'package:flutter/material.dart';

/// Tokens de diseno de MODO YA.
///
/// Identidad de marca: **fondo blanco, acento amarillo, texto negro**. El
/// negro se usa solo como superficie fuerte y puntual (splash, banner hero,
/// barra lateral de escritorio, pantalla de pedido confirmado); nunca como
/// fondo de una pantalla comun. Los nombres siguen los roles de un
/// `ColorScheme` de Material 3 para que toda la app (colores, botones,
/// tarjetas, campos) se actualice desde este unico archivo.
abstract final class MyColors {
  // --- Marca: amarillo ----------------------------------------------------
  /// Amarillo MODO YA. CTAs principales, iconos activos, circulos de rubro.
  static const primary = Color(0xFFFFC800);

  /// Negro sobre amarillo: el amarillo puro no soporta texto blanco encima.
  static const onPrimary = Color(0xFF171200);

  /// Negro de marca con tinte ambar: tarjetas hero / banner y CTA flotante
  /// del carrito. Encima va texto blanco y detalles amarillos.
  static const primaryContainer = Color(0xFF17150C);
  static const onPrimaryContainer = Color(0xFFFFE9A6);

  /// Amarillo palido: relleno suave de paneles destacados, fila seleccionada,
  /// avisos ("info" de marca). Encima va texto oscuro.
  static const primaryFixed = Color(0xFFFFF3C4);
  static const primaryFixedDim = Color(0xFFFFD84D);
  static const onPrimaryFixed = Color(0xFF3D2E00);
  static const onPrimaryFixedVariant = Color(0xFF6B5300);
  static const inversePrimary = Color(0xFFFFD84D);
  static const surfaceTint = Color(0xFFFFC800);

  // --- Secundario (gris neutro, sin tinte azul) ----------------------------
  static const secondary = Color(0xFF6B6B75);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFF2F2F4);
  static const onSecondaryContainer = Color(0xFF2B2B30);
  static const secondaryFixed = Color(0xFFE6E6EA);
  static const secondaryFixedDim = Color(0xFFD8D8DE);
  static const onSecondaryFixed = Color(0xFF1F1F24);
  static const onSecondaryFixedVariant = Color(0xFF3F3F47);

  // --- Terciario (ambar calido para texto de precios sobre blanco) --------
  static const tertiary = Color(0xFF8A6100);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFFFE9A6);
  static const onTertiaryContainer = Color(0xFF4A3800);
  static const tertiaryFixed = Color(0xFFFFE9A6);
  static const tertiaryFixedDim = Color(0xFFFFD84D);
  static const onTertiaryFixed = Color(0xFF4A3800);
  static const onTertiaryFixedVariant = Color(0xFF6B5300);

  // --- Superficies ---------------------------------------------------------
  /// Fondo base de pantalla: blanco puro.
  static const surface = Color(0xFFFFFFFF);
  static const surfaceDim = Color(0xFFE6E6EA);
  static const surfaceBright = Color(0xFFFFFFFF);

  /// Tarjetas: blanco con borde suave; los "escalones" son grises muy claros
  /// para campos, chips y paneles secundarios.
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF7F7F9);
  static const surfaceContainer = Color(0xFFF1F1F4);
  static const surfaceContainerHigh = Color(0xFFE9E9ED);
  static const surfaceContainerHighest = Color(0xFFDEDEE3);
  static const surfaceVariant = Color(0xFFDEDEE3);
  static const onSurface = Color(0xFF141416);
  static const onSurfaceVariant = Color(0xFF5C5C66);

  /// Superficie invertida (negra): snackbars, tooltips, chips seleccionados
  /// en "oscuro".
  static const inverseSurface = Color(0xFF1A1A1D);
  static const inverseOnSurface = Color(0xFFFFFFFF);

  /// Negro de marca: barra lateral de escritorio, splash, pantalla de pedido
  /// confirmado y pastillas "dark".
  static const dock = Color(0xFF141416);

  static const outline = Color(0xFF9A9AA3);
  static const outlineVariant = Color(0xFFE6E6EC);

  // --- Estado ------------------------------------------------------------
  static const error = Color(0xFFC22C2C);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF410002);

  /// Verde de "conectado / disponible / entregado". Uso puntual, no
  /// reemplaza al amarillo como color de marca.
  static const success = Color(0xFF2E9E5B);
  static const successContainer = Color(0xFFD7F5E3);
  static const onSuccessContainer = Color(0xFF0C5138);

  // --- Alias "claro" -------------------------------------------------------
  //
  // El flujo de pedidos (carrito, direcciones, seguimiento) se escribio
  // cuando el tema claro era la excepcion y referencia estos nombres. Hoy son
  // los mismos tonos que el resto de la app.
  static const claroFondo = surface;
  static const claroSuperficie = surfaceContainerLowest;
  static const claroSuperficieAlt = surfaceContainerLow;
  static const claroBorde = outlineVariant;
  static const claroTexto = onSurface;
  static const claroTextoSecundario = onSurfaceVariant;

  /// Amarillo de marca oscurecido para texto sobre blanco: el amarillo puro
  /// no tiene contraste suficiente para leerse (precios, montos).
  static const claroAcento = tertiary;

  static const claroError = error;
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
