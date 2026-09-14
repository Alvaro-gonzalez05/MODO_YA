import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_AR');

  // Solo para pruebas automatizadas en web: expone el arbol de accesibilidad
  // como elementos del DOM para poder leer y tocar la app desde un navegador.
  // Se activa con --dart-define=MY_SEMANTICA=true; ninguna build real lo lleva.
  if (const bool.fromEnvironment('MY_SEMANTICA')) {
    SemanticsBinding.instance.ensureSemantics();
  }

  ErrorWidget.builder = (detalle) => Material(
        color: MyColors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            detalle.exceptionAsString(),
            style: const TextStyle(fontSize: 11, color: MyColors.onErrorContainer),
          ),
        ),
      );

  try {
    await Backend.inicializar();
  } catch (e) {
    runApp(MaterialApp(home: Scaffold(body: MyEmptyState(title: 'La app no esta configurada', message: '$e'))));
    return;
  }

  runApp(const ProviderScope(child: AppRepartidor()));
}

/// App del rider.
///
/// Va separada de la app MODO YA a proposito: necesita ubicacion (y mas
/// adelante, ubicacion en segundo plano), el permiso que mas revisan Apple y
/// Google. Dentro de una app de clientes lo mas probable es que la rechacen.
class AppRepartidor extends ConsumerWidget {
  const AppRepartidor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MODO YA Rider',
      debugShowCheckedModeBanner: false,
      theme: MyTheme.light,
      routerConfig: ref.watch(routerProvider),
      // Aviso de version nueva, encima de todas las pantallas.
      builder: (context, child) => MyAvisoActualizacion(
        app: 'rider',
        versionActual: Entorno.version,
        urlManifiesto: Entorno.urlActualizaciones,
        child: child ?? const SizedBox.shrink(),
      ),
      locale: const Locale('es', 'AR'),
      supportedLocales: const [Locale('es', 'AR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
