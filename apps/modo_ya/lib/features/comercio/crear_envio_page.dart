import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';

/// Crear envio (A5) y cotizacion (A6).
///
/// El precio lo calcula el servidor con la distancia real entre el local y el
/// punto marcado; la app nunca manda importes.
class CrearEnvioPage extends ConsumerStatefulWidget {
  const CrearEnvioPage({super.key});

  @override
  ConsumerState<CrearEnvioPage> createState() => _CrearEnvioPageState();
}

class _CrearEnvioPageState extends ConsumerState<CrearEnvioPage> {
  final _form = GlobalKey<FormState>();
  final _calle = TextEditingController();
  final _referencia = TextEditingController();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _indicaciones = TextEditingController();

  var _paga = QuienPaga.cliente;
  LatLng? _destino;
  Cotizacion? _cotizacion;
  var _cotizando = false;

  @override
  void dispose() {
    for (final c in [_calle, _referencia, _nombre, _telefono, _indicaciones]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _marcarDestino() async {
    final comercio = ref.read(comercioActualProvider).value;
    final origen = comercio?.direccion;
    final p = await MyMapa.elegirPunto(
      context,
      inicial: _destino ?? (origen != null && origen.tieneCoordenadas ? LatLng(origen.lat!, origen.lng!) : null),
      titulo: 'Donde se entrega',
      ayuda: 'Mueve el mapa hasta que el pin quede sobre la casa del cliente.',
    );
    if (p == null) return;
    setState(() {
      _destino = p;
      _cotizacion = null;
      _cotizando = true;
    });
    try {
      final c = await ref.read(enviosRepositoryProvider).cotizar(lat: p.latitude, lng: p.longitude);
      if (mounted) setState(() => _cotizacion = c);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _cotizando = false);
    }
  }

  Future<void> _confirmar() async {
    if (!_form.currentState!.validate()) return;
    if (_destino == null || _cotizacion == null) {
      mostrarError(context, 'Marca en el mapa donde se entrega.');
      return;
    }
    try {
      final id = await ref.read(enviosRepositoryProvider).crearYBuscar(
            calle: _calle.text,
            referencia: _referencia.text,
            lat: _destino!.latitude,
            lng: _destino!.longitude,
            clienteNombre: _nombre.text,
            clienteTelefono: _telefono.text,
            indicaciones: _indicaciones.text,
            paga: _paga,
          );
      if (mounted) context.pushReplacement('/local/envio/$id');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comercio = ref.watch(comercioActualProvider).value;
    final origen = comercio?.direccion;
    final c = _cotizacion;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Symbols.arrow_back), onPressed: () => context.pop()),
        title: const Text('Pedir un rider'),
      ),
      body: Form(
        key: _form,
        child: FormularioCentrado(
          ancho: 580,
          children: [
            MyRouteTimeline(
              background: MyColors.surfaceContainerLowest,
              stops: [
                MyRouteStop(
                  overline: 'Retiro',
                  title: comercio?.nombre ?? 'Tu local',
                  subtitle: origen?.calle,
                  icon: Symbols.storefront,
                ),
                MyRouteStop(
                  overline: 'Entrega',
                  title: _calle.text.trim().isEmpty ? 'A completar' : _calle.text.trim(),
                  subtitle: _destino == null ? 'Falta marcar en el mapa' : null,
                  icon: Symbols.home,
                  iconBackground: MyColors.dock,
                ),
              ],
            ),
            const SizedBox(height: MySpacing.lg),
            MyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Destino', style: MyType.headlineSm),
                  const SizedBox(height: MySpacing.md),
                  MyCampo(
                    controller: _calle,
                    label: 'Direccion',
                    hint: 'Av. San Martin 450',
                    icon: Symbols.location_on,
                    onChanged: (_) => setState(() {}),
                  ),
                  MyCampo(
                    controller: _referencia,
                    label: 'Referencia (opcional)',
                    hint: 'Porton verde, al lado del kiosco',
                    icon: Symbols.pin_drop,
                    obligatorio: false,
                  ),
                  if (_destino != null && origen != null && origen.tieneCoordenadas) ...[
                    MyMapaVista(
                      alto: 170,
                      marcadores: [
                        MyMarcador(punto: LatLng(origen.lat!, origen.lng!), icono: Symbols.storefront),
                        MyMarcador(punto: _destino!, icono: Symbols.home, color: MyColors.dock),
                      ],
                    ),
                    const SizedBox(height: MySpacing.sm),
                  ],
                  OutlinedButton.icon(
                    onPressed: _marcarDestino,
                    icon: Icon(_destino == null ? Symbols.add_location : Symbols.edit_location, size: 20),
                    label: Text(_destino == null ? 'Marcar en el mapa' : 'Cambiar punto'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MySpacing.md),
            MyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Quien recibe', style: MyType.headlineSm),
                  const SizedBox(height: MySpacing.md),
                  MyCampo(controller: _nombre, label: 'Nombre', icon: Symbols.person),
                  MyCampo(controller: _telefono, label: 'Telefono', icon: Symbols.call, keyboard: TextInputType.phone),
                  MyCampo(
                    controller: _indicaciones,
                    label: 'Indicaciones (opcional)',
                    hint: 'Tocar timbre, no golpear',
                    icon: Symbols.sticky_note_2,
                    obligatorio: false,
                    lineas: 2,
                  ),
                  const MyOverline('Quien paga el envio'),
                  const SizedBox(height: MySpacing.xs),
                  Wrap(
                    spacing: MySpacing.xs,
                    children: [
                      MyChip('El cliente', selected: _paga == QuienPaga.cliente, onTap: () => setState(() => _paga = QuienPaga.cliente)),
                      MyChip('Lo pago yo', selected: _paga == QuienPaga.comercio, onTap: () => setState(() => _paga = QuienPaga.comercio)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: MySpacing.md),
            if (_cotizando)
              const Padding(
                padding: EdgeInsets.all(MySpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (c != null)
              MyCard(
                color: MyColors.surfaceContainerLow,
                shadows: const [],
                child: Column(
                  children: [
                    MyStatRow(tiles: [
                      MyStatTile(icon: Symbols.route, value: Formato.km(c.distanciaKm), label: 'Distancia'),
                      MyStatTile(icon: Symbols.schedule, value: '${c.minutosEstimados}', label: 'Minutos est.'),
                    ]),
                    const SizedBox(height: MySpacing.md),
                    _Linea('Rider', Formato.pesos(c.gananciaRepartidor)),
                    _Linea('Comision MODO YA', Formato.pesos(c.comision)),
                    const Divider(height: MySpacing.lg),
                    Row(
                      children: [
                        Text('Total', style: MyType.headlineSm),
                        const Spacer(),
                        Text(Formato.pesos(c.total), style: MyType.priceHero.copyWith(color: MyColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: MySpacing.lg),
            MyBotonAccion(
              label: c == null ? 'Marca el destino para cotizar' : 'Confirmar y buscar rider',
              icon: Symbols.sports_motorsports,
              onPressed: c == null ? null : _confirmar,
            ),
            const SizedBox(height: MySpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.label, this.valor);

  final String label;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MySpacing.xxs),
        child: Row(
          children: [
            Text(label, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
            const Spacer(),
            Text(valor, style: MyType.labelLg),
          ],
        ),
      );
}
