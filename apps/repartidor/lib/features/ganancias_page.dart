import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Ganancias del rider (B8), calculadas sobre los envios entregados.
///
/// La liquidacion (cada cuanto y por que medio le paga MODO YA) todavia no esta
/// definida, asi que esto es lo ganado, no lo cobrado.
class GananciasPage extends ConsumerWidget {
  const GananciasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envios = ref.watch(enviosDelRepartidorProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Mis ganancias'),
        Expanded(
          child: MyAsync(
            valor: envios,
            datos: (lista) {
              final entregados = lista.where((e) => e.estado == EstadoEnvio.entregado).toList();
              final ahora = DateTime.now();
              bool esHoy(DateTime d) => d.year == ahora.year && d.month == ahora.month && d.day == ahora.day;
              final inicioSemana = DateTime(ahora.year, ahora.month, ahora.day).subtract(Duration(days: ahora.weekday - 1));

              int suma(Iterable<Envio> es) => es.fold(0, (s, e) => s + e.cotizacion.gananciaRepartidor);
              final hoy = entregados.where((e) => esHoy(e.entregadoEn ?? e.creadoEn));
              final semana = entregados.where((e) => (e.entregadoEn ?? e.creadoEn).isAfter(inicioSemana));

              return ListView(
                padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance),
                children: [
                  MyHeroCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const MyBadge('HOY', tone: MyBadgeTone.dark),
                        const SizedBox(height: MySpacing.sm),
                        Text(Formato.pesos(suma(hoy)), style: MyType.displayLg.copyWith(color: Colors.white)),
                        Text('${hoy.length} viaje${hoy.length == 1 ? '' : 's'} entregado${hoy.length == 1 ? '' : 's'}',
                            style: MyType.bodyMd.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.md),
                  MyStatRow(tiles: [
                    MyStatTile(icon: Symbols.date_range, value: Formato.pesos(suma(semana)), label: 'Esta semana'),
                    MyStatTile(icon: Symbols.package_2, value: '${entregados.length}', label: 'Entregados (últimos 100)'),
                  ]),
                  const SizedBox(height: MySpacing.md),
                  MyCard(
                    color: MyColors.secondaryContainer,
                    shadows: const [],
                    child: Row(
                      children: [
                        const Icon(Symbols.info, color: MyColors.secondary),
                        const SizedBox(width: MySpacing.sm),
                        Expanded(
                          child: Text(
                            'MODO YA te liquida lo ganado cada cierto tiempo. La frecuencia y el medio de pago se están definiendo.',
                            style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.lg),
                  Text('Últimos viajes', style: MyType.headlineMd),
                  const SizedBox(height: MySpacing.sm),
                  if (entregados.isEmpty)
                    const MyEmptyState(icon: Symbols.receipt_long, title: 'Sin viajes entregados', message: 'Conectate para empezar.')
                  else
                    for (final e in entregados.take(30)) ...[
                      MyCard(
                        padding: const EdgeInsets.all(MySpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${e.codigo} - ${e.comercioNombre}', style: MyType.labelLg),
                                  Text(
                                    '${Formato.fechaCorta(e.entregadoEn ?? e.creadoEn)} ${Formato.hora(e.entregadoEn ?? e.creadoEn)} - ${Formato.km(e.cotizacion.distanciaKm)}',
                                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                                  ),
                                ],
                              ),
                            ),
                            Text(Formato.pesos(e.cotizacion.gananciaRepartidor), style: MyType.headlineSm.copyWith(color: MyColors.primary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: MySpacing.xs),
                    ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
