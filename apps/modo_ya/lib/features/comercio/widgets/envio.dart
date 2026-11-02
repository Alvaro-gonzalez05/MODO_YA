import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'envio_tile.dart';

/// Abre el seguimiento de un envío encima de lo que se está mirando: panel al
/// costado en la compu, hoja desde abajo en el celular.
///
/// Desde el inicio, la lista de envíos y el pedido listo. Antes cada uno
/// navegaba a la pestaña Envíos y el local perdía lo que estaba mirando.
Future<void> mostrarDetalleEnvio(BuildContext context, String envioId) => mostrarHojaLateral(
      context,
      titulo: 'Seguimiento del envío',
      builder: (_) => DetalleEnvio(envioId: envioId),
    );

/// Una lista de envíos en una hoja (los que están en la calle, los entregados
/// hoy). Con uno solo va directo a su seguimiento.
Future<void> mostrarEnvios(
  BuildContext context, {
  required String titulo,
  required bool Function(Envio) filtro,
  required List<Envio> ahora,
}) {
  final visibles = ahora.where(filtro).toList();
  if (visibles.length == 1) return mostrarDetalleEnvio(context, visibles.first.id);
  return mostrarHojaLateral(
    context,
    titulo: titulo,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final lista = (ref.watch(enviosDelComercioProvider).value ?? ahora).where(filtro).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: MyType.headlineMd),
            const SizedBox(height: MySpacing.md),
            if (lista.isEmpty)
              const MyEmptyState(icon: Symbols.sports_motorsports, title: 'Nada por acá', message: 'No hay envíos en este grupo.')
            else
              for (final e in lista) ...[
                EnvioTile(envio: e, onTap: () => mostrarDetalleEnvio(context, e.id)),
                const SizedBox(height: MySpacing.sm),
              ],
          ],
        );
      },
    ),
  );
}

/// El seguimiento en una sola columna, para la hoja. Se actualiza solo.
class DetalleEnvio extends ConsumerWidget {
  const DetalleEnvio({super.key, required this.envioId});

  final String envioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyAsync(
      valor: ref.watch(envioProvider(envioId)),
      onReintentar: () => ref.invalidate(envioProvider(envioId)),
      datos: (e) {
        if (e == null) {
          return const MyEmptyState(icon: Symbols.search_off, title: 'Envío no encontrado', message: 'Puede que ya no exista.');
        }
        final partes = PartesDeEnvio(context, ref, e, altoMapa: 200);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            partes.hero,
            if (partes.mapa case final mapa?) ...[const SizedBox(height: MySpacing.md), mapa],
            const SizedBox(height: MySpacing.md),
            ...partes.detalle,
          ],
        );
      },
    );
  }
}

/// Las piezas del seguimiento. La hoja las apila en una columna y la pantalla
/// completa (`SeguimientoPage`) las reparte en dos; armarlas en un solo lugar
/// evita que una muestre algo que la otra no.
class PartesDeEnvio {
  factory PartesDeEnvio(BuildContext context, WidgetRef ref, Envio envio, {required double altoMapa}) {
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
              // Un envío en `cotizado` es uno que se creó y nunca salió a
              // buscar: antes la bajada quedaba vacía y no había nada que
              // tocar más que cancelarlo (0067).
              EstadoEnvio.cotizado => 'Se creó pero todavía no salió a buscar rider.',
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
            alto: altoMapa,
            radio: MyRadius.card,
            interactivo: !context.esMovil,
            marcadores: [
              MyMarcador(punto: LatLng(o.lat!, o.lng!), icono: Symbols.storefront),
              MyMarcador(punto: LatLng(d.lat!, d.lng!), icono: Symbols.home, color: MyColors.dock),
            ],
          )
        : null;

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
                      Text(envio.repartidorNombre!, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  style: MyType.displayLg.copyWith(color: MyColors.tertiary),
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
          MyRenglon('Distancia', Formato.km(envio.cotizacion.distanciaKm)),
          MyRenglon('Rider', Formato.pesos(envio.cotizacion.gananciaRepartidor)),
          MyRenglon('Comisión MODO YA', Formato.pesos(envio.cotizacion.comision)),
          MyRenglon('Paga', envio.quienPaga == QuienPaga.comercio ? 'Vos' : 'El cliente'),
          const Divider(height: MySpacing.lg),
          MyRenglon('Total', Formato.pesos(envio.total), fuerte: true, color: MyColors.tertiary),
          if (envio.retiradoEn != null) MyRenglon('Retirado', Formato.hora(envio.retiradoEn!)),
          if (envio.entregadoEn != null) MyRenglon('Entregado', Formato.hora(envio.entregadoEn!)),
        ],
      ),
    );

    // La salida de un envío trabado en `cotizado`: el local decide si todavía
    // quiere el viaje. Si no toca nada, a los 15 minutos lo cancela el cron
    // (`vencer_envios_cotizados`, 0067).
    final buscar = envio.estado == EstadoEnvio.cotizado
        ? MyBotonAccion(
            label: 'Buscar rider ahora',
            icon: Symbols.sports_motorsports,
            onPressed: () async {
              try {
                await ref.read(enviosRepositoryProvider).confirmarBusqueda(envio.id);
              } catch (e) {
                if (context.mounted) mostrarError(context, e);
              }
            },
          )
        : null;

    // Con el paquete en la mano del rider (`retirado` o `en_camino`) ya no se
    // cancela: la base lo rechaza desde 0079. Antes el botón aparecía en
    // `retirado` y, en un pedido de la app, le devolvía todo al cliente.
    final cancelar = !envio.estado.esFinal && envio.estado != EstadoEnvio.retirado && envio.estado != EstadoEnvio.enCamino
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

    return PartesDeEnvio._(
      hero: hero,
      mapa: mapa,
      rider: rider,
      recorrido: recorrido,
      codigo: codigo,
      dinero: dinero,
      buscar: buscar,
      cancelar: cancelar,
    );
  }

  const PartesDeEnvio._({
    required this.hero,
    required this.mapa,
    required this.rider,
    required this.recorrido,
    required this.codigo,
    required this.dinero,
    required this.buscar,
    required this.cancelar,
  });

  final Widget hero;
  final Widget? mapa;
  final Widget? rider;
  final Widget recorrido;
  final Widget? codigo;
  final Widget dinero;
  final Widget? buscar;
  final Widget? cancelar;

  /// Todo lo que va debajo del estado y el mapa, en orden.
  List<Widget> get detalle {
    const espacio = SizedBox(height: MySpacing.md);
    return [
      if (rider case final r?) ...[r, espacio],
      recorrido,
      if (codigo case final c?) ...[espacio, c],
      espacio,
      dinero,
      if (buscar case final b?) ...[const SizedBox(height: MySpacing.lg), b],
      if (cancelar case final c?) ...[
        SizedBox(height: buscar == null ? MySpacing.lg : MySpacing.sm),
        Align(alignment: Alignment.centerLeft, child: c),
      ],
    ];
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
    bool hecho(int i) => estado.index >= _pasos[i].$1.index;
    Color tramo(int i) => i < 0 || i >= _pasos.length
        ? Colors.transparent
        : (hecho(i) ? Colors.white : Colors.white30);

    // Cada paso ocupa un cuarto del ancho y el rótulo se achica si no entra:
    // con los rótulos a su ancho natural, en la hoja del celular (~290 px) la
    // fila se pasaba del borde.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _pasos.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    // La mitad de la línea que llega a este paso y la mitad
                    // de la que sale hacia el siguiente.
                    Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : tramo(i))),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: hecho(i) ? Colors.white : Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_pasos[i].$3, size: 18, color: hecho(i) ? MyColors.primary : Colors.white),
                    ),
                    Expanded(child: Container(height: 2, color: tramo(i + 1))),
                  ],
                ),
                const SizedBox(height: MySpacing.xxs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_pasos[i].$2, style: MyType.labelSm.copyWith(color: hecho(i) ? Colors.white : Colors.white70)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
