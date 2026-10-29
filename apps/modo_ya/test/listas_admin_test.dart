// Las listas y formularios de la administración a los tres anchos, sin base.
//
// Cada pantalla tiene que andar en un celular de 360 px, en una tableta y en
// la compu, y tocar un ítem tiene que abrir su ficha encima de la lista, con
// las acciones adentro. Un desborde hace fallar la prueba solo: Flutter lo
// reporta como error.
//
// Las letras de las pruebas miden lo mismo que el alto de la fuente, así que
// los textos salen bastante más largos que en un celular de verdad: si algo
// entra acá, entra allá.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'package:modo_ya/comun/credenciales.dart';
import 'package:modo_ya/features/admin/alta_cuenta_page.dart';
import 'package:modo_ya/features/admin/carteles_page.dart';
import 'package:modo_ya/features/admin/comercios_page.dart';
import 'package:modo_ya/features/admin/envios_page.dart';
import 'package:modo_ya/features/admin/notificaciones_page.dart';
import 'package:modo_ya/features/admin/reclamos_page.dart';
import 'package:modo_ya/features/admin/repartidores_page.dart';

import 'soporte.dart';

/// Cuenta a cuántos les llega sin pegarle a la base.
class _NotificacionesFalso implements NotificacionesRepository {
  @override
  Future<int> alcanceDe(SegmentoNotificacion segmento, {int dias = 30}) async => 128;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  initializeDateFormatting('es_AR');

  final reclamo = Reclamo(
    id: 'rc1',
    motivo: 'El pedido llegó frío y le faltaba una gaseosa',
    detalle: 'Pedí dos pizzas y una gaseosa grande, llegó sin la gaseosa.',
    estado: EstadoReclamo.abierto,
    rolOrigen: RolUsuario.cliente,
    creadoEn: DateTime(2026, 10, 27, 21, 15),
    pedidoCodigo: 'P-1234',
    abiertoPorNombre: 'Ana Fernández',
  );

  final enviada = Notificacion(
    id: 'n1',
    titulo: 'Hoy tenés envío gratis en todos los locales adheridos',
    cuerpo: 'Pedí en cualquier local adherido y no pagás el envío hasta las 23.',
    segmento: SegmentoNotificacion.clientes,
    enviada: true,
    alcance: 140,
    leidas: 12,
  );

  const local = Comercio(
    id: 'c1',
    nombre: 'Pizzería Don Luis de la Avenida San Martín',
    rubro: 'Pizzería',
    direccion: Direccion(calle: 'Av. San Martín 420, entre Rufino Ortega y Saturnino Torres'),
    telefono: '2604123456',
    aprobacion: EstadoAprobacion.aprobado,
  );

  const rider = Repartidor(
    id: 'r1',
    nombre: 'Juan Pérez Gutiérrez',
    telefono: '2604999888',
    vehiculo: Vehiculo.moto,
    aprobacion: EstadoAprobacion.pendiente,
  );

  final envio = Envio(
    id: 'e1',
    codigo: 'MY-0042',
    comercioId: 'c1',
    comercioNombre: 'Pizzería Don Luis de la Avenida San Martín',
    origen: const Direccion(calle: 'Av. San Martín 420'),
    destino: const Direccion(calle: 'Rufino Ortega 455, departamento 3 B'),
    cliente: const DatosCliente(nombre: 'Ana', telefono: '2604000000'),
    cotizacion: const Cotizacion(distanciaKm: 2.3, gananciaRepartidor: 3500, comision: 700),
    quienPaga: QuienPaga.cliente,
    estado: EstadoEnvio.asignado,
    creadoEn: DateTime(2026, 10, 27, 20),
    repartidorNombre: 'Juan Pérez Gutiérrez',
  );

  // Un mandado: lo pidió un cliente, sin local, y el rider cobra en efectivo.
  final mandado = Envio(
    id: 'e2',
    codigo: 'MY-0043',
    comercioId: '',
    comercioNombre: '',
    origen: const Direccion(calle: 'Farmacia Central'),
    destino: const Direccion(calle: 'Villegas 120'),
    cliente: const DatosCliente(nombre: 'Rosa', telefono: '2604000001'),
    cotizacion: const Cotizacion(distanciaKm: 1.1, gananciaRepartidor: 3000, comision: 500),
    quienPaga: QuienPaga.cliente,
    estado: EstadoEnvio.buscandoRepartidor,
    creadoEn: DateTime(2026, 10, 27, 20, 5),
    cobrarAlEntregar: 12500,
    cobroMetodo: MetodoPago.efectivo,
  );

  Future<void> mostrar(WidgetTester tester, Size tamanio, Widget pantalla) async {
    enPantalla(tester, tamanio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        reclamosProvider.overrideWith((ref) => Stream.value([reclamo])),
        notificacionesProvider.overrideWith((ref) => Stream.value([enviada])),
        notificacionesRepositoryProvider.overrideWith((ref) => _NotificacionesFalso()),
        todosLosComerciosProvider.overrideWith((ref) => Stream.value(const [local])),
        todosLosRepartidoresProvider.overrideWith((ref) => Stream.value(const [rider])),
        enviosActivosProvider.overrideWith((ref) => Stream.value([envio, mandado])),
        preinscripcionesProvider.overrideWith((ref) => Stream.value(const [])),
        solicitudesRiderProvider.overrideWith((ref) => Stream.value(const [])),
        documentosExigidosProvider.overrideWith((ref) async => const []),
        documentacionProvider.overrideWith((ref) => Stream.value(const [])),
        usuarioDeCuentaProvider.overrideWith((ref, _) async => 'cuenta@modoya.app'),
        rubrosProvider.overrideWith((ref) => Stream.value(const [])),
        cartelesProvider.overrideWith(
          (ref) => Stream.value(const [
            Cartel(id: 'k1', titulo: 'El mejor sabor, en tu casa', subtitulo: 'Delivery rápido, simple y local'),
          ]),
        ),
      ],
      child: MaterialApp(theme: MyTheme.claro, home: Scaffold(body: pantalla)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  for (final (formato, tamanio) in anchos) {
    group('En $formato', () {
      testWidgets('un reclamo abre su ficha con las acciones adentro', (tester) async {
        await mostrar(tester, tamanio, const AdminReclamosPage());

        // En la lista no hay botones: se toca y se decide en la ficha.
        expect(find.widgetWithText(MyBoton, 'Responder y cerrar'), findsNothing);

        await tocar(tester, find.text(reclamo.motivo).first);

        expect(find.widgetWithText(MyBoton, 'Responder y cerrar'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Lo estoy viendo'), findsOneWidget);
        expect(find.text(reclamo.detalle!), findsOneWidget);
      });

      testWidgets('una notificación enviada abre sus números', (tester) async {
        await mostrar(tester, tamanio, const AdminNotificacionesPage());

        await tocar(tester, find.text(enviada.titulo).first);

        expect(find.text('La abrieron'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Borrar'), findsOneWidget);
      });

      testWidgets('escribir una notificación abre el formulario por secciones', (tester) async {
        await mostrar(tester, tamanio, const AdminNotificacionesPage());

        await tocar(tester, find.widgetWithText(MyBoton, 'Escribir'));

        expect(find.text('A quién le llega'), findsOneWidget);
        expect(find.text('Qué abre al tocarla'), findsOneWidget);
        expect(find.text('Le llega a 128 personas'), findsOneWidget);
        // Sin título ni mensaje no se puede mandar, y se dice por qué.
        expect(find.text('Falta el título.'), findsOneWidget);
      });

      testWidgets('un local abre su ficha agrupada', (tester) async {
        await mostrar(tester, tamanio, const AdminComerciosPage());

        await tocar(tester, find.text(local.nombre).first);

        expect(find.text('Contacto y retiro'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Suspender cuenta'), findsOneWidget);
      });

      testWidgets('un rider en revisión abre su ficha con la decisión al final', (tester) async {
        await mostrar(tester, tamanio, const AdminRepartidoresPage());

        await tocar(tester, find.text(rider.nombre).first);

        expect(find.text('Cuenta'), findsOneWidget);
        expect(find.widgetWithText(MyBoton, 'Aprobar y habilitar'), findsOneWidget);
      });

      testWidgets('un mandado se lee como mandado y dice cuánto cobrar en la puerta', (tester) async {
        await mostrar(tester, tamanio, const AdminEnviosPage());

        // Antes salía sin nombre: los mandados no tienen local.
        expect(find.text('Mandado'), findsOneWidget);

        await tocar(tester, find.text('MY-0043'));

        expect(find.textContaining('12.500 en efectivo'), findsOneWidget);
      });

      testWidgets('los carteles se editan sin desbordar', (tester) async {
        await mostrar(tester, tamanio, const AdminCartelesPage());

        expect(find.text('Se muestra en el inicio'), findsOneWidget);
        expect(find.byTooltip('Borrar cartel'), findsOneWidget);
      });

      testWidgets('el alta de un local avisa al lado de cada dato lo que falta', (tester) async {
        await mostrar(tester, tamanio, const AltaCuentaPage(esLocal: true));

        await tocar(tester, find.widgetWithText(MyBotonAccion, 'Crear local'));

        expect(find.text('Elegí un rubro'), findsWidgets);
        expect(find.text('Marcá dónde está el local: sin eso no puede pedir riders.'), findsOneWidget);
      });
    });
  }
}
