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

  // En release, un widget que revienta se dibuja como un hueco vacio y el
  // problema pasa desapercibido. Preferimos verlo.
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
    runApp(_ErrorDeArranque(error: e));
    return;
  }

  runApp(const ProviderScope(child: AppModoYa()));
}

/// App MODO YA: la usan clientes, locales y la administracion. Que pantallas
/// ve cada uno lo decide el rol de la cuenta.
///
/// Los riders tienen su propia app (apps/repartidor): necesitan ubicacion en
/// segundo plano, un permiso que las tiendas revisan mucho y que no tiene
/// sentido pedirle a un cliente.
class AppModoYa extends ConsumerWidget {
  const AppModoYa({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MODO YA',
      debugShowCheckedModeBanner: false,
      theme: MyTheme.dark,
      routerConfig: ref.watch(routerProvider),
      // Aviso de version nueva, encima de todas las pantallas.
      builder: (context, child) => MyAvisoActualizacion(
        app: 'modo_ya',
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

class _ErrorDeArranque extends StatelessWidget {
  const _ErrorDeArranque({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MyTheme.dark,
      home: Scaffold(
        body: MyEmptyState(
          title: 'La app no esta configurada',
          message: '$error',
        ),
      ),
    );
  }
}
