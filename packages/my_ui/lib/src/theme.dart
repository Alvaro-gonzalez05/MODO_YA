import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Tema Material 3 armado sobre los tokens de MODO YA.
abstract final class MyTheme {
  static const ColorScheme colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: MyColors.primary,
    onPrimary: MyColors.onPrimary,
    primaryContainer: MyColors.primaryContainer,
    onPrimaryContainer: MyColors.onPrimaryContainer,
    primaryFixed: MyColors.primaryFixed,
    primaryFixedDim: MyColors.primaryFixedDim,
    onPrimaryFixed: MyColors.onPrimaryFixed,
    onPrimaryFixedVariant: MyColors.onPrimaryFixedVariant,
    secondary: MyColors.secondary,
    onSecondary: MyColors.onSecondary,
    secondaryContainer: MyColors.secondaryContainer,
    onSecondaryContainer: MyColors.onSecondaryContainer,
    secondaryFixed: MyColors.secondaryFixed,
    secondaryFixedDim: MyColors.secondaryFixedDim,
    onSecondaryFixed: MyColors.onSecondaryFixed,
    onSecondaryFixedVariant: MyColors.onSecondaryFixedVariant,
    tertiary: MyColors.tertiary,
    onTertiary: MyColors.onTertiary,
    tertiaryContainer: MyColors.tertiaryContainer,
    onTertiaryContainer: MyColors.onTertiaryContainer,
    tertiaryFixed: MyColors.tertiaryFixed,
    tertiaryFixedDim: MyColors.tertiaryFixedDim,
    onTertiaryFixed: MyColors.onTertiaryFixed,
    onTertiaryFixedVariant: MyColors.onTertiaryFixedVariant,
    error: MyColors.error,
    onError: MyColors.onError,
    errorContainer: MyColors.errorContainer,
    onErrorContainer: MyColors.onErrorContainer,
    surface: MyColors.surface,
    onSurface: MyColors.onSurface,
    surfaceDim: MyColors.surfaceDim,
    surfaceBright: MyColors.surfaceBright,
    surfaceContainerLowest: MyColors.surfaceContainerLowest,
    surfaceContainerLow: MyColors.surfaceContainerLow,
    surfaceContainer: MyColors.surfaceContainer,
    surfaceContainerHigh: MyColors.surfaceContainerHigh,
    surfaceContainerHighest: MyColors.surfaceContainerHighest,
    onSurfaceVariant: MyColors.onSurfaceVariant,
    outline: MyColors.outline,
    outlineVariant: MyColors.outlineVariant,
    inverseSurface: MyColors.inverseSurface,
    onInverseSurface: MyColors.inverseOnSurface,
    inversePrimary: MyColors.inversePrimary,
    surfaceTint: MyColors.surfaceTint,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: MyColors.surface,
        textTheme: MyType.textTheme,
        splashFactory: InkSparkle.splashFactory,

        appBarTheme: AppBarTheme(
          backgroundColor: MyColors.surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: MyColors.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: MyType.headlineSm,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),

        // El CTA del sistema: pastilla completa, 54 de alto.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: MyColors.primary,
            foregroundColor: MyColors.onPrimary,
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: const StadiumBorder(),
            textStyle: MyType.headlineSm,
            elevation: 0,
          ),
        ),

        // Accion secundaria: misma silueta, relleno azul suave.
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: MyColors.onSurface,
            backgroundColor: MyColors.secondaryContainer,
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: const StadiumBorder(),
            side: BorderSide.none,
            textStyle: MyType.headlineSm,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: MyColors.primary,
            textStyle: MyType.labelLg,
          ),
        ),

        cardTheme: CardThemeData(
          color: MyColors.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MyRadius.card),
            side: const BorderSide(color: MyColors.outlineVariant),
          ),
        ),

        // Relleno celeste con borde suave: los campos van casi siempre sobre
        // tarjetas blancas, y blanco sobre blanco no se ve donde escribir.
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MyColors.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.md,
          ),
          hintStyle: MyType.bodyMd.copyWith(color: MyColors.secondary),
          labelStyle: MyType.labelMd.copyWith(color: MyColors.secondary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: const BorderSide(color: MyColors.surfaceContainerHigh),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: const BorderSide(color: MyColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: const BorderSide(color: MyColors.error, width: 1.5),
          ),
        ),

        chipTheme: ChipThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          selectedColor: MyColors.dock,
          labelStyle: MyType.labelLg,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.sm,
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: MyColors.surfaceContainerHigh,
          thickness: 1,
          space: 1,
        ),

        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(MyRadius.hero),
            ),
          ),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: MyColors.primary,
          linearTrackColor: MyColors.surfaceContainerHigh,
          circularTrackColor: MyColors.surfaceContainerHigh,
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? MyColors.onPrimary
                : MyColors.surfaceContainerLowest,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? MyColors.primary
                : MyColors.surfaceContainerHighest,
          ),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      );

  // --- Variante clara: flujo de pedidos (carrito, direcciones, seguimiento) -
  static const ColorScheme colorSchemeClaro = ColorScheme(
    brightness: Brightness.light,
    primary: MyColors.primary,
    onPrimary: MyColors.onPrimary,
    primaryContainer: Color(0xFFFFF3D1),
    onPrimaryContainer: Color(0xFF4A3800),
    primaryFixed: MyColors.primaryFixed,
    primaryFixedDim: MyColors.primaryFixedDim,
    onPrimaryFixed: MyColors.onPrimaryFixed,
    onPrimaryFixedVariant: MyColors.onPrimaryFixedVariant,
    secondary: Color(0xFF545F73),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE9EDF5),
    onSecondaryContainer: Color(0xFF313B4C),
    secondaryFixed: MyColors.secondaryFixed,
    secondaryFixedDim: MyColors.secondaryFixedDim,
    onSecondaryFixed: MyColors.onSecondaryFixed,
    onSecondaryFixedVariant: MyColors.onSecondaryFixedVariant,
    tertiary: Color(0xFF8A5300),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFE4B8),
    onTertiaryContainer: Color(0xFF4A2E00),
    tertiaryFixed: MyColors.tertiaryFixed,
    tertiaryFixedDim: MyColors.tertiaryFixedDim,
    onTertiaryFixed: MyColors.onTertiaryFixed,
    onTertiaryFixedVariant: MyColors.onTertiaryFixedVariant,
    error: MyColors.claroError,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: MyColors.claroFondo,
    onSurface: MyColors.claroTexto,
    surfaceDim: Color(0xFFE2E2E6),
    surfaceBright: MyColors.claroSuperficie,
    surfaceContainerLowest: MyColors.claroSuperficie,
    surfaceContainerLow: MyColors.claroSuperficieAlt,
    surfaceContainer: Color(0xFFECECEF),
    surfaceContainerHigh: Color(0xFFE3E3E8),
    surfaceContainerHighest: Color(0xFFD8D8DE),
    onSurfaceVariant: MyColors.claroTextoSecundario,
    outline: Color(0xFF9A9AA3),
    outlineVariant: MyColors.claroBorde,
    inverseSurface: Color(0xFF1A1A1D),
    onInverseSurface: Color(0xFFFFFFFF),
    inversePrimary: MyColors.inversePrimary,
    surfaceTint: MyColors.surfaceTint,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  /// Tema claro para el flujo de pedidos (carrito, direcciones, seguimiento).
  /// [dark] (el tema por defecto de toda la app) ya usa los mismos tonos
  /// blancos -- ver [tokens.dart] -- asi que esta variante quedo casi
  /// idéntica; se mantiene separada porque esas pantallas la referencian
  /// explicitamente por nombre (`claroFondo`, `claroTexto`, etc).
  static ThemeData get claro => ThemeData(
        useMaterial3: true,
        colorScheme: colorSchemeClaro,
        scaffoldBackgroundColor: MyColors.claroFondo,
        textTheme: MyType.textTheme,
        splashFactory: InkSparkle.splashFactory,

        appBarTheme: AppBarTheme(
          backgroundColor: MyColors.claroFondo,
          surfaceTintColor: Colors.transparent,
          foregroundColor: MyColors.claroTexto,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: MyType.headlineSm,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: MyColors.primary,
            foregroundColor: MyColors.onPrimary,
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: const StadiumBorder(),
            textStyle: MyType.headlineSm,
            elevation: 0,
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: MyColors.claroTexto,
            backgroundColor: MyColors.claroSuperficieAlt,
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: const StadiumBorder(),
            side: BorderSide.none,
            textStyle: MyType.headlineSm,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: MyColors.claroAcento,
            textStyle: MyType.labelLg,
          ),
        ),

        cardTheme: CardThemeData(
          color: MyColors.claroSuperficie,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MyRadius.card),
            side: const BorderSide(color: MyColors.claroBorde),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MyColors.claroSuperficieAlt,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.md,
          ),
          hintStyle: MyType.bodyMd.copyWith(color: MyColors.claroTextoSecundario),
          labelStyle: MyType.labelMd.copyWith(color: MyColors.claroTextoSecundario),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: const BorderSide(color: MyColors.claroBorde),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: const BorderSide(color: MyColors.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(MyRadius.lg),
            borderSide: const BorderSide(color: MyColors.claroError, width: 1.5),
          ),
        ),

        chipTheme: ChipThemeData(
          backgroundColor: MyColors.claroSuperficieAlt,
          selectedColor: MyColors.primary,
          labelStyle: MyType.labelLg,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.sm,
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: MyColors.claroBorde,
          thickness: 1,
          space: 1,
        ),

        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: MyColors.claroSuperficie,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(MyRadius.hero),
            ),
          ),
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: MyColors.primary,
          linearTrackColor: MyColors.claroBorde,
          circularTrackColor: MyColors.claroBorde,
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.onPrimary : MyColors.claroSuperficie,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.primary : Color(0xFFD8D8DE),
          ),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      );
}

/// Envuelve una pantalla del flujo de pedidos (carrito, direcciones,
/// seguimiento) en el tema claro. Hoy es el mismo blanco que el resto de la
/// app por defecto; queda igual por si ese flujo necesita volver a divergir.
class MyPantallaClara extends StatelessWidget {
  const MyPantallaClara({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MyColors.claroFondo,
      child: Theme(data: MyTheme.claro, child: child),
    );
  }
}
