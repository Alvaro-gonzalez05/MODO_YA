import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Ganancias del rider: lo del día y, sobre todo, **lo que va a cobrar**.
///
/// Antes esta pantalla decía que la liquidación "todavía no está definida". Lo
/// está desde la migración 0035, y desde 0065 el rider puede leer la suya: el
/// mismo documento que mira la administración, con los mismos números. Lo que
/// no se promete es cada cuánto se paga, porque eso lo decide una persona al
/// cerrar el período y no hay nada en el código que lo fije.
class GananciasPage extends ConsumerStatefulWidget {
  const GananciasPage({super.key});

  @override
  ConsumerState<GananciasPage> createState() => _GananciasPageState();
}

enum _Vista { hoy, liquidacion, cerradas }

class _GananciasPageState extends ConsumerState<GananciasPage> {
  var _vista = _Vista.liquidacion;
  var _rango = RangoDePeriodo.estaSemana;

  @override
  Widget build(BuildContext context) {
    final cerradas = ref.watch(misLiquidacionesDeRiderProvider).value?.length ?? 0;

    return Column(
      children: [
        const MyTopBar(zona: 'Mis ganancias'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance),
            children: [
              MyFiltros<_Vista>(
                opciones: [
                  (_Vista.liquidacion, 'Lo que vas a cobrar', -1),
                  (_Vista.cerradas, 'Ya cobradas', cerradas),
                  (_Vista.hoy, 'Hoy', -1),
                ],
                seleccionado: _vista,
                onChanged: (v) => setState(() => _vista = v),
              ),
              const SizedBox(height: MySpacing.md),
              switch (_vista) {
                _Vista.liquidacion => _EnCurso(
                    rango: _rango,
                    onRango: (r) => setState(() => _rango = r),
                  ),
                _Vista.cerradas => const _Cerradas(),
                _Vista.hoy => const _Hoy(),
              },
            ],
          ),
        ),
      ],
    );
  }
}

/// El período en curso: el neto grande arriba y el renglón por renglón abajo.
class _EnCurso extends ConsumerWidget {
  const _EnCurso({required this.rango, required this.onRango});

  final RangoDePeriodo rango;
  final ValueChanged<RangoDePeriodo> onRango;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (desde, hasta) = rango.periodo;
    final periodo = (desde: desde, hasta: hasta);
    final resumen = ref.watch(miLiquidacionDeRiderProvider(periodo));

    // El resumen llega en vivo y la hoja se pide una vez. Si entra un envío
    // mientras la pantalla está abierta, el número de arriba cambiaría y el
    // detalle de abajo no: quedarían contradiciéndose en la misma pantalla.
    ref.listen(pendientesRidersProvider(periodo), (_, _) {
      ref.invalidate(detalleDeRiderProvider);
      ref.invalidate(cargosDelPeriodoRiderProvider);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyFiltros<RangoDePeriodo>(
          opciones: [for (final r in RangoDePeriodo.values) (r, r.rotulo, -1)],
          seleccionado: rango,
          onChanged: onRango,
        ),
        const SizedBox(height: MySpacing.xs),
        Text(rango.texto, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
        const SizedBox(height: MySpacing.md),
        MyAsync(
          valor: resumen,
          onReintentar: () => ref.invalidate(pendientesRidersProvider(periodo)),
          datos: (r) {
            // Sin movimientos la función no devuelve fila (ver 0065): no es un
            // error, es que todavía no hizo nada en el período.
            if (r == null) {
              return const MyCard(
                child: MyEmptyState(
                  icon: Symbols.receipt_long,
                  title: 'Todavía no hay nada en este período',
                  message: 'Cuando entregues tu primer envío, acá vas a ver cuánto te queda.',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyHeroCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MyBadge(
                        r.total >= 0 ? 'TE PAGAMOS' : 'TENÉS QUE RENDIR',
                        tone: MyBadgeTone.dark,
                      ),
                      const SizedBox(height: MySpacing.sm),
                      Text(
                        Formato.pesos(r.total.abs()),
                        style: MyType.displayLg.copyWith(color: MyColors.inverseOnSurface),
                      ),
                      Text(
                        r.total >= 0
                            ? 'Por ${r.envios} ${r.envios == 1 ? "envío" : "envíos"} entregado'
                                '${r.envios == 1 ? "" : "s"}'
                            : 'Juntaste más efectivo del que ganaste',
                        style: MyType.bodyMd.copyWith(color: MyColors.inverseOnSurface.withValues(alpha: 0.72)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.md),
                MyHojaDeRider(resumen: r, desde: desde, hasta: hasta, paraElMismo: true),
                const SizedBox(height: MySpacing.md),
                MyCard(
                  color: MyColors.secondaryContainer,
                  shadows: const [],
                  child: Row(
                    children: [
                      Icon(Symbols.info, color: MyColors.secondary),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Text(
                          'MODO YA cierra el período y te paga lo que quedó. Cuando lo cierre, '
                          'la liquidación pasa a "Ya cobradas" con este mismo detalle.',
                          style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Las liquidaciones que ya se cerraron. Cada una abre su detalle.
class _Cerradas extends ConsumerWidget {
  const _Cerradas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historial = ref.watch(misLiquidacionesDeRiderProvider);
    final yo = ref.watch(repartidorActualProvider).value;

    return MyAsync(
      valor: historial,
      onReintentar: () => ref.invalidate(misLiquidacionesDeRiderProvider),
      datos: (lista) {
        if (lista.isEmpty) {
          return const MyCard(
            child: MyEmptyState(
              icon: Symbols.history,
              title: 'Todavía no te cerraron ninguna',
              message: 'Cuando MODO YA cierre un período, la liquidación queda acá con su detalle.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final l in lista) ...[
              MyCard(
                onTap: () => mostrarHojaCerrada(context, l, titular: yo?.nombre, paraElMismo: true),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${Formato.fechaCorta(l.desde)} al ${Formato.fechaCorta(l.hasta)}',
                            style: MyType.labelLg,
                          ),
                          Text(
                            'Ganaste ${Formato.pesos(l.aFavor)}'
                            '${l.enContra == 0 ? "" : " · rendiste ${Formato.pesos(l.enContra)}"}'
                            '${l.ajustes == 0 ? "" : " · cargos ${Formato.pesos(l.ajustes)}"}',
                            style: MyType.bodySm.copyWith(color: MyColors.secondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          Formato.pesos(l.total),
                          style: MyType.headlineSm.copyWith(
                            color: l.total < 0 ? MyColors.error : MyColors.tertiary,
                          ),
                        ),
                        const SizedBox(height: MySpacing.xxs),
                        MyBadge(
                          l.pagada ? 'Pagada' : 'Pendiente',
                          tone: l.pagada ? MyBadgeTone.success : MyBadgeTone.neutral,
                          icon: l.pagada ? Symbols.check : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MySpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

/// Lo del día y los últimos viajes: el dato que el rider mira varias veces por
/// jornada, sin tener que entrar a la liquidación.
///
/// El número grande sale de `pendiente_de_liquidar_riders` con el período
/// "hoy a hoy", la **misma** función que alimenta "Lo que vas a cobrar" y la
/// bandeja de la administración. Antes se calculaba acá sumando
/// `gananciaRepartidor` de los entregados, y era el único de los tres cálculos
/// que podía dar un número de signo distinto al de la liquidación: no restaba
/// el efectivo que el rider junta en la puerta (un mandado se cobra entero en
/// mano, 0052) ni los cargos de 0062. Con dos mandados en el día el cartel
/// decía "HOY $6.000" cuando la liquidación iba a dar negativa y el que tenía
/// que poner plata era el rider.
///
/// La semana también sale de ahí y no de los últimos 100 envíos, que es todo
/// lo que trae `enviosDelRepartidorProvider`: una semana cargada subcontaba sin
/// decirlo.
///
/// Contrapartida asumida: la función descuenta lo que ya entró en una
/// liquidación cerrada. Si la administración cierra un período que incluye hoy,
/// el cartel vuelve a cero. Es correcto —ya se lo pagaron— y es lo mismo que
/// muestra la otra pestaña.
class _Hoy extends ConsumerWidget {
  const _Hoy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final (semanaDesde, semanaHasta) = RangoDePeriodo.estaSemana.periodo;

    final delDia = ref.watch(miLiquidacionDeRiderProvider((desde: hoy, hasta: hoy)));
    final deLaSemana = ref.watch(miLiquidacionDeRiderProvider((desde: semanaDesde, hasta: semanaHasta)));
    final envios = ref.watch(enviosDelRepartidorProvider);

    return MyAsync(
      valor: delDia,
      onReintentar: () => ref.invalidate(pendientesRidersProvider),
      datos: (r) {
        // Sin movimientos la función no devuelve fila (ver 0065): es un día en
        // cero, no un error.
        final total = r?.total ?? 0;
        final ganancias = r?.ganancias ?? 0;
        final efectivo = r?.efectivo ?? 0;
        final cargos = r?.cargos ?? 0;
        final viajes = r?.envios ?? 0;
        final entregados = (envios.value ?? const <Envio>[])
            .where((e) => e.estado == EstadoEnvio.entregado)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyHeroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: MySpacing.xs,
                    children: [
                      const MyBadge('HOY', tone: MyBadgeTone.dark),
                      if (total < 0) const MyBadge('TENÉS QUE RENDIR', tone: MyBadgeTone.dark),
                    ],
                  ),
                  const SizedBox(height: MySpacing.sm),
                  Text(
                    Formato.pesos(total.abs()),
                    style: MyType.displayLg.copyWith(color: MyColors.inverseOnSurface),
                  ),
                  Text(
                    total < 0
                        ? 'Juntaste más de lo que ganaste'
                        : '$viajes viaje${viajes == 1 ? '' : 's'} entregado'
                            '${viajes == 1 ? '' : 's'}',
                    style: MyType.bodyMd.copyWith(color: MyColors.inverseOnSurface.withValues(alpha: 0.72)),
                  ),
                  // El desglose solo cuando hay algo que explicar: si el día es
                  // ganancia pura, repetir el mismo número confunde.
                  if (efectivo != 0 || cargos != 0) ...[
                    const SizedBox(height: MySpacing.xs),
                    Text(
                      'Ganaste ${Formato.pesos(ganancias)}'
                      '${efectivo == 0 ? '' : ' · juntaste ${Formato.pesos(efectivo)} en la puerta'}'
                      '${cargos == 0 ? '' : ' · cargos ${Formato.pesos(cargos)}'}',
                      style: MyType.bodySm.copyWith(color: MyColors.inverseOnSurface.withValues(alpha: 0.72)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: MySpacing.md),
            MyStatRow(tiles: [
              MyStatTile(
                icon: Symbols.date_range,
                value: Formato.pesos(deLaSemana.value?.total ?? 0),
                label: 'Esta semana',
              ),
              MyStatTile(
                icon: Symbols.package_2,
                value: '${deLaSemana.value?.envios ?? 0}',
                label: 'Entregados esta semana',
              ),
            ]),
            const SizedBox(height: MySpacing.lg),
            Text('Últimos viajes', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.sm),
            if (entregados.isEmpty)
              const MyEmptyState(
                icon: Symbols.receipt_long,
                title: 'Sin viajes entregados',
                message: 'Conectate para empezar.',
              )
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
                            Text('${e.codigo} - ${e.nombreRetiro}', style: MyType.labelLg),
                            Text(
                              '${Formato.fechaCorta(e.entregadoEn ?? e.creadoEn)} '
                              '${Formato.hora(e.entregadoEn ?? e.creadoEn)} - '
                              '${Formato.km(e.cotizacion.distanciaKm)}'
                              // Sin esto un mandado se lee como ganancia pura:
                              // el rider cobró el total en mano y tiene que
                              // rendirlo (0052).
                              '${e.hayQueCobrar ? ' · juntaste ${Formato.pesos(e.cobrarAlEntregar)}' : ''}',
                              style: MyType.bodySm.copyWith(color: MyColors.secondary),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Formato.pesos(e.cotizacion.gananciaRepartidor),
                        style: MyType.headlineSm.copyWith(color: MyColors.tertiary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.xs),
              ],
          ],
        );
      },
    );
  }
}
