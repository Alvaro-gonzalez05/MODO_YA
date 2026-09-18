import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';
import 'typography.dart';

/// Tema Material 3 armado sobre los tokens de MODO YA: blanco, amarillo y
/// negro en todos los widgets estandar (botones, campos, dialogos, chips,
/// selectores, snackbars) para que cualquier pantalla, incluso las que usan
/// widgets de Material sin estilo propio, salga con la identidad de marca.
abstract final class MyTheme {
  /// El `ColorScheme` de Material armado con una paleta.
  static ColorScheme esquema(MyPaleta p) => ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    primaryFixed: p.primaryFixed,
    primaryFixedDim: p.primaryFixedDim,
    onPrimaryFixed: p.onPrimaryFixed,
    onPrimaryFixedVariant: p.onPrimaryFixedVariant,
    secondary: p.secondary,
    onSecondary: p.onSecondary,
    secondaryContainer: p.secondaryContainer,
    onSecondaryContainer: p.onSecondaryContainer,
    secondaryFixed: p.secondaryFixed,
    secondaryFixedDim: p.secondaryFixedDim,
    onSecondaryFixed: p.onSecondaryFixed,
    onSecondaryFixedVariant: p.onSecondaryFixedVariant,
    tertiary: p.tertiary,
    onTertiary: p.onTertiary,
    tertiaryContainer: p.tertiaryContainer,
    onTertiaryContainer: p.onTertiaryContainer,
    tertiaryFixed: p.tertiaryFixed,
    tertiaryFixedDim: p.tertiaryFixedDim,
    onTertiaryFixed: p.onTertiaryFixed,
    onTertiaryFixedVariant: p.onTertiaryFixedVariant,
    error: p.error,
    onError: p.onError,
    errorContainer: p.errorContainer,
    onErrorContainer: p.onErrorContainer,
    surface: p.surface,
    onSurface: p.onSurface,
    surfaceDim: p.surfaceDim,
    surfaceBright: p.surfaceBright,
    surfaceContainerLowest: p.surfaceContainerLowest,
    surfaceContainerLow: p.surfaceContainerLow,
    surfaceContainer: p.surfaceContainer,
    surfaceContainerHigh: p.surfaceContainerHigh,
    surfaceContainerHighest: p.surfaceContainerHighest,
    onSurfaceVariant: p.onSurfaceVariant,
    outline: p.outline,
    outlineVariant: p.outlineVariant,
    inverseSurface: p.inverseSurface,
    onInverseSurface: p.inverseOnSurface,
    inversePrimary: p.inversePrimary,
    surfaceTint: p.surfaceTint,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
  );

  static OutlineInputBorder _borde(Color color, {double ancho = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(MyRadius.lg),
        borderSide: BorderSide(color: color, width: ancho),
      );

  /// Tema del modo claro: el de la marca (blanco, amarillo, negro).
  static ThemeData get claro => _construir(MyPaleta.clara);

  /// Tema del modo oscuro: grises casi negros con el mismo amarillo.
  static ThemeData get oscuro => _construir(MyPaleta.oscura);

  /// El tema activo segun [MyColors.paleta].
  static ThemeData get actual => MyColors.esOscuro ? oscuro : claro;

  /// Nombre historico del tema unico. Hoy es el tema claro.
  static ThemeData get dark => claro;

  static ThemeData _construir(MyPaleta p) => ThemeData(
        useMaterial3: true,
        brightness: p.brightness,
        colorScheme: esquema(p),
        scaffoldBackgroundColor: p.surface,
        canvasColor: p.surface,
        textTheme: MyType.textTheme,
        splashFactory: InkSparkle.splashFactory,
        splashColor: p.primary.withValues(alpha: 0.18),
        highlightColor: p.primary.withValues(alpha: 0.08),
        hoverColor: p.primary.withValues(alpha: 0.06),
        focusColor: p.primary.withValues(alpha: 0.14),
        dividerColor: p.outlineVariant,
        iconTheme: IconThemeData(color: p.onSurface),

        // Transiciones entre pantallas: fundido + deslizamiento corto en todas
        // las plataformas, en vez del zoom de Android o el corte seco de la PC.
        pageTransitionsTheme: PageTransitionsTheme(
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
          backgroundColor: p.surface,
          surfaceTintColor: Colors.transparent,
          foregroundColor: p.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: MyType.headlineSm,
          systemOverlayStyle: p.esOscura ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        ),

        // El CTA del sistema: pastilla amarilla completa, 54 de alto.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
            disabledBackgroundColor: p.surfaceContainerHigh,
            disabledForegroundColor: p.outline,
            minimumSize: Size.fromHeight(54),
            padding: EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: StadiumBorder(),
            textStyle: MyType.headlineSm,
            elevation: 0,
          ).copyWith(
            overlayColor: WidgetStatePropertyAll(p.onPrimary.withValues(alpha: 0.08)),
          ),
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.onPrimary,
            minimumSize: Size.fromHeight(54),
            shape: StadiumBorder(),
            textStyle: MyType.headlineSm,
            elevation: 0,
          ),
        ),

        // Accion secundaria: misma silueta, blanca con borde negro fino.
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: p.onSurface,
            backgroundColor: p.surfaceContainerLowest,
            minimumSize: Size.fromHeight(54),
            padding: EdgeInsets.symmetric(horizontal: MySpacing.xl),
            shape: StadiumBorder(),
            side: BorderSide(color: p.onSurface, width: 1.4),
            textStyle: MyType.headlineSm,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: p.onSurface,
            textStyle: MyType.labelLg,
            shape: StadiumBorder(),
          ),
        ),

        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: p.onSurface,
            highlightColor: p.primary.withValues(alpha: 0.18),
          ),
        ),

        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          elevation: 4,
          shape: StadiumBorder(),
        ),

        cardTheme: CardThemeData(
          color: p.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MyRadius.card),
            side: BorderSide(color: p.outlineVariant),
          ),
        ),

        // Campos: relleno gris muy claro con borde suave; al enfocar, borde
        // amarillo como en la referencia.
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: p.surfaceContainerLow,
          contentPadding: EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.md,
          ),
          hintStyle: MyType.bodyMd.copyWith(color: p.secondary),
          labelStyle: MyType.labelMd.copyWith(color: p.secondary),
          floatingLabelStyle: MyType.labelMd.copyWith(color: p.onPrimaryFixedVariant),
          prefixIconColor: p.secondary,
          suffixIconColor: p.secondary,
          border: _borde(p.outlineVariant),
          enabledBorder: _borde(p.outlineVariant),
          focusedBorder: _borde(p.primary, ancho: 2),
          errorBorder: _borde(p.error, ancho: 1.5),
          focusedErrorBorder: _borde(p.error, ancho: 2),
          disabledBorder: _borde(p.surfaceContainerHigh),
        ),

        chipTheme: ChipThemeData(
          backgroundColor: p.surfaceContainerLowest,
          selectedColor: p.primary,
          secondarySelectedColor: p.primary,
          checkmarkColor: p.onPrimary,
          labelStyle: MyType.labelLg,
          secondaryLabelStyle: MyType.labelLg.copyWith(color: p.onPrimary),
          side: BorderSide(color: p.outlineVariant),
          shape: StadiumBorder(),
          padding: EdgeInsets.symmetric(
            horizontal: MySpacing.md,
            vertical: MySpacing.sm,
          ),
        ),

        dividerTheme: DividerThemeData(
          color: p.outlineVariant,
          thickness: 1,
          space: 1,
        ),

        listTileTheme: ListTileThemeData(
          iconColor: p.onSurfaceVariant,
          textColor: p.onSurface,
          selectedColor: p.onPrimaryFixed,
          selectedTileColor: p.primaryFixed,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.md)),
        ),

        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: p.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: p.surfaceContainerLowest,
          dragHandleColor: p.surfaceContainerHighest,
          showDragHandle: false,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(MyRadius.hero),
            ),
          ),
        ),

        dialogTheme: DialogThemeData(
          backgroundColor: p.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
          titleTextStyle: MyType.headlineMd.copyWith(color: p.onSurface),
          contentTextStyle: MyType.bodyMd.copyWith(color: p.onSurfaceVariant),
          actionsPadding: EdgeInsets.fromLTRB(MySpacing.lg, 0, MySpacing.lg, MySpacing.lg),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: p.inverseSurface,
          contentTextStyle: MyType.bodyMd.copyWith(color: p.inverseOnSurface),
          actionTextColor: p.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
          elevation: 6,
        ),

        popupMenuTheme: PopupMenuThemeData(
          color: p.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
          textStyle: MyType.labelLg,
        ),

        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(p.surfaceContainerLowest),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            elevation: WidgetStatePropertyAll(8),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
            ),
          ),
        ),

        dropdownMenuTheme: DropdownMenuThemeData(
          textStyle: MyType.bodyMd,
          menuStyle: MenuStyle(
            backgroundColor: WidgetStatePropertyAll(p.surfaceContainerLowest),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
            ),
          ),
        ),

        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: p.inverseSurface,
            borderRadius: BorderRadius.circular(MyRadius.md),
          ),
          textStyle: MyType.bodySm.copyWith(color: p.inverseOnSurface),
        ),

        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: p.primary,
          linearTrackColor: p.surfaceContainerHigh,
          circularTrackColor: p.surfaceContainerHigh,
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.onPrimary
                : p.surfaceContainerLowest,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.primary
                : p.surfaceContainerHighest,
          ),
          trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
        ),

        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.primary : Colors.transparent,
          ),
          checkColor: WidgetStatePropertyAll(p.onPrimary),
          side: BorderSide(color: p.outline, width: 1.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),

        radioTheme: RadioThemeData(
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.primary : p.outline,
          ),
        ),

        sliderTheme: SliderThemeData(
          activeTrackColor: p.primary,
          inactiveTrackColor: p.surfaceContainerHigh,
          thumbColor: p.primary,
          overlayColor: Color(0x29FFC800),
        ),

        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            backgroundColor: p.surfaceContainerLowest,
            foregroundColor: p.onSurfaceVariant,
            selectedBackgroundColor: p.primary,
            selectedForegroundColor: p.onPrimary,
            side: BorderSide(color: p.outlineVariant),
            textStyle: MyType.labelLg,
          ),
        ),

        tabBarTheme: TabBarThemeData(
          labelColor: p.onSurface,
          unselectedLabelColor: p.secondary,
          indicatorColor: p.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: p.outlineVariant,
          labelStyle: MyType.labelLg,
          unselectedLabelStyle: MyType.labelLg,
        ),

        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: p.surfaceContainerLowest,
          indicatorColor: p.primary,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? p.onPrimary : p.secondary,
            ),
          ),
          labelTextStyle: WidgetStatePropertyAll(MyType.labelMd),
        ),

        datePickerTheme: DatePickerThemeData(
          backgroundColor: p.surfaceContainerLowest,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: p.dock,
          headerForegroundColor: p.inverseOnSurface,
          dayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.primary : null,
          ),
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.onPrimary : p.onSurface,
          ),
          todayBorder: BorderSide(color: p.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
        ),

        timePickerTheme: TimePickerThemeData(
          backgroundColor: p.surfaceContainerLowest,
          dialBackgroundColor: p.surfaceContainerLow,
          dialHandColor: p.primary,
          hourMinuteColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.primaryFixed : p.surfaceContainerLow,
          ),
          hourMinuteTextColor: p.onSurface,
          dayPeriodColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.primary : p.surfaceContainerLow,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.hero)),
        ),

        badgeTheme: BadgeThemeData(
          backgroundColor: p.error,
          textColor: p.onError,
        ),

        textSelectionTheme: TextSelectionThemeData(
          cursorColor: p.onSurface,
          selectionColor: p.primary.withValues(alpha: 0.35),
          selectionHandleColor: p.primary,
        ),

        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(p.onSurface.withValues(alpha: 0.25)),
          radius: Radius.circular(MyRadius.full),
        ),
      );

  /// Alias historico del flujo de pedidos (carrito, direcciones, seguimiento).
  /// Es el mismo tema activo.
  static ColorScheme get colorScheme => esquema(MyColors.paleta);
  static ColorScheme get colorSchemeClaro => colorScheme;
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

/// Modo de color elegido por el usuario (claro u oscuro), compartido por
/// todas las apps.
///
/// Se guarda en el dispositivo, asi que la eleccion sobrevive al cierre de la
/// app. Al cambiarlo se actualiza [MyColors.paleta] y se vuelve a construir
/// el arbol completo con [WidgetsBinding.reassembleApplication]: la mayoria
/// de las pantallas leen los colores como `MyColors.x` (no via `Theme.of`),
/// asi que un cambio de tema comun no las redibujaria.
class MyTema extends Notifier<ThemeMode> {
  static const _clave = 'modo_tema';
  static ThemeMode _guardado = ThemeMode.light;
  static SharedPreferences? _prefs;

  /// Lee la preferencia guardada. Llamar antes de `runApp`.
  static Future<void> cargar() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _guardado = _prefs!.getString(_clave) == 'oscuro' ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      _guardado = ThemeMode.light;
    }
    MyColors.paleta = _guardado == ThemeMode.dark ? MyPaleta.oscura : MyPaleta.clara;
  }

  @override
  ThemeMode build() => _guardado;

  bool get esOscuro => state == ThemeMode.dark;

  void cambiar(ThemeMode modo) {
    if (modo == state) return;
    _guardado = modo;
    MyColors.paleta = modo == ThemeMode.dark ? MyPaleta.oscura : MyPaleta.clara;
    state = modo;
    _prefs?.setString(_clave, modo == ThemeMode.dark ? 'oscuro' : 'claro');
    WidgetsBinding.instance.reassembleApplication();
  }

  void alternar() => cambiar(esOscuro ? ThemeMode.light : ThemeMode.dark);
}

final temaProvider = NotifierProvider<MyTema, ThemeMode>(MyTema.new);
