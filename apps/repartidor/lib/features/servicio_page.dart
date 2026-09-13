import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// B4 a B7 - Servicio en curso.
///
/// Una sola pantalla recorre toda la secuencia del diseno (ir al comercio,
/// llegue, retire el pedido, en camino, confirmar entrega, finalizado): lo
/// unico que cambia es el estado del envio y, con el, la accion principal.
class ServicioEnCursoPage extends ConsumerWidget {
  const ServicioEnCursoPage({super.key, required this.envioId});

  final String envioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enCurso = ref.watch(envioEnCursoProvider);

    return Scaffold(
      backgroundColor: MyColors.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => context.goNamed('inicio'),
        ),
        title: const Text('Servicio en curso'),
      ),
      body: enCurso.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (envio) {
          if (envio == null || envio.id != envioId) {
            return _Finalizado(onVolver: () => context.goNamed('inicio'));
          }
          return _Contenido(envio: envio);
        },
      ),
    );
  }
}

class _Contenido extends ConsumerStatefulWidget {
  const _Contenido({required this.envio});

  final Envio envio;

  @override
  ConsumerState<_Contenido> createState() => _ContenidoState();
}

class _ContenidoState extends ConsumerState<_Contenido> {
  var _procesando = false;

  /// Siguiente paso del flujo segun el estado actual.
  ({String label, IconData icon, EstadoEnvio siguiente})? get _accion =>
      switch (widget.envio.estado) {
        EstadoEnvio.asignado => (
            label: 'Llegue al local',
            icon: Symbols.storefront,
            siguiente: EstadoEnvio.enLocal,
          ),
        EstadoEnvio.enLocal => (
            label: 'Retire el pedido',
            icon: Symbols.package_2,
            siguiente: EstadoEnvio.retirado,
          ),
        EstadoEnvio.retirado => (
            label: 'Voy al cliente',
            icon: Symbols.navigation,
            siguiente: EstadoEnvio.enCamino,
          ),
        // La entrega no avanza sola: necesita el codigo del cliente.
        EstadoEnvio.enCamino => null,
        _ => null,
      };

  Future<void> _avanzar(EstadoEnvio siguiente) async {
    setState(() => _procesando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(enviosRepositoryProvider)
          .cambiarEstado(widget.envio.id, siguiente);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _confirmarEntrega() async {
    final codigo = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogoCodigo(),
    );
    if (codigo == null || !mounted) return;

    setState(() => _procesando = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      await ref.read(enviosRepositoryProvider).confirmarEntrega(
            envioId: widget.envio.id,
            codigo: codigo,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Entrega confirmada')),
      );
      router.goNamed('inicio');
    } on CodigoEntregaInvalido {
      messenger.showSnackBar(
        const SnackBar(content: Text('El codigo no es correcto')),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final envio = widget.envio;
    final accion = _accion;
    final esperandoCodigo = envio.estado == EstadoEnvio.enCamino;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(MySpacing.screenEdge),
              children: [
                MyHeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          MyBadge('#${envio.codigo}', tone: MyBadgeTone.dark),
                          const Spacer(),
                          Text(
                            Formato.pesos(envio.cotizacion.gananciaRepartidor),
                            style: MyType.headlineMd
                                .copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: MySpacing.md),
                      Text(
                        envio.estado.label,
                        style:
                            MyType.headlineLg.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: MySpacing.xxs),
                      Text(
                        switch (envio.estado) {
                          EstadoEnvio.asignado =>
                            'Anda al local a retirar el pedido.',
                          EstadoEnvio.enLocal =>
                            'Avisale al comercio que llegaste.',
                          EstadoEnvio.retirado =>
                            'Ya tenes el pedido. Sali para el domicilio.',
                          EstadoEnvio.enCamino =>
                            'Al llegar, pedile el codigo al cliente.',
                          _ => '',
                        },
                        style:
                            MyType.bodyLg.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: MySpacing.md),
                MyStatRow(
                  tiles: [
                    MyStatTile(
                      icon: Symbols.route,
                      value: Formato.km(envio.cotizacion.distanciaKm),
                      label: 'Total viaje',
                    ),
                    MyStatTile(
                      icon: Symbols.schedule,
                      value: '${envio.cotizacion.minutosEstimados}',
                      label: 'Minutos est.',
                    ),
                  ],
                ),

                const SizedBox(height: MySpacing.md),
                MyRouteTimeline(
                  background: MyColors.surfaceContainerLowest,
                  stops: [
                    MyRouteStop(
                      overline: 'Punto de retiro',
                      title: envio.comercioNombre,
                      subtitle: envio.origen.calle,
                      icon: Symbols.restaurant,
                    ),
                    MyRouteStop(
                      overline: 'Punto de entrega',
                      title: envio.destino.calle,
                      subtitle: envio.destino.referencia,
                      icon: Symbols.home,
                      iconBackground: MyColors.dock,
                    ),
                  ],
                ),

                // Los datos del cliente solo se muestran una vez que el cadete
                // tiene el pedido en la mano: antes no los necesita.
                if (envio.estado.index >= EstadoEnvio.retirado.index) ...[
                  const SizedBox(height: MySpacing.md),
                  MyCard(
                    padding: const EdgeInsets.all(MySpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: const BoxDecoration(
                            color: MyColors.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Symbols.person,
                              size: 23, color: MyColors.primary),
                        ),
                        const SizedBox(width: MySpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const MyOverline('Cliente'),
                              Text(envio.cliente.nombre,
                                  style: MyType.headlineSm),
                              if (envio.cliente.indicaciones != null)
                                Text(
                                  envio.cliente.indicaciones!,
                                  style: MyType.bodySm
                                      .copyWith(color: MyColors.secondary),
                                ),
                            ],
                          ),
                        ),
                        const MyCircleIconButton(
                          icon: Symbols.call,
                          background: MyColors.primary,
                          foreground: MyColors.onPrimary,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Accion principal anclada abajo, al alcance del pulgar.
          Padding(
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            child: _procesando
                ? const Center(child: CircularProgressIndicator())
                : esperandoCodigo
                    ? FilledButton.icon(
                        onPressed: _confirmarEntrega,
                        icon: const Icon(Symbols.verified, size: 22),
                        label: const Text('Confirmar entrega'),
                      )
                    : accion == null
                        ? const SizedBox.shrink()
                        : FilledButton.icon(
                            onPressed: () => _avanzar(accion.siguiente),
                            icon: Icon(accion.icon, size: 22),
                            label: Text(accion.label),
                          ),
          ),
        ],
      ),
    );
  }
}

/// Pide el codigo de 4 digitos que el cliente le dicta al cadete.
class _DialogoCodigo extends StatefulWidget {
  const _DialogoCodigo();

  @override
  State<_DialogoCodigo> createState() => _DialogoCodigoState();
}

class _DialogoCodigoState extends State<_DialogoCodigo> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Codigo de entrega'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pedile al cliente los 4 digitos que ve en su pedido.',
            style: MyType.bodyMd.copyWith(color: MyColors.secondary),
          ),
          const SizedBox(height: MySpacing.md),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: MyType.displayLg,
            decoration: const InputDecoration(counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

/// B7 - Servicio finalizado.
class _Finalizado extends StatelessWidget {
  const _Finalizado({required this.onVolver});

  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return MyEmptyState(
      icon: Symbols.check_circle,
      title: 'Servicio finalizado',
      message: 'La ganancia ya quedo registrada en tu historial.',
      action: FilledButton(
        onPressed: onVolver,
        child: const Text('Volver al inicio'),
      ),
    );
  }
}
