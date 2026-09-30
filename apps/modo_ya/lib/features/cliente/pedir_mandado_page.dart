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
    return MyPagina(
      volver: () => context.go('/cliente'),
      rotulo: 'Mandados',
      titulo: 'Pedir un rider',
      bajada: 'Para que te retire algo y te lo lleve. El rider no compra ni '
          'adelanta plata: solo lleva y trae.',
      anchoMaximo: 700,
      children: [
        MyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('¿De dónde lo retira?', style: MyType.headlineSm),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _origenCalle,
                label: 'Dirección',
                hint: 'Av. Roca 420',
                icon: Symbols.location_on,
              ),
              _BotonPunto(
                punto: _origen,
                label: _origen == null ? 'Marcar en el mapa' : 'Cambiar el punto',
                onTap: () => _elegirPunto(esOrigen: true),
              ),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _queRetirar,
                label: '¿Qué tiene que retirar?',
                hint: 'Un sobre a nombre de Marcela',
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
              Text('¿A dónde lo lleva?', style: MyType.headlineSm),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _destinoCalle,
                label: 'Dirección',
                hint: 'San Martín 500',
                icon: Symbols.home_pin,
              ),
              _BotonPunto(
                punto: _destino,
                label: _destino == null ? 'Marcar en el mapa' : 'Cambiar el punto',
                onTap: () => _elegirPunto(esOrigen: false),
              ),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _referencia,
                label: 'Referencia',
                hint: 'Portón verde, timbre 2',
                icon: Symbols.info,
                obligatorio: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.md),
        MyCard(
          child: Row(
            children: [
              Icon(Symbols.payments, color: MyColors.tertiary),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  _cotizando
                      ? 'Calculando cuánto sale…'
                      : _cotizacion == null
                          ? 'Marcá los dos puntos en el mapa y te digo cuánto sale.'
                          : 'Sale ${Formato.pesos(_cotizacion!.total)} · '
                              '${_cotizacion!.distanciaKm} km · '
                              'unos ${_cotizacion!.minutos} min',
                  style: MyType.labelLg,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.xs),
        Text(
          'Se lo pagás al rider en efectivo cuando te lo entregue.',
          style: MyType.bodySm.copyWith(color: MyColors.secondary),
        ),
        const SizedBox(height: MySpacing.lg),
        MyBotonAccion(
          label: 'Pedir el rider',
          icon: Symbols.sports_motorsports,
          onPressed: _completo ? _pedir : null,
        ),
        const SizedBox(height: MySpacing.xxl),
      ],
    );
  }
}

class _BotonPunto extends StatelessWidget {
  const _BotonPunto({required this.punto, required this.label, required this.onTap});

  final LatLng? punto;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          punto == null ? Symbols.pin_drop : Symbols.check_circle,
          color: punto == null ? MyColors.outline : MyColors.success,
          fill: punto == null ? 0 : 1,
          size: 20,
        ),
        const SizedBox(width: MySpacing.xs),
        Expanded(
          child: Text(
            punto == null ? 'Falta marcarlo en el mapa' : 'Punto marcado',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
        ),
        MyBoton(
          label: label,
          icon: Symbols.map,
          tipo: MyBotonTipo.texto,
          onPressed: onTap,
        ),
      ],
    );
  }
}
