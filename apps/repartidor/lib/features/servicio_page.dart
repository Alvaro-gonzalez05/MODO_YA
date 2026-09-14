import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Servicio en curso (B4 a B7): ir al local, retirar, llevar y confirmar con
/// el codigo que dicta el cliente.
class ServicioEnCursoPage extends ConsumerWidget {
  const ServicioEnCursoPage({super.key, required this.envioId});

  final String envioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envio = ref.watch(envioProvider(envioId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('Servicio'),
      ),
      body: MyAsync(
        valor: envio,
        datos: (e) => e == null
            ? const MyEmptyState(title: 'Servicio no encontrado', message: 'Puede que lo hayan cancelado.')
            : _Contenido(envio: e),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.envio});

  final Envio envio;

  ({String label, IconData icon, EstadoEnvio siguiente})? get _accion => switch (envio.estado) {
        EstadoEnvio.asignado => (label: 'Llegue al local', icon: Symbols.storefront, siguiente: EstadoEnvio.enLocal),
        EstadoEnvio.enLocal => (label: 'Retire el pedido', icon: Symbols.package_2, siguiente: EstadoEnvio.retirado),
        EstadoEnvio.retirado => (label: 'Salgo para el cliente', icon: Symbols.navigation, siguiente: EstadoEnvio.enCamino),
        _ => null,
      };

  Future<void> _confirmarEntrega(BuildContext context, WidgetRef ref) async {
    final codigo = await showDialog<String>(context: context, builder: (_) => const _DialogoCodigo());
    if (codigo == null) return;
    try {
      await ref.read(enviosRepositoryProvider).confirmarEntrega(envio.id, codigo);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (envio.estado == EstadoEnvio.entregado) return _Finalizado(envio: envio);
    if (envio.estado == EstadoEnvio.cancelado) {
      return MyEmptyState(
        icon: Symbols.cancel,
        title: 'Servicio cancelado',
        message: envio.motivoCancelacion ?? 'El envio se cancelo.',
        action: FilledButton(onPressed: () => context.go('/'), child: const Text('Volver al inicio')),
      );
    }

    final accion = _accion;
    // Los datos del cliente recien cuando el pedido esta en la mano: antes no
    // hacen falta.
    final mostrarCliente = envio.estado.index >= EstadoEnvio.retirado.index;
    final vaAlLocal = envio.estado.index < EstadoEnvio.retirado.index;
    final o = envio.origen;
    final d = envio.destino;

    return Column(
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
                        MyBadge(envio.codigo, tone: MyBadgeTone.dark),
                        const Spacer(),
                        Text(Formato.pesos(envio.cotizacion.gananciaRepartidor),
                            style: MyType.headlineMd.copyWith(color: Colors.white)),
                      ],
                    ),
                    const SizedBox(height: MySpacing.md),
                    Text(
                      vaAlLocal ? 'Anda a ${envio.comercioNombre}' : 'Llevalo a ${d.calle}',
                      style: MyType.headlineLg.copyWith(color: Colors.white),
                    ),
                    Text(
                      switch (envio.estado) {
                        EstadoEnvio.asignado => 'Retira el pedido en ${o.calle}.',
                        EstadoEnvio.enLocal => 'Avisale al local que llegaste y retira el pedido.',
                        EstadoEnvio.retirado => 'Tenes el pedido. Sali para el domicilio.',
                        EstadoEnvio.enCamino => 'Al llegar, pedile el codigo de 4 numeros al cliente.',
                        _ => '',
                      },
                      style: MyType.bodyLg.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MySpacing.md),
              if (o.tieneCoordenadas && d.tieneCoordenadas) ...[
                MyMapaVista(
                  alto: 220,
                  interactivo: true,
                  marcadores: [
                    MyMarcador(punto: LatLng(o.lat!, o.lng!), icono: Symbols.storefront, etiqueta: vaAlLocal ? 'Ir aca' : null),
                    MyMarcador(
                      punto: LatLng(d.lat!, d.lng!),
                      icono: Symbols.home,
                      color: MyColors.dock,
                      etiqueta: vaAlLocal ? null : 'Ir aca',
                    ),
                  ],
                ),
                const SizedBox(height: MySpacing.md),
              ],
              MyRouteTimeline(
                background: MyColors.surfaceContainerLowest,
                stops: [
                  MyRouteStop(
                    overline: 'Retiro',
                    title: envio.comercioNombre,
                    subtitle: [o.calle, if (o.referencia != null) o.referencia!].join(' - '),
                    icon: Symbols.restaurant,
                  ),
                  MyRouteStop(
                    overline: 'Entrega',
                    title: d.calle,
                    subtitle: d.referencia,
                    icon: Symbols.home,
                    iconBackground: MyColors.dock,
                  ),
                ],
              ),
              if (mostrarCliente) ...[
                const SizedBox(height: MySpacing.md),
                MyCard(
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(color: MyColors.secondaryContainer, shape: BoxShape.circle),
                        child: const Icon(Symbols.person, color: MyColors.primary),
                      ),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const MyOverline('Cliente'),
                            Text(envio.cliente.nombre, style: MyType.headlineSm),
                            SelectableText(envio.cliente.telefono, style: MyType.bodyMd),
                            if (envio.cliente.indicaciones != null)
                              Text(envio.cliente.indicaciones!, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copiar telefono',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: envio.cliente.telefono));
                          if (context.mounted) mostrarAviso(context, 'Telefono copiado');
                        },
                        icon: const Icon(Symbols.content_copy, color: MyColors.primary),
                      ),
                    ],
                  ),
                ),
              ],
              if (envio.quienPaga == QuienPaga.cliente && envio.pedidoId == null) ...[
                const SizedBox(height: MySpacing.sm),
                Text(
                  'El envio lo paga el cliente.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            child: envio.estado == EstadoEnvio.enCamino
                ? MyBotonAccion(
                    label: 'Confirmar entrega',
                    icon: Symbols.verified,
                    onPressed: () => _confirmarEntrega(context, ref),
                  )
                : accion == null
                    ? const SizedBox.shrink()
                    : MyBotonAccion(
                        label: accion.label,
                        icon: accion.icon,
                        onPressed: () async {
                          try {
                            await ref.read(enviosRepositoryProvider).avanzar(envio.id, accion.siguiente);
                          } catch (e) {
                            if (context.mounted) mostrarError(context, e);
                          }
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

class _DialogoCodigo extends StatefulWidget {
  const _DialogoCodigo();

  @override
  State<_DialogoCodigo> createState() => _DialogoCodigoState();
}

class _DialogoCodigoState extends State<_DialogoCodigo> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Codigo de entrega'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pedile al cliente los 4 numeros que ve en su pedido.', style: MyType.bodyMd),
          const SizedBox(height: MySpacing.md),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: MyType.displayLg.copyWith(letterSpacing: 8),
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (v) => v.length == 4 ? Navigator.pop(context, v) : null,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          onPressed: () => _c.text.length == 4 ? Navigator.pop(context, _c.text) : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _Finalizado extends StatelessWidget {
  const _Finalizado({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(MySpacing.screenEdge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Symbols.check_circle, size: 72, color: MyColors.success, fill: 1),
              const SizedBox(height: MySpacing.md),
              Text('Entregado', style: MyType.displayLg, textAlign: TextAlign.center),
              Text('Buen trabajo. La ganancia ya quedo registrada.',
                  style: MyType.bodyLg.copyWith(color: MyColors.secondary), textAlign: TextAlign.center),
              const SizedBox(height: MySpacing.lg),
              MyHeroCard(
                child: Column(
                  children: [
                    const MyOverline('Ganaste', color: Colors.white70),
                    Text(Formato.pesos(envio.cotizacion.gananciaRepartidor),
                        style: MyType.displayLg.copyWith(color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: MySpacing.xl),
              FilledButton(onPressed: () => context.go('/'), child: const Text('Volver al inicio')),
            ],
          ),
        ),
      ),
    );
  }
}
