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
    final codigo = await mostrarDialogoAnimado<String>(context, builder: (_) => const _DialogoCodigo());
    if (codigo == null) return;
    try {
      await ref.read(enviosRepositoryProvider).confirmarEntrega(envio.id, codigo);
      if (context.mounted) {
        await mostrarExito(context, titulo: '¡Entregado!', mensaje: 'Buen trabajo. Ya podés tomar el próximo.');
      }
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
        message: envio.motivoCancelacion ?? 'El envío se canceló.',
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
                        EstadoEnvio.retirado => 'Tenés el pedido. Salí para el domicilio.',
                        EstadoEnvio.enCamino => 'Al llegar, pedile el código de 4 números al cliente.',
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
                    MyMarcador(punto: LatLng(o.lat!, o.lng!), icono: Symbols.storefront, etiqueta: vaAlLocal ? 'Ir acá' : null),
                    MyMarcador(
                      punto: LatLng(d.lat!, d.lng!),
                      icono: Symbols.home,
                      color: MyColors.dock,
                      etiqueta: vaAlLocal ? null : 'Ir acá',
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
                        decoration: BoxDecoration(color: MyColors.secondaryContainer, shape: BoxShape.circle),
                        child: Icon(Symbols.person, color: MyColors.onSurface, fill: 1),
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
                        tooltip: 'Copiar teléfono',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: envio.cliente.telefono));
                          if (context.mounted) mostrarAviso(context, 'Teléfono copiado');
                        },
                        icon: Icon(Symbols.content_copy, color: MyColors.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
              // Efectivo o posnet: el rider cobra en la puerta. Bien visible
              // para que no se le pase al entregar.
              if (envio.hayQueCobrar) ...[
                const SizedBox(height: MySpacing.md),
                Container(
                  padding: const EdgeInsets.all(MySpacing.md),
                  decoration: BoxDecoration(
                    color: MyColors.primaryFixed,
                    borderRadius: BorderRadius.circular(MyRadius.card),
                    border: Border.all(color: MyColors.primary, width: 2),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        envio.cobroMetodo == MetodoPago.tarjeta ? Symbols.credit_card : Symbols.payments,
                        color: MyColors.onPrimaryFixed,
                        size: 28,
                      ),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Text(envio.textoCobro, style: MyType.headlineSm.copyWith(color: MyColors.onPrimaryFixed)),
                      ),
                    ],
                  ),
                ),
              ],
              if (envio.quienPaga == QuienPaga.cliente && envio.pedidoId == null) ...[
                const SizedBox(height: MySpacing.sm),
                Text(
                  'El envío lo paga el cliente.',
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
      title: const Text('Código de entrega'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Pedile al cliente los 4 números que ve en su pedido.', style: MyType.bodyMd),
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
              Icon(Symbols.check_circle, size: 72, color: MyColors.success, fill: 1),
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
