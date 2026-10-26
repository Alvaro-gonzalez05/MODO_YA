// Eliminar la cuenta desde la app, sin base.
//
// Es lo único de la app que no tiene vuelta atrás: lo que se prueba es que un
// toque de más no alcance para borrar una cuenta.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/comun/eliminar_cuenta.dart';

class _AuthDePrueba extends AuthRepository {
  _AuthDePrueba();

  var eliminaciones = 0;

  @override
  Future<void> eliminarMiCuenta() async => eliminaciones++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<_AuthDePrueba> abrir(WidgetTester tester) async {
    final auth = _AuthDePrueba();
    await tester.pumpWidget(ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp(
        theme: MyTheme.claro,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => eliminarMiCuenta(context, ref),
              child: const Text('Eliminar mi cuenta'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Eliminar mi cuenta'));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('el cartel dice qué se pierde y qué queda', (tester) async {
    await abrir(tester);

    expect(find.textContaining('el mes pagado no se devuelve'), findsOneWidget);
    expect(find.textContaining('Tus pedidos quedan registrados sin tus datos'), findsOneWidget);
    expect(find.textContaining('No se puede deshacer'), findsOneWidget);
  });

  testWidgets('escribiendo ELIMINAR se elimina, sin importar mayúsculas', (tester) async {
    final auth = await abrir(tester);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ' eliminar ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar mi cuenta').last);
    await tester.pumpAndSettle();

    expect(auth.eliminaciones, 1);
  });

  testWidgets('otra palabra no elimina nada', (tester) async {
    final auth = await abrir(tester);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'borrar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar mi cuenta').last);
    await tester.pumpAndSettle();

    expect(auth.eliminaciones, 0);
    expect(find.textContaining('tu cuenta sigue como estaba'), findsOneWidget);
  });

  testWidgets('cancelar el primer cartel no pide nada más', (tester) async {
    final auth = await abrir(tester);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(auth.eliminaciones, 0);
  });
}
