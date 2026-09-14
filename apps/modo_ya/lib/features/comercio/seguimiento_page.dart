import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Seguimiento de un envío (A7 a A10). Las cuatro pantallas del diseño son la
/// misma en distintos estados, y se actualiza sola en cuanto el rider avanza.
class SeguimientoPage extends ConsumerWidget {
  const SeguimientoPage({super.key, required this.envioId});

  final String envioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envio = ref.watch(envioProvider(envioId));

    return MyAsync(
      valor: envio,
      datos: (e) => e == null
          ? const MyEmptyState(icon: Symbols.search_off, title: 'Envío no encontrado', message: 'Puede que ya no exista.')
          : _Contenido(envio: e),
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

    final hero = MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MyBadge(envio.codigo, tone: MyBadgeTone.dark),
              const Spacer(),
              if (envio.estado == EstadoEnvio.buscandoRepartidor)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Text(envio.estado.label, style: MyType.headlineLg.copyWith(color: Colors.white)),
          Text(
            switch (envio.estado) {
              EstadoEnvio.buscandoRepartidor => 'Le estamos ofreciendo el envío a los riders más cercanos.',
              EstadoEnvio.asignado => '${envio.repartidorNombre} va para tu local.',
              EstadoEnvio.enLocal => 'El rider llegó. Entregale el pedido.',
              EstadoEnvio.retirado || EstadoEnvio.enCamino => 'En camino al cliente.',
              EstadoEnvio.entregado => 'Entregado y confirmado con código.',
              EstadoEnvio.sinRepartidor => 'Ningún rider pudo tomarlo. Probá de nuevo en unos minutos.',
              EstadoEnvio.cancelado => envio.motivoCancelacion ?? 'Cancelado.',
              _ => '',
            },
            style: MyType.bodyLg.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: MySpacing.lg),
          _Progreso(estado: envio.estado),
        ],
      ),
    );

    final mapa = o.tieneCoordenadas && d.tieneCoordenadas
        ? MyMapaVista(
            alto: context.esMovil ? 220 : 360,
            radio: MyRadius.card,
            interactivo: !context.esMovil,
            marcadores: [
              MyMarcador(punto: LatLng(o.lat!, o.lng!), icono: Symbols.storefront),
              MyMarcador(punto: LatLng(d.lat!, d.lng!), icono: Symbols.home, color: MyColors.dock),
            ],
          )
        : const SizedBox();

    final rider = envio.repartidorNombre == null
        ? null
        : MyCard(
            padding: const EdgeInsets.all(MySpacing.md),
            child: Row(
              children: [
                const MyIconoCaja(Symbols.sports_motorsports, tamano: 52, circular: true),
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
          );

    final recorrido = MyRouteTimeline(
      background: MyColors.surfaceContainerLowest,
      stops: [
        MyRouteStop(overline: 'Retiro', title: envio.comercioNombre, subtitle: o.calle, icon: Symbols.storefront),
        MyRouteStop(
          overline: 'Entrega',
          title: d.calle,
          subtitle: '${envio.cliente.nombre} · ${envio.cliente.telefono}',
          icon: Symbols.home,
          iconBackground: MyColors.dock,
        ),
      ],
    );

    // El código solo si el envío es de cadetería: en uno de la app se lo da el
    // cliente, que lo ve en su celular.
    final codigo = envio.codigoEntrega != null && envio.pedidoId == null && !envio.estado.esFinal
        ? MyCard(
            color: MyColors.primaryFixed,
            shadows: const [],
            child: Column(
              children: [
                const MyOverline('Código de entrega'),
                const SizedBox(height: MySpacing.xs),
                SelectableText(
                  envio.codigoEntrega!.split('').join('  '),
                  style: MyType.displayLg.copyWith(color: MyColors.primary),
                ),
                Text(
                  'Pasáselo a quien recibe (por mensaje o llamada). Se lo dicta al rider al recibir.',
                  style: MyType.bodySm,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        : null;

    final dinero = MyCard(
      child: Column(
        children: [
          _Fila('Distancia', Formato.km(envio.cotizacion.distanciaKm)),
          _Fila('Rider', Formato.pesos(envio.cotizacion.gananciaRepartidor)),
          _Fila('Comisión MODO YA', Formato.pesos(envio.cotizacion.comision)),
          _Fila('Paga', envio.quienPaga.label),
          const Divider(height: MySpacing.lg),
          _Fila('Total', Formato.pesos(envio.total), destacado: true),
          if (envio.retiradoEn != null) _Fila('Retirado', Formato.hora(envio.retiradoEn!)),
          if (envio.entregadoEn != null) _Fila('Entregado', Formato.hora(envio.entregadoEn!)),
        ],
      ),
    );

    final cancelar = !envio.estado.esFinal && envio.estado != EstadoEnvio.enCamino
        ? MyBoton(
            label: 'Cancelar envío',
            icon: Symbols.cancel,
            tipo: MyBotonTipo.peligro,
            onPressed: () async {
              final motivo = await pedirTexto(context, titulo: 'Cancelar ${envio.codigo}', label: 'Motivo', aceptar: 'Cancelar envío');
              if (motivo == null) return;
              try {
                await ref.read(enviosRepositoryProvider).cancelar(envio.id, motivo);
              } catch (e) {
                if (context.mounted) mostrarError(context, e);
              }
            },
          )
        : null;

    const espacio = SizedBox(height: MySpacing.md);
    final columnaDetalle = <Widget>[
      if (rider != null) ...[rider, espacio],
      recorrido,
      if (codigo != null) ...[espacio, codigo],
      espacio,
      dinero,
      if (cancelar != null) ...[const SizedBox(height: MySpacing.lg), cancelar],
    ];

    return MyPagina(
      volver: () => context.canPop() ? context.pop() : context.go('/local/envios'),
      rotulo: envio.pedidoId != null ? 'Pedido de la app' : 'Cadetería',
      titulo: 'Seguimiento',
      bajada: 'Se actualiza solo',
      anchoMaximo: 1180,
      conDock: false,
      children: context.esMovil
          ? [hero, espacio, mapa, espacio, ...columnaDetalle]
          : [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [hero, espacio, mapa]),
                  ),
                  const SizedBox(width: MySpacing.lg),
                  Expanded(
                    flex: 2,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: columnaDetalle),
                  ),
                ],
              ),
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
    // en_camino va después de retirado en el enum, así que el índice alcanza.
    bool hecho(EstadoEnvio e) => estado.index >= e.index;

    return Row(
      children: [
        for (var i = 0; i < _pasos.length; i++) ...[
          if (i > 0)
            Expanded(child: Container(height: 2, color: hecho(_pasos[i].$1) ? Colors.white : Colors.white30)),
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: hecho(_pasos[i].$1) ? Colors.white : Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: Icon(_pasos[i].$3, size: 18, color: hecho(_pasos[i].$1) ? MyColors.primary : Colors.white),
              ),
              const SizedBox(height: MySpacing.xxs),
              Text(_pasos[i].$2, style: MyType.labelSm.copyWith(color: hecho(_pasos[i].$1) ? Colors.white : Colors.white70)),
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
