import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// A5 - Crear envio, y A6 - Cotizacion y confirmacion.
///
/// Las dos pantallas del diseno son un mismo flujo: se carga el destino y al
/// cotizar sube una hoja inferior con el precio antes de confirmar.
class CrearEnvioPage extends ConsumerStatefulWidget {
  const CrearEnvioPage({super.key});

  @override
  ConsumerState<CrearEnvioPage> createState() => _CrearEnvioPageState();
}

class _CrearEnvioPageState extends ConsumerState<CrearEnvioPage> {
  final _formKey = GlobalKey<FormState>();
  final _direccion = TextEditingController();
  final _referencia = TextEditingController();
  final _nombreCliente = TextEditingController();
  final _telefono = TextEditingController();
  final _indicaciones = TextEditingController();

  var _quienPaga = QuienPaga.cliente;
  var _procesando = false;

  /// Distancia simulada hasta que tengamos el pin en el mapa y PostGIS.
  ///
  /// El slider existe para poder probar la cotizacion con distintas distancias;
  /// cuando entre el mapa, este valor va a salir de la ruta real.
  var _distanciaKm = 2.4;

  @override
  void dispose() {
    _direccion.dispose();
    _referencia.dispose();
    _nombreCliente.dispose();
    _telefono.dispose();
    _indicaciones.dispose();
    super.dispose();
  }

  Future<void> _cotizar() async {
    if (!_formKey.currentState!.validate()) return;

    final tarifario =
        ref.read(tarifarioProvider).value ?? Tarifario.inicial;
    final cotizacion = tarifario.cotizar(_distanciaKm);

    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaCotizacion(
        cotizacion: cotizacion,
        quienPaga: _quienPaga,
        destino: _direccion.text.trim(),
      ),
    );

    if (confirmado != true || !mounted) return;
    await _confirmar();
  }

  Future<void> _confirmar() async {
    setState(() => _procesando = true);
    final repo = ref.read(enviosRepositoryProvider);
    final comercioId = ref.read(sesionProvider).comercioId!;

    try {
      final envio = await repo.crear(
        comercioId: comercioId,
        destino: Direccion(
          calle: _direccion.text.trim(),
          referencia: _referencia.text.trim().isEmpty
              ? null
              : _referencia.text.trim(),
        ),
        cliente: DatosCliente(
          nombre: _nombreCliente.text.trim(),
          telefono: _telefono.text.trim(),
          indicaciones: _indicaciones.text.trim().isEmpty
              ? null
              : _indicaciones.text.trim(),
        ),
        quienPaga: _quienPaga,
        distanciaKm: _distanciaKm,
      );

      // Confirmar arranca la busqueda de cadetes.
      await repo.confirmar(envio.id);

      if (!mounted) return;
      context.goNamed('seguimiento', pathParameters: {'id': envio.id});
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pudimos crear el envio: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final comercio = ref.watch(comercioActualProvider).value;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => context.goNamed('comercioInicio'),
        ),
        title: const Text('Nuevo envio'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(MySpacing.screenEdge),
                children: [
                  // El retiro sale del comercio: no se edita.
                  MyRouteTimeline(
                    background: MyColors.surfaceContainerLowest,
                    padding: const EdgeInsets.all(MySpacing.md),
                    stops: [
                      MyRouteStop(
                        overline: 'Punto de retiro',
                        title: comercio?.nombre ?? 'Tu comercio',
                        subtitle: comercio?.direccion.calle,
                        badge: 'Fijo',
                        icon: Symbols.storefront,
                      ),
                      MyRouteStop(
                        overline: 'Punto de entrega',
                        title: _direccion.text.trim().isEmpty
                            ? 'A completar'
                            : _direccion.text.trim(),
                        icon: Symbols.home,
                        iconBackground: MyColors.dock,
                      ),
                    ],
                  ),

                  const SizedBox(height: MySpacing.xl),
                  Text('Destino', style: MyType.headlineMd),
                  const SizedBox(height: MySpacing.md),

                  _Campo(
                    controller: _direccion,
                    label: 'Direccion de entrega',
                    hint: 'Av. San Martin 450',
                    icon: Symbols.location_on,
                    onChanged: (_) => setState(() {}),
                  ),
                  _Campo(
                    controller: _referencia,
                    label: 'Referencia (opcional)',
                    hint: 'Porton verde, al lado del kiosco',
                    icon: Symbols.pin_drop,
                    obligatorio: false,
                  ),

                  const SizedBox(height: MySpacing.xs),
                  _SelectorDistancia(
                    valor: _distanciaKm,
                    onChanged: (v) => setState(() => _distanciaKm = v),
                  ),

                  const SizedBox(height: MySpacing.xl),
                  Text('Cliente', style: MyType.headlineMd),
                  const SizedBox(height: MySpacing.md),

                  _Campo(
                    controller: _nombreCliente,
                    label: 'Nombre',
                    hint: 'Marcela Diaz',
                    icon: Symbols.person,
                  ),
                  _Campo(
                    controller: _telefono,
                    label: 'Telefono',
                    hint: '+54 260 ...',
                    icon: Symbols.call,
                    keyboard: TextInputType.phone,
                  ),
                  _Campo(
                    controller: _indicaciones,
                    label: 'Indicaciones (opcional)',
                    hint: 'Tocar timbre, no golpear',
                    icon: Symbols.sticky_note_2,
                    obligatorio: false,
                    lineas: 2,
                  ),

                  const SizedBox(height: MySpacing.md),
                  Text('Quien paga el envio', style: MyType.headlineMd),
                  const SizedBox(height: MySpacing.sm),
                  _SelectorPagador(
                    valor: _quienPaga,
                    onChanged: (v) => setState(() => _quienPaga = v),
                  ),

                  const SizedBox(height: MySpacing.xl),
                  FilledButton(
                    onPressed: _procesando ? null : _cotizar,
                    child: _procesando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: MyColors.onPrimary,
                            ),
                          )
                        : const Text('Cotizar envio'),
                  ),
                  const SizedBox(height: MySpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A6 - Hoja de cotizacion: el precio antes de confirmar.
class _HojaCotizacion extends StatelessWidget {
  const _HojaCotizacion({
    required this.cotizacion,
    required this.quienPaga,
    required this.destino,
  });

  final Cotizacion cotizacion;
  final QuienPaga quienPaga;
  final String destino;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MySpacing.screenEdge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: MyColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(MyRadius.full),
                ),
              ),
            ),
            const SizedBox(height: MySpacing.lg),
            Text('Cotizacion del envio', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.xxs),
            Text(
              destino,
              style: MyType.bodyMd.copyWith(color: MyColors.secondary),
            ),

            const SizedBox(height: MySpacing.lg),
            MyStatRow(
              tiles: [
                MyStatTile(
                  icon: Symbols.route,
                  value: Formato.km(cotizacion.distanciaKm),
                  label: 'Distancia',
                ),
                MyStatTile(
                  icon: Symbols.schedule,
                  value: '${cotizacion.minutosEstimados}',
                  label: 'Minutos est.',
                ),
                MyStatTile(
                  icon: Symbols.payments,
                  value: quienPaga == QuienPaga.cliente ? 'Cliente' : 'Vos',
                  label: 'Lo paga',
                ),
              ],
            ),

            const SizedBox(height: MySpacing.lg),
            Container(
              padding: const EdgeInsets.all(MySpacing.md),
              decoration: BoxDecoration(
                color: MyColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(MyRadius.lg),
              ),
              child: Column(
                children: [
                  _Linea(
                    'Ganancia del cadete',
                    Formato.pesos(cotizacion.gananciaRepartidor),
                  ),
                  const SizedBox(height: MySpacing.xs),
                  _Linea(
                    'Comision MODO YA',
                    Formato.pesos(cotizacion.comision),
                  ),
                  const Divider(height: MySpacing.lg),
                  Row(
                    children: [
                      Text('Total', style: MyType.headlineSm),
                      const Spacer(),
                      Text(
                        Formato.pesos(cotizacion.total),
                        style: MyType.priceHero
                            .copyWith(color: MyColors.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: MySpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar y buscar cadete'),
            ),
            const SizedBox(height: MySpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Modificar datos'),
            ),
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
        const Spacer(),
        Text(valor, style: MyType.labelLg),
      ],
    );
  }
}

class _SelectorPagador extends StatelessWidget {
  const _SelectorPagador({required this.valor, required this.onChanged});

  final QuienPaga valor;
  final ValueChanged<QuienPaga> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final opcion in QuienPaga.values) ...[
          if (opcion != QuienPaga.values.first)
            const SizedBox(width: MySpacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opcion),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: MySpacing.md,
                  vertical: MySpacing.md,
                ),
                decoration: BoxDecoration(
                  color: valor == opcion
                      ? MyColors.primary
                      : MyColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(MyRadius.lg),
                  boxShadow: MyShadows.subtle,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      opcion == QuienPaga.comercio
                          ? Symbols.storefront
                          : Symbols.person,
                      size: 22,
                      color: valor == opcion
                          ? MyColors.onPrimary
                          : MyColors.primary,
                    ),
                    const SizedBox(height: MySpacing.xs),
                    Text(
                      opcion == QuienPaga.comercio ? 'Lo pago yo' : 'El cliente',
                      style: MyType.labelLg.copyWith(
                        color: valor == opcion
                            ? MyColors.onPrimary
                            : MyColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Provisorio: reemplaza al pin en el mapa hasta que integremos flutter_map.
class _SelectorDistancia extends StatelessWidget {
  const _SelectorDistancia({required this.valor, required this.onChanged});

  final double valor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.route, size: 18, color: MyColors.primary),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: Text('Distancia estimada', style: MyType.labelLg),
              ),
              Text(
                Formato.km(valor),
                style: MyType.headlineSm.copyWith(color: MyColors.primary),
              ),
            ],
          ),
          Slider(
            value: valor,
            min: 0.5,
            max: 8,
            divisions: 15,
            onChanged: onChanged,
          ),
          Text(
            'Provisorio: cuando integremos el mapa, la distancia se va a '
            'calcular con el pin de entrega.',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
        ],
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  const _Campo({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboard,
    this.obligatorio = true,
    this.lineas = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;
  final bool obligatorio;
  final int lineas;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MyOverline(label),
          const SizedBox(height: MySpacing.xs),
          TextFormField(
            controller: controller,
            keyboardType: keyboard,
            maxLines: lineas,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 20, color: MyColors.outline),
            ),
            validator: obligatorio
                ? (v) => (v == null || v.trim().isEmpty)
                    ? 'Completa este dato'
                    : null
                : null,
          ),
        ],
      ),
    );
  }
}
