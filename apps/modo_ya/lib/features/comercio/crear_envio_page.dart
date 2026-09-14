import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';


/// Crear envío (A5) y cotización (A6).
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
      titulo: 'Dónde se entrega',
      ayuda: 'Mové el mapa hasta que el pin quede sobre la casa del cliente.',
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
      mostrarError(context, 'Marcá en el mapa dónde se entrega.');
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
      if (mounted) context.go('/local/envios/$id');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comercio = ref.watch(comercioActualProvider).value;
    final origen = comercio?.direccion;
    final c = _cotizacion;

    final recorrido = MyRouteTimeline(
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
    );

    final destino = MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Destino', style: MyType.headlineSm),
          const SizedBox(height: MySpacing.md),
          MyCampo(
            controller: _calle,
            label: 'Dirección',
            hint: 'Av. San Martín 450',
            icon: Symbols.location_on,
            onChanged: (_) => setState(() {}),
          ),
          MyCampo(
            controller: _referencia,
            label: 'Referencia (opcional)',
            hint: 'Portón verde, al lado del kiosco',
            icon: Symbols.pin_drop,
            obligatorio: false,
          ),
          if (_destino != null && origen != null && origen.tieneCoordenadas) ...[
            MyMapaVista(
              alto: context.esMovil ? 170 : 220,
              marcadores: [
                MyMarcador(punto: LatLng(origen.lat!, origen.lng!), icono: Symbols.storefront),
                MyMarcador(punto: _destino!, icono: Symbols.home, color: MyColors.dock),
              ],
            ),
            const SizedBox(height: MySpacing.sm),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: MyBoton(
              onPressed: _marcarDestino,
              icon: _destino == null ? Symbols.add_location : Symbols.edit_location,
              label: _destino == null ? 'Marcar en el mapa' : 'Cambiar punto',
              tipo: _destino == null ? MyBotonTipo.oscuro : MyBotonTipo.secundario,
            ),
          ),
        ],
      ),
    );

    final recibe = MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Quién recibe', style: MyType.headlineSm),
          const SizedBox(height: MySpacing.md),
          MyCampo(controller: _nombre, label: 'Nombre', icon: Symbols.person),
          MyCampo(controller: _telefono, label: 'Teléfono', icon: Symbols.call, keyboard: TextInputType.phone),
          MyCampo(
            controller: _indicaciones,
            label: 'Indicaciones (opcional)',
            hint: 'Tocar timbre, no golpear',
            icon: Symbols.sticky_note_2,
            obligatorio: false,
            lineas: 2,
          ),
          const MyOverline('Quién paga el envío'),
          const SizedBox(height: MySpacing.xs),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              MyChip('El cliente', selected: _paga == QuienPaga.cliente, onTap: () => setState(() => _paga = QuienPaga.cliente)),
              MyChip('Lo pago yo', selected: _paga == QuienPaga.comercio, onTap: () => setState(() => _paga = QuienPaga.comercio)),
            ],
          ),
        ],
      ),
    );

    final Widget cotizacion;
    if (_cotizando) {
      cotizacion = const MyCard(
        child: Padding(padding: EdgeInsets.all(MySpacing.lg), child: Center(child: CircularProgressIndicator())),
      );
    } else if (c == null) {
      cotizacion = MyCard(
        color: MyColors.surfaceContainerLow,
        shadows: const [],
        child: Row(
          children: [
            const Icon(Symbols.info, color: MyColors.secondary),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Text(
                'Marcá el destino en el mapa y te mostramos el precio con la distancia real.',
                style: MyType.bodyMd.copyWith(color: MyColors.secondary),
              ),
            ),
          ],
        ),
      );
    } else {
      cotizacion = MyCard(
        child: Column(
          children: [
            MyStatRow(tiles: [
              MyStatTile(icon: Symbols.route, value: Formato.km(c.distanciaKm), label: 'Distancia'),
              MyStatTile(icon: Symbols.schedule, value: '${c.minutosEstimados} min', label: 'Estimado'),
            ]),
            const SizedBox(height: MySpacing.md),
            _Linea('Rider', Formato.pesos(c.gananciaRepartidor)),
            _Linea('Comisión MODO YA', Formato.pesos(c.comision)),
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
      );
    }

    final boton = MyBotonAccion(
      label: c == null ? 'Marcá el destino para cotizar' : 'Confirmar y buscar rider',
      icon: Symbols.sports_motorsports,
      onPressed: c == null ? null : _confirmar,
    );

    const espacio = SizedBox(height: MySpacing.md);
    return Form(
      key: _form,
      child: MyPagina(
        volver: () => context.canPop() ? context.pop() : context.go('/local/envios'),
        rotulo: 'Cadetería',
        titulo: 'Pedir un rider',
        bajada: 'El precio sale de la distancia real entre tu local y el destino',
        anchoMaximo: 1180,
        conDock: false,
        children: context.esMovil
            ? [recorrido, espacio, destino, espacio, recibe, espacio, cotizacion, const SizedBox(height: MySpacing.lg), boton]
            : [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [destino, espacio, recibe]),
                    ),
                    const SizedBox(width: MySpacing.lg),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [recorrido, espacio, cotizacion, const SizedBox(height: MySpacing.lg), boton],
                      ),
                    ),
                  ],
                ),
              ],
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
