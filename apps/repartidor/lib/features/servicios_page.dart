import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Servicios del rider: el que tiene en curso y los ultimos que hizo.
class ServiciosPage extends ConsumerWidget {
  const ServiciosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envios = ref.watch(enviosDelRepartidorProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Mis servicios'),
        Expanded(
          child: MyAsync(
            valor: envios,
            onReintentar: () => ref.invalidate(enviosDelRepartidorProvider),
            datos: (lista) => lista.isEmpty
                ? const MyEmptyState(
                    icon: Symbols.local_shipping,
                    title: 'Todavía no hiciste servicios',
                    message: 'Cuando aceptes una oferta, aparece acá.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const SizedBox(height: MySpacing.sm),
                    itemBuilder: (_, i) => _FilaServicio(envio: lista[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

MyBadgeTone _tono(EstadoEnvio e) => e.esActivo
    ? MyBadgeTone.ember
    : (e == EstadoEnvio.entregado ? MyBadgeTone.success : MyBadgeTone.danger);

class _FilaServicio extends StatelessWidget {
  const _FilaServicio({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    final e = envio;
    return MyCard(
      // El que está en curso se sigue en su pantalla (mapa, botones). Uno
      // terminado no tiene nada que hacer: antes abría esa misma pantalla, que
      // solo decía "Entregado" y "Volver al inicio".
      onTap: e.estado.esActivo
          ? () => context.push('/servicio/${e.id}')
          : () => mostrarHojaLateral(
                context,
                titulo: 'Servicio ${e.codigo}',
                builder: (_) => _DetalleServicio(envio: e),
              ),
      color: e.estado.esActivo ? MyColors.primaryFixed : MyColors.surfaceContainerLowest,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MyOverline(e.codigo),
                    const SizedBox(width: MySpacing.xs),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: MyBadge(e.estado.label, tone: _tono(e.estado)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MySpacing.xxs),
                Text(e.nombreRetiro, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  'A ${e.destino.calle}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('${Formato.fechaCorta(e.creadoEn)} ${Formato.hora(e.creadoEn)}',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary)),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          Text(Formato.pesos(e.cotizacion.gananciaRepartidor), style: MyType.headlineSm.copyWith(color: MyColors.tertiary)),
        ],
      ),
    );
  }
}

/// Lo que pasó con un servicio terminado: por dónde fue, cuándo y cuánto ganó
/// (y cuánta plata juntó en la puerta, que después rinde).
class _DetalleServicio extends StatelessWidget {
  const _DetalleServicio({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    final e = envio;
    final o = e.origen;
    final d = e.destino;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: MySpacing.xs,
          runSpacing: MySpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MyBadge(e.estado.label, tone: _tono(e.estado)),
            Text(
              '${Formato.fechaCorta(e.entregadoEn ?? e.creadoEn)} ${Formato.hora(e.entregadoEn ?? e.creadoEn)}',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
          ],
        ),
        if (e.estado == EstadoEnvio.cancelado && e.motivoCancelacion != null) ...[
          const SizedBox(height: MySpacing.sm),
          Text(e.motivoCancelacion!, style: MyType.bodyMd.copyWith(color: MyColors.error)),
        ],
        const SizedBox(height: MySpacing.md),
        MyRouteTimeline(
          background: MyColors.surfaceContainerLowest,
          stops: [
            MyRouteStop(
              overline: 'Retiro',
              title: e.nombreRetiro,
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
        const SizedBox(height: MySpacing.md),
        MyStatRow(tiles: [
          MyStatTile(icon: Symbols.payments, value: Formato.pesos(e.cotizacion.gananciaRepartidor), label: 'Ganaste'),
          MyStatTile(icon: Symbols.route, value: Formato.km(e.cotizacion.distanciaKm), label: 'Viaje'),
        ]),
        // Sin esto un mandado se lee como ganancia pura: lo cobró entero en
        // mano y lo tiene que rendir (0052).
        if (e.hayQueCobrar) ...[
          const SizedBox(height: MySpacing.md),
          MyCard(
            color: MyColors.primaryFixed,
            shadows: const [],
            padding: const EdgeInsets.all(MySpacing.md),
            child: Row(
              children: [
                Icon(Symbols.payments, color: MyColors.onPrimaryFixed),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Text(
                    'Juntaste ${Formato.pesos(e.cobrarAlEntregar)} en la puerta: entra en tu liquidación.',
                    style: MyType.bodyMd.copyWith(color: MyColors.onPrimaryFixed),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
