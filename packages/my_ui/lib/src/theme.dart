import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'typography.dart';

/// Tema Material 3 armado sobre los tokens de MODO YA: blanco, amarillo y
/// negro en todos los widgets estandar (botones, campos, dialogos, chips,
/// selectores, snackbars) para que cualquier pantalla, incluso las que usan
/// widgets de Material sin estilo propio, salga con la identidad de marca.
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

  static OutlineInputBorder _borde(Color color, {double ancho = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(MyRadius.lg),
        borderSide: BorderSide(color: color, width: ancho),
      );

  /// El tema de toda la app. El nombre `dark` quedo de la primera version
  /// (negra); hoy es el tema blanco de marca y es el unico que hay.
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: MyColors.surface,
        canvasColor: MyColors.surface,
        textTheme: MyType.textTheme,
        splashFactory: InkSparkle.splashFactory,
        splashColor: MyColors.primary.withValues(alpha: 0.18),
        highlightColor: MyColors.primary.withValues(alpha: 0.08),
        hoverColor: MyColors.primary.withValues(alpha: 0.06),
        focusColor: MyColors.primary.withValues(alpha: 0.14),
        dividerColor: MyColors.outlineVariant,
        iconTheme: const IconThemeData(color: MyColors.onSurface),

        // Transiciones entre pantallas: fundido + deslizamiento corto en todas
        // las plataformas, en vez del zoom de Android o el corte seco de la PC.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _TransicionModoYa(),
            TargetPlatform.iOS: _TransicionModoYa(),
            TargetPlatform.windows: _TransicionModoYa(),
            TargetPlatform.macOS: _TransicionModoYa(),
            TargetPlatform.linux: _TransicionModoYa(),
            TargetPlatform.fuchsia: _TransicionModoYa(),
          },
        ),

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

        // El CTA del sistema: pastilla amarilla completa, 54 de alto.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: MyColors.primary,
            foregroundColor: MyColors.onPrimary,
            disabledBackgroundColor: MyColors.surfaceContainerHigh,
            disabledForegroundColor: MyColors.outline,
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: const StadiumBorder(),
            textStyle: MyType.headlineSm,
            elevation: 0,
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(MyColors.onPrimary.withValues(alpha: 0.08)),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: MyColors.primary,
            foregroundColor: MyColors.onPrimary,
            minimumSize: const Size.fromHeight(54),
            shape: const StadiumBorder(),
            textStyle: MyType.headlineSm,
            elevation: 0,
          ),
        ),

        // Accion secundaria: misma silueta, blanca con borde negro fino.
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: MyColors.onSurface,
            backgroundColor: MyColors.surfaceContainerLowest,
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: const StadiumBorder(),
            side: const BorderSide(color: MyColors.onSurface, width: 1.4),
            textStyle: MyType.headlineSm,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: MyColors.onSurface,
            textStyle: MyType.labelLg,
            shape: const StadiumBorder(),
          ),
        ),

        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: MyColors.onSurface,
            highlightColor: MyColors.primary.withValues(alpha: 0.18),
          ),
        ),

        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: MyColors.primary,
          foregroundColor: MyColors.onPrimary,
          elevation: 4,
          shape: StadiumBorder(),
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

        // Campos: relleno gris muy claro con borde suave; al enfocar, borde
        // amarillo como en la referencia.
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MyColors.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.md,
          ),
          hintStyle: MyType.bodyMd.copyWith(color: MyColors.secondary),
          labelStyle: MyType.labelMd.copyWith(color: MyColors.secondary),
          floatingLabelStyle: MyType.labelMd.copyWith(color: MyColors.onPrimaryFixedVariant),
          prefixIconColor: MyColors.secondary,
          suffixIconColor: MyColors.secondary,
          border: _borde(MyColors.outlineVariant),
          enabledBorder: _borde(MyColors.outlineVariant),
          focusedBorder: _borde(MyColors.primary, ancho: 2),
          errorBorder: _borde(MyColors.error, ancho: 1.5),
          focusedErrorBorder: _borde(MyColors.error, ancho: 2),
          disabledBorder: _borde(MyColors.surfaceContainerHigh),
        ),

        chipTheme: ChipThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          selectedColor: MyColors.primary,
          secondarySelectedColor: MyColors.primary,
          checkmarkColor: MyColors.onPrimary,
          labelStyle: MyType.labelLg,
          secondaryLabelStyle: MyType.labelLg.copyWith(color: MyColors.onPrimary),
          side: const BorderSide(color: MyColors.outlineVariant),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.sm,
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: MyColors.outlineVariant,
          thickness: 1,
          space: 1,
        ),

        listTileTheme: ListTileThemeData(
          iconColor: MyColors.onSurfaceVariant,
          textColor: MyColors.onSurface,
          selectedColor: MyColors.onPrimaryFixed,
          selectedTileColor: MyColors.primaryFixed,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.md)),
        ),

        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: MyColors.surfaceContainerLowest,
          dragHandleColor: MyColors.surfaceContainerHighest,
          showDragHandle: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(MyRadius.hero),
            ),
          ),
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
          titleTextStyle: MyType.headlineMd.copyWith(color: MyColors.onSurface),
          contentTextStyle: MyType.bodyMd.copyWith(color: MyColors.onSurfaceVariant),
          actionsPadding: const EdgeInsets.fromLTRB(MySpacing.lg, 0, MySpacing.lg, MySpacing.lg),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: MyColors.inverseSurface,
          contentTextStyle: MyType.bodyMd.copyWith(color: MyColors.inverseOnSurface),
          actionTextColor: MyColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
          elevation: 6,
        ),

        popupMenuTheme: PopupMenuThemeData(
          color: MyColors.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
          textStyle: MyType.labelLg,
        ),

        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(MyColors.surfaceContainerLowest),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            elevation: const WidgetStatePropertyAll(8),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
            ),
          ),
        ),

        dropdownMenuTheme: DropdownMenuThemeData(
          textStyle: MyType.bodyMd,
          menuStyle: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(MyColors.surfaceContainerLowest),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
            ),
          ),
        ),

        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: MyColors.inverseSurface,
            borderRadius: BorderRadius.circular(MyRadius.md),
          ),
          textStyle: MyType.bodySm.copyWith(color: MyColors.inverseOnSurface),
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

        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.primary : Colors.transparent,
          ),
          checkColor: const WidgetStatePropertyAll(MyColors.onPrimary),
          side: const BorderSide(color: MyColors.outline, width: 1.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),

        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.primary : MyColors.outline,
          ),
        ),

        sliderTheme: const SliderThemeData(
          activeTrackColor: MyColors.primary,
          inactiveTrackColor: MyColors.surfaceContainerHigh,
          thumbColor: MyColors.primary,
          overlayColor: Color(0x29FFC800),
        ),

        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            backgroundColor: MyColors.surfaceContainerLowest,
            foregroundColor: MyColors.onSurfaceVariant,
            selectedBackgroundColor: MyColors.primary,
            selectedForegroundColor: MyColors.onPrimary,
            side: const BorderSide(color: MyColors.outlineVariant),
            textStyle: MyType.labelLg,
          ),
        ),

        tabBarTheme: TabBarThemeData(
          labelColor: MyColors.onSurface,
          unselectedLabelColor: MyColors.secondary,
          indicatorColor: MyColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: MyColors.outlineVariant,
          labelStyle: MyType.labelLg,
          unselectedLabelStyle: MyType.labelLg,
        ),

        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          indicatorColor: MyColors.primary,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? MyColors.onPrimary : MyColors.secondary,
            ),
          ),
          labelTextStyle: WidgetStatePropertyAll(MyType.labelMd),
        ),

        datePickerTheme: DatePickerThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: MyColors.dock,
          headerForegroundColor: MyColors.inverseOnSurface,
          dayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.primary : null,
          ),
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.onPrimary : MyColors.onSurface,
          ),
          todayBorder: const BorderSide(color: MyColors.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
        ),

        timePickerTheme: TimePickerThemeData(
          backgroundColor: MyColors.surfaceContainerLowest,
          dialBackgroundColor: MyColors.surfaceContainerLow,
          dialHandColor: MyColors.primary,
          hourMinuteColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.primaryFixed : MyColors.surfaceContainerLow,
          ),
          hourMinuteTextColor: MyColors.onSurface,
          dayPeriodColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? MyColors.primary : MyColors.surfaceContainerLow,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
        ),

        badgeTheme: const BadgeThemeData(
          backgroundColor: MyColors.error,
          textColor: MyColors.onError,
        ),

        textSelectionTheme: TextSelectionThemeData(
          cursorColor: MyColors.onSurface,
          selectionColor: MyColors.primary.withValues(alpha: 0.35),
          selectionHandleColor: MyColors.primary,
        ),

        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(MyColors.onSurface.withValues(alpha: 0.25)),
          radius: const Radius.circular(MyRadius.full),
        ),
      );

  /// Alias historico del flujo de pedidos (carrito, direcciones, seguimiento).
  /// Es el mismo tema: toda la app es blanca.
  static ThemeData get claro => dark;

  static const ColorScheme colorSchemeClaro = colorScheme;
}

/// Transicion de pantalla de MODO YA: la nueva pantalla entra con un fundido
/// y un deslizamiento corto desde abajo; la anterior se atenua apenas.
class _TransicionModoYa extends PageTransitionsBuilder {
  const _TransicionModoYa();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entrada = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final salida = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: entrada,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(entrada),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.85).animate(salida),
          child: child,
        ),
      ),
    );
  }
}

/// Envuelve una pantalla del flujo de pedidos (carrito, direcciones,
/// seguimiento). Quedo de cuando ese flujo tenia un tema distinto; hoy es el
/// mismo blanco que el resto de la app y solo garantiza el fondo.
class MyPantallaClara extends StatelessWidget {
  const MyPantallaClara({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: MyColors.surface, child: child);
  }
}
