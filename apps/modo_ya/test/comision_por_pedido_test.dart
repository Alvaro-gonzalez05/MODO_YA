// La comisión por pedido (0075) del lado de la app, sin base.
//
// La cuenta la hace la base y tiene su prueba (comision_por_pedido.sql). Acá
// se cuida lo que puede romperse sin que la base se entere: que guardar las
// tarifas mande los porcentajes (si no, `admin_nuevo_tarifario` copia los del
// tarifario anterior y el cambio se pierde callado) y que la hoja del local
// diga qué es cada descuento en vez de "Ajuste".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/features/admin/tarifas_page.dart';

/// Anota el tarifario que se le pide guardar en vez de pegarle a la base.
class _TarifasFalso implements TarifasRepository {
  Tarifario? guardado;

  @override
  Future<void> reemplazar(Tarifario t) async => guardado = t;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Sin bajar tipografias por HTTPS: dejan temporizadores pendientes al cerrar.
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  test('el porcentaje se escribe como en la hoja de la base', () {
    // Mismo formato que pct_legible() en 0075: la pantalla y la hoja tienen
    // que decir lo mismo.
    expect(Formato.porcentaje(10), '10%');
    expect(Formato.porcentaje(10.0), '10%');
    expect(Formato.porcentaje(8.5), '8,5%');
    expect(Formato.porcentaje(0), '0%');
  });

  test('el tarifario lee los porcentajes aunque lleguen como texto', () {
    final t = Tarifario.fromRow({
      'ganancia_repartidor_base': 2000,
      'comision_modo_ya': 500,
      'km_incluidos': 3,
      'precio_km_adicional': 300,
      'radio_busqueda_km': 5,
      'segundos_para_aceptar': 30,
      'comision_pedido_pct': '10.00',
      'costo_cobro_pct': 8,
    });
    expect(t.comisionPedidoPct, 10);
    expect(t.costoCobroPct, 8);
    // Un tarifario de antes de 0075 no tiene las columnas: no cobra comisión.
    final viejo = Tarifario.fromRow({'ganancia_repartidor_base': 2000});
    expect(viejo.comisionPedidoPct, 0);
    expect(viejo.costoCobroPct, 0);
  });

  test('la hoja del local nombra la comisión y el cobro con tarjeta', () {
    RenglonDeCargo r(String concepto) =>
        RenglonDeCargo(fecha: DateTime(2026, 10, 27), concepto: concepto, detalle: '', monto: 0);
    expect(r('comision').rotulo, 'Comisión por pedido');
    expect(r('costo_cobro').rotulo, 'Cobro con tarjeta');
    expect(r('otra_cosa').rotulo, 'Ajuste');
  });

  testWidgets('guardar las tarifas manda los porcentajes que se cambiaron', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _TarifasFalso();
    const vigente = Tarifario(
      ciudadId: 'malargue',
      gananciaRepartidorBase: 2000,
      comisionModoYa: 500,
      kmIncluidos: 3,
      precioKmAdicional: 300,
      radioBusquedaKm: 5,
      segundosParaAceptar: 30,
      comisionPedidoPct: 10,
      costoCobroPct: 8,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        tarifasRepositoryProvider.overrideWith((ref) => repo),
        tarifarioProvider.overrideWith((ref) => Stream.value(vigente)),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: const Scaffold(body: AdminTarifasPage())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('10%'), findsOneWidget);
    expect(find.text('8%'), findsOneWidget);
    expect(find.text('Se le descuenta al local el 18% de cada pedido (le queda el 82%)'), findsOneWidget);

    Finder boton(String campo, String tooltip) => find.descendant(
          of: find.ancestor(of: find.text(campo), matching: find.byType(MyCard)),
          matching: find.byTooltip(tooltip),
        );

    // De a medio punto: lo que cobra Mercado Pago no suele ser redondo.
    await tester.tap(boton('Comisión por pedido', 'Subir'));
    await tester.pump();
    await tester.tap(boton('Cobro con tarjeta', 'Bajar'));
    await tester.pumpAndSettle();
    expect(find.text('10,5%'), findsOneWidget);
    expect(find.text('7,5%'), findsOneWidget);

    await tester.tap(find.widgetWithText(MyBoton, 'Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Aplicar'));
    await tester.pumpAndSettle();

    expect(repo.guardado?.comisionPedidoPct, 10.5);
    expect(repo.guardado?.costoCobroPct, 7.5);
    // Lo que no se tocó viaja como estaba.
    expect(repo.guardado?.gananciaRepartidorBase, 2000);
  });
}
