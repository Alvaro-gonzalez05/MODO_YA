import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';

/// Liquidaciones: qué le queda a cada local y a cada rider en un período.
///
/// La plata la cobra MODO YA (tarjeta en la app) o la junta el rider
/// (efectivo). Acá se arma el reparto:
///
///   Local = lo que vendió − mensualidad − publicidad − ajustes
///   Rider = lo que ganó − el efectivo que cobró y todavía no rindió
///
/// Al cerrar una liquidación, esos pedidos y envíos quedan marcados: no se
/// pueden pagar dos veces.
class LiquidacionesPage extends ConsumerStatefulWidget {
  const LiquidacionesPage({super.key});

  @override
  ConsumerState<LiquidacionesPage> createState() => _LiquidacionesPageState();
}

enum _Vista { locales, riders, historial }

enum _Rango { estaSemana, semanaPasada, esteMes, mesPasado }

class _LiquidacionesPageState extends ConsumerState<LiquidacionesPage> {
  var _vista = _Vista.locales;
  var _rango = _Rango.estaSemana;

  (DateTime, DateTime) get _periodo {
    final hoy = DateTime.now();
    final lunes = DateTime(hoy.year, hoy.month, hoy.day).subtract(Duration(days: hoy.weekday - 1));
    return switch (_rango) {
      _Rango.estaSemana => (lunes, lunes.add(const Duration(days: 6))),
      _Rango.semanaPasada => (lunes.subtract(const Duration(days: 7)), lunes.subtract(const Duration(days: 1))),
      _Rango.esteMes => (DateTime(hoy.year, hoy.month), DateTime(hoy.year, hoy.month + 1, 0)),
      _Rango.mesPasado => (DateTime(hoy.year, hoy.month - 1), DateTime(hoy.year, hoy.month, 0)),
    };
  }

  String get _periodoTexto {
    final (d, h) = _periodo;
    return '${Formato.fechaCorta(d)} al ${Formato.fechaCorta(h)}';
  }

  @override
  Widget build(BuildContext context) {
    final (desde, hasta) = _periodo;
    final periodo = (desde: desde, hasta: hasta);
    final locales = ref.watch(pendientesComerciosProvider(periodo));
    final riders = ref.watch(pendientesRidersProvider(periodo));

    return MyPagina(
      rotulo: 'Dinero',
      titulo: 'Liquidaciones',
      bajada: 'Lo que hay que pagarle a cada local y a cada rider',
      children: [
        MyFiltros<_Rango>(
          opciones: [
            (_Rango.estaSemana, 'Esta semana', -1),
            (_Rango.semanaPasada, 'Semana pasada', -1),
            (_Rango.esteMes, 'Este mes', -1),
            (_Rango.mesPasado, 'Mes pasado', -1),
          ],
          seleccionado: _rango,
          onChanged: (r) => setState(() => _rango = r),
        ),
        const SizedBox(height: MySpacing.xs),
        Text(_periodoTexto, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
        const SizedBox(height: MySpacing.md),
        MyFiltros<_Vista>(
          opciones: [
            (_Vista.locales, 'Locales', locales.value?.length ?? 0),
            (_Vista.riders, 'Riders', riders.value?.length ?? 0),
            (_Vista.historial, 'Cerradas', ref.watch(historialLiquidacionesProvider).value?.length ?? 0),
          ],
          seleccionado: _vista,
          onChanged: (v) => setState(() => _vista = v),
        ),
        const SizedBox(height: MySpacing.lg),
        switch (_vista) {
          _Vista.locales => _Locales(periodo: periodo),
          _Vista.riders => _Riders(periodo: periodo),
          _Vista.historial => const _Historial(),
        },
      ],
    );
  }
}

/// "$12.500 a favor" / "$3.000 en contra", con el color según de qué lado cae.
class _Saldo extends StatelessWidget {
  const _Saldo(this.monto);

  final int monto;

  @override
  Widget build(BuildContext context) {
    final color = monto < 0 ? MyColors.error : MyColors.tertiary;
    return Text(Formato.pesos(monto), style: MyType.headlineSm.copyWith(color: color));
  }
}

class _Locales extends ConsumerWidget {
  const _Locales({required this.periodo});

  final Periodo periodo;

  Future<void> _cerrar(BuildContext context, WidgetRef ref, PendienteComercio p) async {
    final ok = await confirmar(
      context,
      titulo: 'Cerrar la liquidación de ${p.comercio}',
      mensaje: p.total >= 0
          ? 'Le vas a pagar ${Formato.pesos(p.total)}. Los pedidos y cargos de este período quedan cerrados.'
          : 'El local te debe ${Formato.pesos(p.total.abs())}. Los pedidos y cargos de este período quedan cerrados.',
      aceptar: 'Cerrar',
    );
    if (!ok) return;
    try {
      await ref.read(liquidacionesRepositoryProvider).cerrarComercio(p.comercioId, periodo.desde, periodo.hasta);
      if (context.mounted) mostrarAviso(context, 'Liquidación cerrada. Queda en "Cerradas".');
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref.watch(pendientesComerciosProvider(periodo));

    return MyAsync(
      valor: pendientes,
      onReintentar: () => ref.invalidate(pendientesComerciosProvider(periodo)),
      datos: (lista) {
        if (lista.isEmpty) {
          return const MyCard(
            child: MyEmptyState(
              icon: Symbols.storefront,
              title: 'Nada para liquidar',
              message: 'En este período no hubo ventas entregadas ni cargos cargados.',
            ),
          );
        }
        if (context.esMovil) {
          return Column(
            children: [
              for (final p in lista) ...[
                MyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(p.comercio, style: MyType.headlineSm)),
                          _Saldo(p.total),
                        ],
                      ),
                      Text(
                        '${p.pedidos} pedidos · vendió ${Formato.pesos(p.ventas)} · descuentos ${Formato.pesos(p.cargos)}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                      const SizedBox(height: MySpacing.sm),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: MySpacing.xs,
                        children: [
                          MyBoton(
                            label: 'Cargos',
                            icon: Symbols.receipt,
                            tipo: MyBotonTipo.texto,
                            onPressed: () => mostrarCargos(context, ref, p.comercioId, p.comercio),
                          ),
                          MyBoton(label: 'Cerrar', icon: Symbols.done_all, onPressed: () => _cerrar(context, ref, p)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.sm),
              ],
            ],
          );
        }
        return MyTabla(
          columnas: const [
            MyColumna('Local', flex: 2),
            MyColumna('Pedidos'),
            MyColumna('Vendió', alDerecha: true),
            MyColumna('Descuentos', alDerecha: true),
            MyColumna('A pagar', alDerecha: true),
            MyColumna('', flex: 2, alDerecha: true),
          ],
          filas: [
            for (final p in lista)
              MyFila(
                celdas: [
                  Text(p.comercio, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${p.pedidos}', style: MyType.bodyMd),
                  Text(Formato.pesos(p.ventas), style: MyType.bodyMd),
                  Text(Formato.pesos(p.cargos), style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  _Saldo(p.total),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: MySpacing.xs,
                    children: [
                      MyBoton(
                        label: 'Cargos',
                        icon: Symbols.receipt,
                        tipo: MyBotonTipo.texto,
                        onPressed: () => mostrarCargos(context, ref, p.comercioId, p.comercio),
                      ),
                      MyBoton(label: 'Cerrar', icon: Symbols.done_all, onPressed: () => _cerrar(context, ref, p)),
                    ],
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _Riders extends ConsumerWidget {
  const _Riders({required this.periodo});

  final Periodo periodo;

  Future<void> _cerrar(BuildContext context, WidgetRef ref, PendienteRider p) async {
    final ok = await confirmar(
      context,
      titulo: 'Cerrar la liquidación de ${p.rider}',
      mensaje: p.total >= 0
          ? 'Le vas a pagar ${Formato.pesos(p.total)} por ${p.envios} envíos.'
          : 'Cobró ${Formato.pesos(p.efectivo)} en la calle y ganó ${Formato.pesos(p.ganancias)}: tiene que rendirte ${Formato.pesos(p.total.abs())}.',
      aceptar: 'Cerrar',
    );
    if (!ok) return;
    try {
      await ref.read(liquidacionesRepositoryProvider).cerrarRider(p.repartidorId, periodo.desde, periodo.hasta);
      if (context.mounted) mostrarAviso(context, 'Liquidación cerrada. Queda en "Cerradas".');
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = ref.watch(pendientesRidersProvider(periodo));

    return MyAsync(
      valor: pendientes,
      onReintentar: () => ref.invalidate(pendientesRidersProvider(periodo)),
      datos: (lista) {
        if (lista.isEmpty) {
          return const MyCard(
            child: MyEmptyState(
              icon: Symbols.sports_motorsports,
              title: 'Nada para liquidar',
              message: 'En este período ningún rider entregó envíos.',
            ),
          );
        }
        if (context.esMovil) {
          return Column(
            children: [
              for (final p in lista) ...[
                MyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(p.rider, style: MyType.headlineSm)),
                          _Saldo(p.total),
                        ],
                      ),
                      Text(
                        '${p.envios} envíos · ganó ${Formato.pesos(p.ganancias)} · cobró ${Formato.pesos(p.efectivo)}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                      const SizedBox(height: MySpacing.sm),
                      Align(
                        alignment: Alignment.centerRight,
                        child: MyBoton(label: 'Cerrar', icon: Symbols.done_all, onPressed: () => _cerrar(context, ref, p)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.sm),
              ],
            ],
          );
        }
        return MyTabla(
          columnas: const [
            MyColumna('Rider', flex: 2),
            MyColumna('Envíos'),
            MyColumna('Ganó', alDerecha: true),
            MyColumna('Cobró en efectivo', alDerecha: true),
            MyColumna('Saldo', alDerecha: true),
            MyColumna('', alDerecha: true),
          ],
          filas: [
            for (final p in lista)
              MyFila(
                celdas: [
                  Text(p.rider, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${p.envios}', style: MyType.bodyMd),
                  Text(Formato.pesos(p.ganancias), style: MyType.bodyMd),
                  Text(Formato.pesos(p.efectivo), style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  _Saldo(p.total),
                  MyBoton(label: 'Cerrar', icon: Symbols.done_all, onPressed: () => _cerrar(context, ref, p)),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _Historial extends ConsumerWidget {
  const _Historial();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historial = ref.watch(historialLiquidacionesProvider);

    return MyAsync(
      valor: historial,
      onReintentar: () => ref.invalidate(historialLiquidacionesProvider),
      datos: (lista) {
        if (lista.isEmpty) {
          return const MyCard(
            child: MyEmptyState(
              icon: Symbols.history,
              title: 'Todavía no cerraste ninguna',
              message: 'Cuando cierres una liquidación, queda acá con su detalle.',
            ),
          );
        }
        return Column(
          children: [
            for (final l in lista) ...[
              MyCard(
                child: Row(
                  children: [
                    MyIconoCaja(l.esComercio ? Symbols.storefront : Symbols.sports_motorsports),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l.nombre, style: MyType.labelLg),
                          Text(
                            '${Formato.fechaCorta(l.desde)} al ${Formato.fechaCorta(l.hasta)} · '
                            '${l.esComercio ? "vendió" : "ganó"} ${Formato.pesos(l.aFavor)} · '
                            '${l.esComercio ? "descuentos" : "efectivo"} ${Formato.pesos(l.enContra)}',
                            style: MyType.bodySm.copyWith(color: MyColors.secondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: MySpacing.sm),
                    _Saldo(l.total),
                    const SizedBox(width: MySpacing.sm),
                    if (l.pagada)
                      const MyBadge('Pagada', tone: MyBadgeTone.success, icon: Symbols.check)
                    else
                      MyBoton(
                        label: 'Marcar pagada',
                        icon: Symbols.payments,
                        onPressed: () async {
                          try {
                            await ref.read(liquidacionesRepositoryProvider).marcarPagada(l);
                          } catch (e) {
                            if (context.mounted) mostrarError(context, e);
                          }
                        },
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

/// Cargos de un local: la mensualidad del plan, la publicidad y los ajustes.
Future<void> mostrarCargos(BuildContext context, WidgetRef ref, String comercioId, String nombre) =>
    mostrarFormularioEmergente(
      context,
      titulo: 'Cargos de $nombre',
      builder: (h) => _Cargos(comercioId: comercioId),
    );

class _Cargos extends ConsumerStatefulWidget {
  const _Cargos({required this.comercioId});

  final String comercioId;

  @override
  ConsumerState<_Cargos> createState() => _CargosState();
}

class _CargosState extends ConsumerState<_Cargos> {
  final _detalle = TextEditingController();
  final _monto = TextEditingController();
  var _concepto = 'mensualidad';

  static const _conceptos = {
    'mensualidad': 'Mensualidad del plan',
    'publicidad': 'Publicidad',
    'ajuste': 'Ajuste',
  };

  @override
  void dispose() {
    _detalle.dispose();
    _monto.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    final monto = int.tryParse(_monto.text.replaceAll(RegExp(r'\D'), ''));
    if (monto == null || monto == 0 || _detalle.text.trim().isEmpty) {
      mostrarError(context, 'Escribí un detalle y un monto.');
      return;
    }
    try {
      await ref.read(liquidacionesRepositoryProvider).agregarCargo(
            comercioId: widget.comercioId,
            concepto: _concepto,
            detalle: _detalle.text.trim(),
            monto: monto,
          );
      _detalle.clear();
      _monto.clear();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cargos = ref.watch(cargosDeComercioProvider(widget.comercioId)).value ?? const <CargoComercio>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: MySpacing.xs,
          children: [
            for (final e in _conceptos.entries)
              ChoiceChip(
                selected: _concepto == e.key,
                onSelected: (_) => setState(() => _concepto = e.key),
                label: Text(e.value),
              ),
          ],
        ),
        const SizedBox(height: MySpacing.sm),
        MyCampo(controller: _detalle, label: 'Detalle', hint: 'Plan Básico de septiembre', icon: Symbols.description),
        MyCampo(
          controller: _monto,
          label: 'Monto a descontarle',
          hint: '15000',
          icon: Symbols.payments,
          soloNumeros: true,
        ),
        MyBotonAccion(label: 'Agregar cargo', icon: Symbols.add, onPressed: _agregar),
        const Divider(height: MySpacing.lg),
        if (cargos.isEmpty)
          Text('Todavía no tiene cargos.', style: MyType.bodyMd.copyWith(color: MyColors.secondary))
        else
          for (final c in cargos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (c.concepto) {
                'publicidad' => Symbols.campaign,
                'ajuste' => Symbols.tune,
                _ => Symbols.card_membership,
              }),
              title: Text(c.detalle, style: MyType.labelMd),
              subtitle: Text(
                '${Formato.fechaCorta(c.fecha)}${c.liquidado ? ' · ya liquidado' : ''}',
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Formato.pesos(c.monto), style: MyType.labelLg),
                  if (!c.liquidado)
                    IconButton(
                      tooltip: 'Borrar',
                      icon: Icon(Symbols.delete, size: 20, color: MyColors.error),
                      onPressed: () => ref.read(liquidacionesRepositoryProvider).borrarCargo(c.id),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
