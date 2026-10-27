import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Mi dinero (local): qué entró en el período, qué se le descuenta y cuánto
/// le queda, con el renglón por renglón.
///
/// Es la misma hoja que mira la administración y la misma que mira el rider en
/// su app. Antes el local no veía nada: ni la mensualidad, ni la publicidad, ni
/// la penalidad por rechazar un pedido ya cobrado. Como el saldo le llegaba sin
/// explicación, el único camino era llamar a preguntar.
class DineroLocalPage extends ConsumerStatefulWidget {
  const DineroLocalPage({super.key});

  @override
  ConsumerState<DineroLocalPage> createState() => _DineroLocalPageState();
}

enum _Vista { enCurso, cerradas }

class _DineroLocalPageState extends ConsumerState<DineroLocalPage> {
  var _vista = _Vista.enCurso;
  var _rango = RangoDePeriodo.estaSemana;

  @override
  Widget build(BuildContext context) {
    final cerradas = ref.watch(misLiquidacionesDeComercioProvider).value?.length ?? 0;

    return MyPagina(
      rotulo: 'Dinero',
      titulo: 'Mi liquidación',
      bajada: 'Lo que te queda del período y lo que ya se cerró',
      children: [
        MyFiltros<_Vista>(
          opciones: [
            (_Vista.enCurso, 'Período en curso', -1),
            (_Vista.cerradas, 'Cerradas', cerradas),
          ],
          seleccionado: _vista,
          onChanged: (v) => setState(() => _vista = v),
        ),
        const SizedBox(height: MySpacing.lg),
        switch (_vista) {
          _Vista.enCurso => _EnCurso(
              rango: _rango,
              onRango: (r) => setState(() => _rango = r),
            ),
          _Vista.cerradas => const _Cerradas(),
        },
      ],
    );
  }
}

class _EnCurso extends ConsumerWidget {
  const _EnCurso({required this.rango, required this.onRango});

  final RangoDePeriodo rango;
  final ValueChanged<RangoDePeriodo> onRango;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (desde, hasta) = rango.periodo;
    final periodo = (desde: desde, hasta: hasta);
    final resumen = ref.watch(miLiquidacionDeComercioProvider(periodo));

    // El resumen llega en vivo y la hoja se pide una vez. Si entra un pedido
    // mientras la pantalla está abierta, el número de arriba cambiaría y el
    // detalle de abajo no: quedarían contradiciéndose en la misma pantalla.
    ref.listen(pendientesComerciosProvider(periodo), (_, _) {
      ref.invalidate(detalleDeComercioProvider);
      ref.invalidate(cargosDelPeriodoComercioProvider);
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
          onReintentar: () => ref.invalidate(pendientesComerciosProvider(periodo)),
          datos: (r) {
            // Sin ventas ni cargos la función no devuelve fila (ver 0065): no es
            // un error, es que todavía no pasó nada en el período.
            if (r == null) {
              return const MyCard(
                child: MyEmptyState(
                  icon: Symbols.receipt_long,
                  title: 'Todavía no hay nada en este período',
                  message: 'Cuando entregues tu primer pedido, acá vas a ver cuánto te queda.',
                ),
              );
            }
            final espacio = const SizedBox(height: MySpacing.md);
            final hoja = MyHojaDeComercio(
              resumen: r,
              desde: desde,
              hasta: hasta,
              paraElMismo: true,
            );
            final resaltado = _Saldo(resumen: r);

            if (context.esMovil) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [resaltado, espacio, hoja, espacio, const _ComoSeCalcula()],
              );
            }
            // En la PC el saldo y la explicación van al costado: la hoja es
            // larga y se lee mejor ocupando su propia columna.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: hoja),
                const SizedBox(width: MySpacing.lg),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [resaltado, espacio, const _ComoSeCalcula()],
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

/// El número grande: lo que le queda del período.
class _Saldo extends StatelessWidget {
  const _Saldo({required this.resumen});

  final PendienteComercio resumen;

  @override
  Widget build(BuildContext context) {
    final r = resumen;
    final aFavor = r.total >= 0;

    return MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MyBadge(aFavor ? 'TE PAGAMOS' : 'NOS DEBÉS', tone: MyBadgeTone.dark),
          const SizedBox(height: MySpacing.sm),
          Text(
            Formato.pesos(r.total.abs()),
            style: MyType.displayLg.copyWith(color: Colors.white),
          ),
          Text(
            'Vendiste ${Formato.pesos(r.ventas)} en ${r.pedidos} '
            '${r.pedidos == 1 ? "pedido" : "pedidos"}'
            '${r.cargos == 0 ? "" : " y se te descuentan ${Formato.pesos(r.cargos)}"}',
            style: MyType.bodyMd.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

/// Qué entra y qué no en el número, dicho antes de que lo pregunte.
class _ComoSeCalcula extends StatelessWidget {
  const _ComoSeCalcula();

  @override
  Widget build(BuildContext context) {
    return MyCard(
      color: MyColors.secondaryContainer,
      shadows: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Symbols.info, color: MyColors.secondary),
              const SizedBox(width: MySpacing.sm),
              Expanded(child: Text('Cómo sale este número', style: MyType.labelLg)),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Text(
            'Se suma lo que vendiste de tu menú en los pedidos entregados y se '
            'resta la comisión por pedido, lo que cobra Mercado Pago por las '
            'tarjetas, la mensualidad del plan, la publicidad, los envíos que '
            'regalaste con Plus y las penalidades por rechazar un pedido ya '
            'cobrado o no responderlo a tiempo. El envío no entra: esa plata es '
            'de MODO YA, que le paga al rider su parte.',
            style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
          ),
        ],
      ),
    );
  }
}

/// Las liquidaciones ya cerradas. Cada una abre su detalle.
class _Cerradas extends ConsumerWidget {
  const _Cerradas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historial = ref.watch(misLiquidacionesDeComercioProvider);
    final local = ref.watch(comercioActualProvider).value;

    return MyAsync(
      valor: historial,
      onReintentar: () => ref.invalidate(misLiquidacionesDeComercioProvider),
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
                // Tres semanas después "$84.500 del 1 al 7" no se puede
                // explicar: la hoja trae lo que entró en ese cierre.
                onTap: () => mostrarHojaCerrada(
                  context,
                  l,
                  titular: local?.nombre,
                  paraElMismo: true,
                ),
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
                            'Vendiste ${Formato.pesos(l.aFavor)}'
                            '${l.enContra == 0 ? "" : " · descuentos ${Formato.pesos(l.enContra)}"}',
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
