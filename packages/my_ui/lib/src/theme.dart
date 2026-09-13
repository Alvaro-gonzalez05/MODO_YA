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

  static ThemeData get light => ThemeData(
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
          ),
        ),

        // Campos sin borde visible: el relleno claro define la caja.
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MyColors.surfaceContainerLowest,
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
            borderSide: BorderSide.none,
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
}
