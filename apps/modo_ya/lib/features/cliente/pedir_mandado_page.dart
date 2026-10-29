import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'carrito.dart';

/// Pedir un rider para un mandado: que retire algo en un lado y lo lleve a otro.
///
/// El rider **no pone plata**: retira algo que ya está pago o listo y lo lleva.
/// Por eso la pantalla pide decir qué tiene que retirar, y no cuánto cuesta lo
/// que se retira.
class PedirMandadoPage extends ConsumerStatefulWidget {
  const PedirMandadoPage({super.key});

  @override
  ConsumerState<PedirMandadoPage> createState() => _PedirMandadoPageState();
}

class _PedirMandadoPageState extends ConsumerState<PedirMandadoPage> {
  final _origenCalle = TextEditingController();
  final _destinoCalle = TextEditingController();
  final _queRetirar = TextEditingController();
  final _referencia = TextEditingController();

  LatLng? _origen;
  LatLng? _destino;
  ({int total, double distanciaKm, int minutos})? _cotizacion;
  var _cotizando = false;

  @override
  void initState() {
    super.initState();
    // La dirección de siempre es el destino más probable: se la ofrece cargada
    // y el cliente la cambia si este mandado va a otro lado.
    final dir = ref.read(direccionActualProvider);
    if (dir != null) {
      _destinoCalle.text = dir.calle;
      _destino = LatLng(dir.lat, dir.lng);
    }
    for (final c in [_origenCalle, _destinoCalle, _queRetirar]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_origenCalle, _destinoCalle, _queRetirar, _referencia]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Lo primero que falta, para decirlo al lado del botón apagado: sin esto
  /// el botón no hacía nada y no se sabía por qué.
  String? get _falta {
    if (_origenCalle.text.trim().isEmpty || _origen == null) return 'Falta de dónde lo retira.';
    if (_queRetirar.text.trim().isEmpty) return 'Falta qué tiene que retirar.';
    if (_destinoCalle.text.trim().isEmpty || _destino == null) return 'Falta a dónde lo lleva.';
    return null;
  }

  bool get _completo =>
      _origen != null &&
      _destino != null &&
      _origenCalle.text.trim().isNotEmpty &&
      _destinoCalle.text.trim().isNotEmpty &&
      _queRetirar.text.trim().isNotEmpty;

  Future<void> _elegirPunto({required bool esOrigen}) async {
    final p = await MyMapa.elegirPunto(
      context,
      inicial: esOrigen ? _origen : _destino,
      titulo: esOrigen ? '¿De dónde lo retira?' : '¿A dónde lo lleva?',
    );
    if (p == null) return;
    setState(() {
      if (esOrigen) {
        _origen = p;
      } else {
        _destino = p;
      }
      _cotizacion = null;
    });
    await _cotizar();
  }

  Future<void> _cotizar() async {
    if (_origen == null || _destino == null) return;
    setState(() => _cotizando = true);
    try {
      final c = await ref.read(enviosRepositoryProvider).cotizarMandado(
            origenLat: _origen!.latitude,
            origenLng: _origen!.longitude,
            destinoLat: _destino!.latitude,
            destinoLng: _destino!.longitude,
          );
      if (mounted) setState(() => _cotizacion = c);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _cotizando = false);
    }
  }

  Future<void> _pedir() async {
    final precio = _cotizacion;
    final ok = await confirmar(
      context,
      titulo: 'Pedir el rider',
      mensaje: precio == null
          ? 'Vamos a buscarte un rider para este mandado.'
          : 'El envío sale ${Formato.pesos(precio.total)} y se los pagás al rider '
              'en efectivo cuando te lo entregue.',
      aceptar: 'Pedir rider',
    );
    if (!ok) return;

    try {
      await ref.read(enviosRepositoryProvider).pedirMandado(
            origenCalle: _origenCalle.text.trim(),
            origenLat: _origen!.latitude,
            origenLng: _origen!.longitude,
            destinoCalle: _destinoCalle.text.trim(),
            destinoLat: _destino!.latitude,
            destinoLng: _destino!.longitude,
            queRetirar: _queRetirar.text,
            destinoReferencia: _referencia.text.trim().isEmpty ? null : _referencia.text.trim(),
          );
      ref.invalidate(misMandadosProvider);
      if (!mounted) return;
      await mostrarExito(context, titulo: '¡Pedido!', mensaje: 'Estamos buscando un rider.');
      if (mounted) context.go('/cliente/mandados');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final movil = context.esMovil;
    final cotizacion = _cotizacion;
    final precio = MyCard(
      child: Row(
        children: [
          Icon(Symbols.payments, color: MyColors.tertiary),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _cotizando
                      ? 'Calculando cuánto sale…'
                      : cotizacion == null
                          ? 'Marcá los dos puntos en el mapa y te decimos cuánto sale.'
                          : 'Sale ${Formato.pesos(cotizacion.total)}',
                  style: MyType.labelLg,
                ),
                if (cotizacion != null && !_cotizando)
                  Text(
                    '${Formato.km(cotizacion.distanciaKm)} · unos ${cotizacion.minutos} min',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  ),
                const SizedBox(height: MySpacing.xxs),
                Text(
                  'Se lo pagás al rider en efectivo cuando te lo entregue.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final falta = _falta;
    final boton = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyBotonAccion(
          label: cotizacion == null || movil ? 'Pedir el rider' : 'Pedir el rider · ${Formato.pesos(cotizacion.total)}',
          icon: Symbols.sports_motorsports,
          onPressed: _completo ? _pedir : null,
        ),
        if (falta != null)
          Padding(
            padding: const EdgeInsets.only(top: MySpacing.xs),
            child: Text(
              falta,
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );

    final pagina = MyPagina(
      volver: () => context.go('/cliente'),
      rotulo: 'Mandados',
      titulo: 'Pedir un rider',
      bajada: 'Para que te retire algo y te lo lleve. El rider no compra ni '
          'adelanta plata: solo lleva y trae.',
      anchoMaximo: 700,
      conDock: false,
      children: [
        MyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TituloTramo(numero: 1, texto: '¿De dónde lo retira?'),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _origenCalle,
                label: 'Dirección',
                hint: 'Ej.: Av. Roca 420',
                icon: Symbols.location_on,
              ),
              _BotonPunto(
                punto: _origen,
                onTap: () => _elegirPunto(esOrigen: true),
              ),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _queRetirar,
                label: '¿Qué tiene que retirar?',
                hint: 'Ej.: un sobre a nombre de Marcela',
                icon: Symbols.inventory_2,
                lineas: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.md),
        MyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TituloTramo(numero: 2, texto: '¿A dónde lo lleva?'),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _destinoCalle,
                label: 'Dirección',
                hint: 'Ej.: San Martín 500',
                icon: Symbols.home_pin,
              ),
              _BotonPunto(
                punto: _destino,
                onTap: () => _elegirPunto(esOrigen: false),
              ),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _referencia,
                label: 'Referencia (opcional)',
                hint: 'Ej.: portón verde, timbre 2',
                icon: Symbols.info,
                obligatorio: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.md),
        precio,
        if (!movil) ...[
          const SizedBox(height: MySpacing.lg),
          boton,
        ],
        const SizedBox(height: MySpacing.xl),
      ],
    );

    if (!movil) return pagina;

    // En el celular el formulario es largo: el botón (y lo que falta para
    // poder tocarlo) queda fijo abajo, siempre a la vista.
    return Column(
      children: [
        Expanded(child: pagina),
        DecoratedBox(
          decoration: BoxDecoration(
            color: MyColors.surfaceContainerLowest,
            border: Border(top: BorderSide(color: MyColors.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.sm, MySpacing.screenEdge, MySpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cotizacion != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MySpacing.xs),
                      child: Row(
                        children: [
                          Expanded(child: Text('En efectivo al rider', style: MyType.bodyMd.copyWith(color: MyColors.secondary))),
                          Text(Formato.pesos(cotizacion.total), style: MyType.headlineSm.copyWith(color: MyColors.tertiary)),
                        ],
                      ),
                    ),
                  boton,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "1 · ¿De dónde lo retira?": los dos tramos numerados, para que se lea el
/// orden del viaje.
class _TituloTramo extends StatelessWidget {
  const _TituloTramo({required this.numero, required this.texto});

  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: MyColors.primary,
          child: Text('$numero', style: MyType.labelMd.copyWith(color: MyColors.onPrimary)),
        ),
        const SizedBox(width: MySpacing.sm),
        Expanded(child: Text(texto, style: MyType.headlineSm)),
      ],
    );
  }
}

/// El punto en el mapa: un botón grande mientras falta y, una vez marcado,
/// el mapita con el pin para confirmar que quedó donde era.
///
/// Antes era una fila con el texto y el botón al lado: a 360 px el texto se
/// partía en tres renglones y el botón quedaba cortado.
class _BotonPunto extends StatelessWidget {
  const _BotonPunto({required this.punto, required this.onTap});

  final LatLng? punto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = punto;
    if (p == null) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Symbols.map, size: 20),
        label: const Text('Marcar en el mapa'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyMapaVista(alto: 110, marcadores: [MyMarcador(punto: p, icono: Symbols.location_on)]),
        const SizedBox(height: MySpacing.xxs),
        Row(
          children: [
            Icon(Symbols.check_circle, color: MyColors.success, fill: 1, size: 18),
            const SizedBox(width: MySpacing.xs),
            Expanded(child: Text('Punto marcado', style: MyType.bodySm.copyWith(color: MyColors.secondary))),
            MyBoton(label: 'Cambiar', icon: Symbols.edit_location, tipo: MyBotonTipo.texto, onPressed: onTap),
          ],
        ),
      ],
    );
  }
}
