// El diálogo del código de entrega, sin base.
//
// Existe por un botón que mentía: "Confirmar" se veía habilitado siempre
// (`onPressed: () => _c.text.length == 4 ? ... : null` nunca es null) y con
// menos de 4 dígitos el rider lo tocaba y no pasaba nada, sin ningún mensaje.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya_repartidor/features/servicio_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final envio = Envio(
    id: 'e1',
    codigo: 'MY-E-001',
    comercioId: 'c1',
    comercioNombre: 'El Local',
    origen: const Direccion(calle: 'Roca 900'),
    destino: const Direccion(calle: 'San Martín 100'),
    cliente: const DatosCliente(nombre: 'Clienta', telefono: '2604555000'),
    cotizacion: const Cotizacion(distanciaKm: 1.2, gananciaRepartidor: 3000, comision: 1200),
    quienPaga: QuienPaga.cliente,
    // En camino es el único estado en el que se ofrece confirmar la entrega.
    estado: EstadoEnvio.enCamino,
    creadoEn: DateTime(2026, 10, 21, 20, 30),
    repartidorId: 'r1',
    repartidorNombre: 'Rider',
  );

  Future<void> abrirDialogo(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Sin Supabase inicializado: la sesión se resuelve vacía.
        sesionActualProvider.overrideWith((ref) async => null),
        envioProvider(envio.id).overrideWith((ref) => Stream.value(envio)),
      ],
      child: MaterialApp(
        theme: MyTheme.claro,
        home: ServicioEnCursoPage(envioId: envio.id),
      ),
    ));
    // Pumps a mano y no pumpAndSettle: el mapa del servicio nunca se queda
    // quieto, asi que esperar a que no haya nada animando no termina.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Confirmar entrega'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  VoidCallback? botonConfirmar(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar')).onPressed;

  group('Confirmar el código de entrega', () {
    testWidgets('arranca deshabilitado y se habilita con los 4 dígitos',
        (tester) async {
      await abrirDialogo(tester);

      expect(find.text('Código de entrega'), findsOneWidget);
      expect(botonConfirmar(tester), isNull, reason: 'sin nada escrito no se puede confirmar');

      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();
      expect(botonConfirmar(tester), isNull, reason: 'con 2 digitos tampoco');

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      expect(botonConfirmar(tester), isNotNull, reason: 'con los 4 ya se puede');
    });

    testWidgets('confirmar con los 4 dígitos cierra el diálogo', (tester) async {
      await abrirDialogo(tester);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Se cerró: lo que viene después es la llamada a la base, que acá falla
      // y se muestra como error. Lo que importa es que el diálogo devolvió.
      expect(find.text('Código de entrega'), findsNothing);
    });
  });
}
