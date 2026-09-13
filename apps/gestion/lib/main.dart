import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Formatos de fecha y moneda en es-AR.
  await initializeDateFormatting('es_AR');

  Entorno.validar();

  // En release, un widget que revienta se dibuja como un hueco vacio y el
  // problema pasa desapercibido. Preferimos verlo.
  ErrorWidget.builder = (detalle) => Material(
        color: const Color(0xFFFFDAD6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            detalle.exceptionAsString(),
            style: const TextStyle(fontSize: 11, color: Color(0xFF93000A)),
          ),
        ),
      );

  runApp(
    ProviderScope(
      overrides: [
        // Hasta que entre Supabase Auth, la sesion es la del comercio demo.
        sesionProvider.overrideWithValue(Sesion.demoComercio),
      ],
      child: const AppGestion(),
    ),
  );
}

/// App de Gestion: la usa el comercio desde el celular y la administracion
/// desde Windows. El rol define que arbol de pantallas ve cada uno.
class AppGestion extends ConsumerWidget {
  const AppGestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'MODO YA Gestion',
      debugShowCheckedModeBanner: false,
      theme: MyTheme.light,
      routerConfig: ref.watch(routerProvider),
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
