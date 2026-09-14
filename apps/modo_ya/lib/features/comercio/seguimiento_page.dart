import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';

/// Seguimiento de un envio (A7 a A10). Las cuatro pantallas del diseno son la
/// misma en distintos estados, y se actualiza sola en cuanto el rider avanza.
class SeguimientoPage extends ConsumerWidget {
  const SeguimientoPage({super.key, required this.envioId});

  final String envioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envio = ref.watch(envioProvider(envioId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/local'),
        ),
        title: const Text('Seguimiento'),
      ),
      body: MyAsync(
        valor: envio,
        datos: (e) => e == null
            ? const MyEmptyState(icon: Symbols.search_off, title: 'Envio no encontrado', message: 'Puede que ya no exista.')
            : _Contenido(envio: e),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = envio.origen;
    final d = envio.destino;

    return FormularioCentrado(
      ancho: 580,
      children: [
        MyHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MyBadge(envio.codigo, tone: MyBadgeTone.dark),
                  const Spacer(),
                  if (envio.estado == EstadoEnvio.buscandoRepartidor)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    ),
                ],
              ),
              const SizedBox(height: MySpacing.md),
              Text(envio.estado.label, style: MyType.headlineLg.copyWith(color: Colors.white)),
              Text(
                switch (envio.estado) {
                  EstadoEnvio.buscandoRepartidor => 'Le estamos ofreciendo el envio a los riders mas cercanos.',
                  EstadoEnvio.asignado => '${envio.repartidorNombre} va para tu local.',
                  EstadoEnvio.enLocal => 'El rider llego. Entregale el pedido.',
                  EstadoEnvio.retirado || EstadoEnvio.enCamino => 'En camino al cliente.',
                  EstadoEnvio.entregado => 'Entregado y confirmado con codigo.',
                  EstadoEnvio.sinRepartidor => 'Ningun rider pudo tomarlo. Proba de nuevo en unos minutos.',
                  EstadoEnvio.cancelado => envio.motivoCancelacion ?? 'Cancelado.',
                  _ => '',
                },
                style: MyType.bodyLg.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.lg),
        _Progreso(estado: envio.estado),
        const SizedBox(height: MySpacing.lg),

        if (o.tieneCoordenadas && d.tieneCoordenadas) ...[
          MyMapaVista(
            alto: 200,
            marcadores: [
              MyMarcador(punto: LatLng(o.lat!, o.lng!), icono: Symbols.storefront),
              MyMarcador(punto: LatLng(d.lat!, d.lng!), icono: Symbols.home, color: MyColors.dock),
            ],
          ),
          const SizedBox(height: MySpacing.md),
        ],

        if (envio.repartidorNombre != null) ...[
          MyCard(
            padding: const EdgeInsets.all(MySpacing.md),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: MyColors.primaryFixed, shape: BoxShape.circle),
                  child: const Icon(Symbols.sports_motorsports, size: 26, color: MyColors.primary),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MyOverline('Tu rider'),
                      Text(envio.repartidorNombre!, style: MyType.headlineSm),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MySpacing.md),
        ],

        MyRouteTimeline(
          background: MyColors.surfaceContainerLowest,
          stops: [
            MyRouteStop(overline: 'Retiro', title: envio.comercioNombre, subtitle: o.calle, icon: Symbols.storefront),
            MyRouteStop(
              overline: 'Entrega',
              title: d.calle,
              subtitle: '${envio.cliente.nombre} - ${envio.cliente.telefono}',
              icon: Symbols.home,
              iconBackground: MyColors.dock,
            ),
          ],
        ),

        // El codigo solo si el envio es de cadeteria: en uno de la app, se lo
        // da el cliente, que lo ve en su celular.
        if (envio.codigoEntrega != null && envio.pedidoId == null && !envio.estado.esFinal) ...[
          const SizedBox(height: MySpacing.md),
          MyCard(
            color: MyColors.primaryFixed,
            shadows: const [],
            child: Column(
              children: [
                const MyOverline('Codigo de entrega'),
                const SizedBox(height: MySpacing.xs),
                SelectableText(
                  envio.codigoEntrega!.split('').join('  '),
                  style: MyType.displayLg.copyWith(color: MyColors.primary),
                ),
                Text(
                  'Pasaselo a quien recibe (por mensaje o llamada). Se lo dicta al rider al recibir.',
                  style: MyType.bodySm,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: MySpacing.md),
        MyCard(
          child: Column(
            children: [
              _Fila('Distancia', Formato.km(envio.cotizacion.distanciaKm)),
              _Fila('Rider', Formato.pesos(envio.cotizacion.gananciaRepartidor)),
              _Fila('Comision MODO YA', Formato.pesos(envio.cotizacion.comision)),
              _Fila('Paga', envio.quienPaga.label),
              const Divider(height: MySpacing.lg),
              _Fila('Total', Formato.pesos(envio.total), destacado: true),
              if (envio.retiradoEn != null) _Fila('Retirado', Formato.hora(envio.retiradoEn!)),
              if (envio.entregadoEn != null) _Fila('Entregado', Formato.hora(envio.entregadoEn!)),
            ],
          ),
        ),

        const SizedBox(height: MySpacing.xl),
        if (!envio.estado.esFinal && envio.estado != EstadoEnvio.enCamino)
          OutlinedButton.icon(
            onPressed: () async {
              final motivo = await pedirTexto(
                context,
                titulo: 'Cancelar ${envio.codigo}',
                label: 'Motivo',
                aceptar: 'Cancelar envio',
              );
              if (motivo == null) return;
              try {
                await ref.read(enviosRepositoryProvider).cancelar(envio.id, motivo);
              } catch (e) {
                if (context.mounted) mostrarError(context, e);
              }
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: MyColors.errorContainer,
              foregroundColor: MyColors.onErrorContainer,
            ),
            icon: const Icon(Symbols.cancel, size: 20),
            label: const Text('Cancelar envio'),
          ),
        const SizedBox(height: MySpacing.xl),
      ],
    );
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.estado});

  final EstadoEnvio estado;

  static const _pasos = [
    (EstadoEnvio.buscandoRepartidor, 'Buscando', Symbols.search),
    (EstadoEnvio.asignado, 'Asignado', Symbols.sports_motorsports),
    (EstadoEnvio.retirado, 'Retirado', Symbols.package_2),
    (EstadoEnvio.entregado, 'Entregado', Symbols.check_circle),
  ];

  @override
  Widget build(BuildContext context) {
    if (estado == EstadoEnvio.cancelado || estado == EstadoEnvio.sinRepartidor) return const SizedBox.shrink();
    // en_camino va despues de retirado en el enum, asi que el indice alcanza.
    bool hecho(EstadoEnvio e) => estado.index >= e.index;

    return Row(
      children: [
        for (var i = 0; i < _pasos.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: hecho(_pasos[i].$1) ? MyColors.primary : MyColors.surfaceContainerHighest,
              ),
            ),
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hecho(_pasos[i].$1) ? MyColors.primary : MyColors.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _pasos[i].$3,
                  size: 18,
                  color: hecho(_pasos[i].$1) ? MyColors.onPrimary : MyColors.secondary,
                ),
              ),
              const SizedBox(height: MySpacing.xxs),
              Text(_pasos[i].$2, style: MyType.labelSm.copyWith(color: hecho(_pasos[i].$1) ? MyColors.primary : MyColors.secondary)),
            ],
          ),
        ],
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila(this.label, this.valor, {this.destacado = false});

  final String label;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MySpacing.xs),
        child: Row(
          children: [
            Text(label, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
            const Spacer(),
            Text(valor, style: destacado ? MyType.headlineSm.copyWith(color: MyColors.primary) : MyType.labelLg),
          ],
        ),
      );
}
