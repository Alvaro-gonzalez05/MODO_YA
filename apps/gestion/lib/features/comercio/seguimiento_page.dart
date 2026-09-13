import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// A7 a A10 - Seguimiento del envio.
///
/// Las cuatro pantallas del diseno (buscando cadete, cadete asignado, retiro
/// confirmado y entregado) son la misma pantalla en distintos estados, asi que
/// se resuelven con un solo widget que reacciona al estado del envio. Eso evita
/// cuatro rutas que hay que mantener sincronizadas.
class SeguimientoPage extends ConsumerWidget {
  const SeguimientoPage({super.key, required this.envioId});

  final String envioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enviosAsync = ref.watch(enviosDelComercioProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => context.goNamed('comercioInicio'),
        ),
        title: const Text('Seguimiento'),
      ),
      body: enviosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (envios) {
          final envio = envios.where((e) => e.id == envioId).firstOrNull;
          if (envio == null) {
            return const MyEmptyState(
              icon: Symbols.search_off,
              title: 'Envio no encontrado',
              message: 'Puede que se haya cancelado.',
            );
          }
          return _Contenido(envio: envio);
        },
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            children: [
              _Encabezado(envio: envio),
              const SizedBox(height: MySpacing.lg),
              _LineaDeTiempo(estado: envio.estado),
              const SizedBox(height: MySpacing.lg),

              if (envio.repartidorNombre != null) ...[
                _TarjetaCadete(envio: envio),
                const SizedBox(height: MySpacing.md),
              ],

              MyRouteTimeline(
                background: MyColors.surfaceContainerLowest,
                stops: [
                  MyRouteStop(
                    overline: 'Punto de retiro',
                    title: envio.comercioNombre,
                    subtitle: envio.origen.calle,
                    icon: Symbols.storefront,
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

              const SizedBox(height: MySpacing.md),
              _TarjetaImporte(envio: envio),

              // A9: el codigo de entrega aparece recien cuando el pedido salio
              // del local; antes no tiene sentido mostrarlo.
              if (envio.codigoEntrega != null &&
                  envio.estado.index >= EstadoEnvio.retirado.index &&
                  envio.estado != EstadoEnvio.entregado) ...[
                const SizedBox(height: MySpacing.md),
                _CodigoEntrega(codigo: envio.codigoEntrega!),
              ],

              // A10: comprobante.
              if (envio.estado == EstadoEnvio.entregado) ...[
                const SizedBox(height: MySpacing.md),
                _Comprobante(envio: envio),
              ],

              const SizedBox(height: MySpacing.xl),
              if (!envio.estado.esFinal)
                OutlinedButton.icon(
                  onPressed: () => _cancelar(context, ref),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: MyColors.errorContainer,
                    foregroundColor: MyColors.onErrorContainer,
                  ),
                  icon: const Icon(Symbols.cancel, size: 20),
                  label: const Text('Cancelar envio'),
                ),
              const SizedBox(height: MySpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar el envio'),
        content: Text(
          'El pedido #${envio.codigo} se va a cancelar. '
          'Si ya hay un cadete asignado, se le avisa.',
          style: MyType.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar envio'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    await ref
        .read(enviosRepositoryProvider)
        .cancelar(envio.id, 'Cancelado por el comercio');
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    final buscando = envio.estado == EstadoEnvio.buscandoRepartidor;

    return MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MyBadge('Pedido #${envio.codigo}', tone: MyBadgeTone.dark),
              const Spacer(),
              if (buscando)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Text(
            envio.estado.label,
            style: MyType.headlineLg.copyWith(color: Colors.white),
          ),
          const SizedBox(height: MySpacing.xxs),
          Text(
            switch (envio.estado) {
              EstadoEnvio.buscandoRepartidor =>
                'Estamos ofreciendo el envio a los cadetes mas cercanos.',
              EstadoEnvio.asignado =>
                '${envio.repartidorNombre} va camino a tu local.',
              EstadoEnvio.enLocal => 'El cadete llego. Entregale el pedido.',
              EstadoEnvio.retirado => 'El pedido ya salio del local.',
              EstadoEnvio.enCamino => 'En camino al domicilio del cliente.',
              EstadoEnvio.entregado => 'Entrega confirmada con codigo.',
              EstadoEnvio.sinRepartidor =>
                'Ningun cadete acepto a tiempo. Podes volver a intentar.',
              EstadoEnvio.cancelado => envio.motivoCancelacion ?? 'Cancelado.',
              _ => 'Preparando el envio.',
            },
            style: MyType.bodyLg.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Barra de progreso por estados. Marca hasta donde llego el envio.
class _LineaDeTiempo extends StatelessWidget {
  const _LineaDeTiempo({required this.estado});

  final EstadoEnvio estado;

  static const _pasos = [
    (EstadoEnvio.buscandoRepartidor, 'Buscando', Symbols.search),
    (EstadoEnvio.asignado, 'Asignado', Symbols.sports_motorsports),
    (EstadoEnvio.retirado, 'Retirado', Symbols.package_2),
    (EstadoEnvio.entregado, 'Entregado', Symbols.check_circle),
  ];

  @override
  Widget build(BuildContext context) {
    if (estado == EstadoEnvio.cancelado ||
        estado == EstadoEnvio.sinRepartidor) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        for (var i = 0; i < _pasos.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: estado.index >= _pasos[i].$1.index
                    ? MyColors.primary
                    : MyColors.surfaceContainerHighest,
              ),
            ),
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: estado.index >= _pasos[i].$1.index
                      ? MyColors.primary
                      : MyColors.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _pasos[i].$3,
                  size: 18,
                  color: estado.index >= _pasos[i].$1.index
                      ? MyColors.onPrimary
                      : MyColors.secondary,
                  fill: estado.index >= _pasos[i].$1.index ? 1 : 0,
                ),
              ),
              const SizedBox(height: MySpacing.xxs),
              Text(
                _pasos[i].$2,
                style: MyType.labelSm.copyWith(
                  color: estado.index >= _pasos[i].$1.index
                      ? MyColors.primary
                      : MyColors.secondary,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TarjetaCadete extends StatelessWidget {
  const _TarjetaCadete({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: MyColors.primaryFixed,
              shape: BoxShape.circle,
            ),
            child: const Icon(Symbols.sports_motorsports,
                size: 26, color: MyColors.primary),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MyOverline('Tu cadete'),
                Text(envio.repartidorNombre!, style: MyType.headlineSm),
                Text(
                  'Llegada estimada ~${envio.cotizacion.minutosEstimados} min',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
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
    );
  }
}

class _TarjetaImporte extends StatelessWidget {
  const _TarjetaImporte({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        children: [
          MyStatRow(
            tiles: [
              MyStatTile(
                icon: Symbols.route,
                value: Formato.km(envio.cotizacion.distanciaKm),
                label: 'Distancia',
              ),
              MyStatTile(
                icon: Symbols.schedule,
                value: '${envio.cotizacion.minutosEstimados}',
                label: 'Minutos est.',
              ),
              MyStatTile(
                icon: Symbols.payments,
                value: envio.quienPaga == QuienPaga.cliente ? 'Cliente' : 'Vos',
                label: 'Lo paga',
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Row(
            children: [
              Text('Tarifa total', style: MyType.labelLg),
              const Spacer(),
              Text(
                Formato.pesos(envio.total),
                style: MyType.priceHero.copyWith(color: MyColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A9 - Codigo que el cliente le dicta al cadete para cerrar la entrega.
class _CodigoEntrega extends StatelessWidget {
  const _CodigoEntrega({required this.codigo});

  final String codigo;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      color: MyColors.secondaryContainer,
      shadows: const [],
      child: Column(
        children: [
          const MyOverline('Codigo de entrega'),
          const SizedBox(height: MySpacing.xs),
          Text(
            codigo.split('').join('  '),
            style: MyType.displayLg.copyWith(color: MyColors.primary),
          ),
          const SizedBox(height: MySpacing.xs),
          Text(
            'El cliente se lo dicta al cadete al recibir el pedido.',
            style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A10 - Comprobante de la entrega.
class _Comprobante extends StatelessWidget {
  const _Comprobante({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    final duracion = envio.entregadoEn?.difference(envio.creadoEn).inMinutes;

    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.receipt_long,
                  size: 22, color: MyColors.primary),
              const SizedBox(width: MySpacing.xs),
              Text('Comprobante', style: MyType.headlineSm),
            ],
          ),
          const Divider(height: MySpacing.xl),
          _Fila('Pedido', '#${envio.codigo}'),
          _Fila('Cadete', envio.repartidorNombre ?? '-'),
          _Fila('Cliente', envio.cliente.nombre),
          if (envio.retiradoEn != null)
            _Fila('Retirado', Formato.hora(envio.retiradoEn!)),
          if (envio.entregadoEn != null)
            _Fila('Entregado', Formato.hora(envio.entregadoEn!)),
          if (duracion != null) _Fila('Duracion total', '$duracion min'),
          const Divider(height: MySpacing.xl),
          _Fila(
            'Ganancia del cadete',
            Formato.pesos(envio.cotizacion.gananciaRepartidor),
          ),
          _Fila('Comision MODO YA', Formato.pesos(envio.cotizacion.comision)),
          _Fila('Total', Formato.pesos(envio.total), destacado: true),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.label, this.valor, {this.destacado = false});

  final String label;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.xs),
      child: Row(
        children: [
          Text(label, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
          const Spacer(),
          Text(
            valor,
            style: destacado
                ? MyType.headlineSm.copyWith(color: MyColors.primary)
                : MyType.labelLg,
          ),
        ],
      ),
    );
  }
}
