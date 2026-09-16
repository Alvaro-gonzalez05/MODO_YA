import 'package:flutter/material.dart';

/// Tokens de diseno de MODO YA.
///
/// Identidad de marca: fondo blanco, acento amarillo, texto negro, con el
/// negro tambien usado a proposito como superficie fuerte en algunos acentos
/// (dock de navegacion, barra lateral, tarjetas hero, CTA flotante). Los
/// nombres de los tokens siguen los roles de un `ColorScheme` de Material 3
/// para que toda la app (colores, botones, tarjetas, campos) se actualice
/// desde este unico archivo.
abstract final class MyColors {
  // --- Marca: amarillo ----------------------------------------------------
  /// Amarillo MODO YA. CTAs principales, iconos activos, precios destacados.
  static const primary = Color(0xFFFFC800);
  static const onPrimary = Color(0xFF171200);

  /// Relleno oscuro con tinte ambar: tarjetas hero, CTA flotante del carrito,
  /// pastillas sobre el dock/barra lateral. A proposito se mantiene oscuro
  /// (con texto blanco encima) como acento "negro" de marca, aunque el resto
  /// de la app pasó a fondo blanco.
  static const primaryContainer = Color(0xFF2E2610);
  static const onPrimaryContainer = Color(0xFFFFE9A6);

  static const primaryFixed = Color(0xFF473A12);
  static const primaryFixedDim = Color(0xFF6B5818);
  static const onPrimaryFixed = Color(0xFFFFF3D1);
  static const onPrimaryFixedVariant = Color(0xFFFFE9A6);
  static const inversePrimary = Color(0xFF7A5B00);
  static const surfaceTint = Color(0xFFFFC800);

  // --- Secundario (gris pizarra sobre blanco) ------------------------------
  static const secondary = Color(0xFF545F73);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFE9EDF5);
  static const onSecondaryContainer = Color(0xFF313B4C);
  static const secondaryFixed = Color(0xFF3A4152);
  static const secondaryFixedDim = Color(0xFF232733);
  static const onSecondaryFixed = Color(0xFFE6EAF3);
  static const onSecondaryFixedVariant = Color(0xFFC3CADA);

  // --- Terciario (ambar calido, acento secundario) ------------------------
  static const tertiary = Color(0xFF8A5300);
  static const onTertiary = Color(0xFFFFFFFF);
  static const tertiaryContainer = Color(0xFFFFE4B8);
  static const onTertiaryContainer = Color(0xFF4A2E00);
  static const tertiaryFixed = Color(0xFF4A2E00);
  static const tertiaryFixedDim = Color(0xFF6B4300);
  static const onTertiaryFixed = Color(0xFFFFE8CC);
  static const onTertiaryFixedVariant = Color(0xFFFFCE94);

  // --- Superficies ---------------------------------------------------------
  /// Fondo base de pantalla: blanco MODO YA (con el amarillo y el negro como
  /// acentos, nunca como fondo de pantalla completo).
  static const surface = Color(0xFFFAFAFB);
  static const surfaceDim = Color(0xFFE2E2E6);
  static const surfaceBright = Color(0xFFFFFFFF);

  /// Tarjetas: blanco puro, un escalon mas claro que el fondo para que "floten".
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF1F1F4);
  static const surfaceContainer = Color(0xFFECECEF);
  static const surfaceContainerHigh = Color(0xFFE3E3E8);
  static const surfaceContainerHighest = Color(0xFFD8D8DE);
  static const surfaceVariant = Color(0xFFD8D8DE);
  static const onSurface = Color(0xFF17171A);
  static const onSurfaceVariant = Color(0xFF5B6472);

  /// Superficie "invertida" (oscura), para snackbars/tooltips y botones
  /// blancos dentro de paneles oscuros (hero, CTA flotante).
  static const inverseSurface = Color(0xFFEDEDF0);
  static const inverseOnSurface = Color(0xFF1A1A1D);

  /// Dock de navegacion flotante y barra lateral: negro de marca, a proposito
  /// distinguible del fondo blanco del resto de la app.
  static const dock = Color(0xFF141416);

  static const outline = Color(0xFF9A9AA3);
  static const outlineVariant = Color(0xFFE6E6EC);

  // --- Estado ------------------------------------------------------------
  static const error = Color(0xFFC22C2C);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF410002);

  /// Verde de "conectado / disponible". Uso puntual (estado de conexion del
  /// repartidor), no reemplaza al amarillo como color de marca.
  static const success = Color(0xFF2E9E5B);
  static const successContainer = Color(0xFFD7F5E3);

  // --- Variante clara (flujo de pedidos: carrito, direcciones, seguimiento) --
  //
  // Estos nombres quedaron de cuando esta variante clara era la excepcion
  // (el resto de la app era negra). Ahora toda la app es blanca por default
  // -- ver el bloque de "Superficies" arriba -- pero el carrito, checkout y
  // seguimiento siguen envueltos en `MyPantallaClara` explicitamente porque
  // usan estos nombres `claro*` en vez de los `MyColors.on*`/`surface*` del
  // tema ambiente. No hace falta tocarlos: ya son los mismos tonos.
  static const claroFondo = Color(0xFFFAFAFB);
  static const claroSuperficie = Color(0xFFFFFFFF);
  static const claroSuperficieAlt = Color(0xFFF1F1F4);
  static const claroBorde = Color(0xFFE6E6EC);
  static const claroTexto = Color(0xFF17171A);
  static const claroTextoSecundario = Color(0xFF5B6472);

  /// Amarillo de marca oscurecido para texto sobre blanco: el amarillo puro
  /// no tiene contraste suficiente para leerse (precios, montos).
  static const claroAcento = Color(0xFF8A6100);

  /// Rojo de error oscurecido para texto sobre blanco, mismo motivo.
  static const claroError = Color(0xFFC22C2C);
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
