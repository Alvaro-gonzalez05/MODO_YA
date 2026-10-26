import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'hoja_de_liquidacion.dart';

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

class _LiquidacionesPageState extends ConsumerState<LiquidacionesPage> {
  var _vista = _Vista.locales;
  // Cómo se cuentan las semanas y los meses vive en `my_core`: el rider y el
  // local miran los mismos períodos desde sus pantallas.
  var _rango = RangoDePeriodo.estaSemana;

  @override
  Widget build(BuildContext context) {
    final (desde, hasta) = _rango.periodo;
    final periodo = (desde: desde, hasta: hasta);
    final locales = ref.watch(pendientesComerciosProvider(periodo));
    final riders = ref.watch(pendientesRidersProvider(periodo));

    return MyPagina(
      rotulo: 'Dinero',
      titulo: 'Liquidaciones',
      bajada: 'Lo que hay que pagarle a cada local y a cada rider',
      children: [
        MyFiltros<RangoDePeriodo>(
          opciones: [for (final r in RangoDePeriodo.values) (r, r.rotulo, -1)],
          seleccionado: _rango,
          onChanged: (r) => setState(() => _rango = r),
        ),
        const SizedBox(height: MySpacing.xs),
        Text(_rango.texto, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
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
                  // En el celular la hoja entra desde abajo, pero es el mismo
                  // detalle: tocar la tarjeta lo abre.
                  onTap: () => mostrarHojaDeComercio(context, p, periodo.desde, periodo.hasta),
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
                  // El nombre abre la hoja con el renglón por renglón: el
                  // resumen no alcanza para explicarle un descuento.
                  MyPressable(
                    onTap: () => mostrarHojaDeComercio(context, p, periodo.desde, periodo.hasta),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(p.comercio, style: MyType.labelLg,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: MySpacing.xxs),
                        Icon(Symbols.chevron_right, size: 18, color: MyColors.secondary),
                      ],
                    ),
                  ),
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
          : 'Cobró ${Formato.pesos(p.efectivo)} en la calle y ganó ${Formato.pesos(p.ganancias)}'
              '${p.cargos == 0 ? '' : ', con ${Formato.pesos(p.cargos)} de cargos'}'
              ': tiene que rendirte ${Formato.pesos(p.total.abs())}.',
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
                  // En el celular la hoja entra desde abajo, pero es el mismo
                  // detalle: tocar la tarjeta lo abre.
                  onTap: () => mostrarHojaDeRider(context, p, periodo.desde, periodo.hasta),
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
                        '${p.envios} envíos · ganó ${Formato.pesos(p.ganancias)} · cobró ${Formato.pesos(p.efectivo)}'
                        '${p.cargos == 0 ? '' : ' · cargos ${Formato.pesos(p.cargos)}'}',
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
            MyColumna('Cargos', alDerecha: true),
            MyColumna('Saldo', alDerecha: true),
            MyColumna('', alDerecha: true),
          ],
          filas: [
            for (final p in lista)
              MyFila(
                celdas: [
                  // El nombre abre la hoja con el renglón por renglón: el
                  // resumen no alcanza para discutirlo con el rider.
                  MyPressable(
                    onTap: () => mostrarHojaDeRider(context, p, periodo.desde, periodo.hasta),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(p.rider, style: MyType.labelLg,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: MySpacing.xxs),
                        Icon(Symbols.chevron_right, size: 18, color: MyColors.secondary),
                      ],
                    ),
                  ),
                  Text('${p.envios}', style: MyType.bodyMd),
                  Text(Formato.pesos(p.ganancias), style: MyType.bodyMd),
                  Text(Formato.pesos(p.efectivo), style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  Text(
                    p.cargos == 0 ? '—' : Formato.pesos(p.cargos),
                    style: MyType.bodyMd.copyWith(
                      color: p.cargos == 0 ? MyColors.secondary : MyColors.error,
                    ),
                  ),
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
                // Tres semanas después "$84.500 del 1 al 7" no se puede
                // explicar: la hoja trae lo que entró en ese cierre.
                onTap: () => mostrarHojaCerrada(context, l),
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
                            '${l.esComercio ? "descuentos" : "efectivo"} ${Formato.pesos(l.enContra)}'
                            // Los cargos del rider salen de su propia columna:
                            // sin nombrarlos, la resta no da el saldo de al lado.
                            '${l.ajustes == 0 ? "" : " · cargos ${Formato.pesos(l.ajustes)}"}',
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

/// Lee el monto escrito **respetando el signo**.
///
/// Antes el parseo era `int.tryParse(texto.replaceAll(RegExp(r'\D'), ''))`, que
/// borra el `-` antes de leerlo, y el campo era `soloNumeros` así que el signo
/// no se podía ni tipear. Un ajuste negativo era imposible de cargar desde la
/// pantalla, aunque el esquema lo contempla desde 0035 ("Negativo: se le suma,
/// una devolución") y el formulario del rider sí lo permita.
///
/// Es la única vía para devolverle una penalidad a un local cuando ya se
/// liquidó: borrar el cargo no sirve (los totales guardados no se recalculan)
/// y entrar por SQL no es una respuesta.
int? montoConSigno(String texto) {
  final limpio = texto.replaceAll(RegExp(r'[^\d-]'), '');
  final digitos = limpio.replaceAll('-', '');
  if (digitos.isEmpty) return null;
  final n = int.tryParse(digitos);
  if (n == null) return null;
  // El signo cuenta solo adelante: "-1500" devuelve, "1500-" es un tipeo.
  return limpio.startsWith('-') ? -n : n;
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
    final monto = montoConSigno(_monto.text);
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
        Text(
          'Se le descuenta de lo que cobra en su próxima liquidación. '
          'Un monto negativo se lo devuelve.',
          style: MyType.bodySm.copyWith(color: MyColors.secondary),
        ),
        const SizedBox(height: MySpacing.sm),
        MyCampo(controller: _detalle, label: 'Detalle', hint: 'Plan Básico de septiembre', icon: Symbols.description),
        MyCampo(
          controller: _monto,
          label: 'Cuánto',
          hint: '15000 · -15000 para devolverle',
          icon: Symbols.payments,
          keyboard: const TextInputType.numberWithOptions(signed: true),
          // `soloNumeros` filtra con `digitsOnly`, que se come el signo mientras
          // se tipea: el campo quedaba sin forma de cargar una devolución.
          formatos: [FilteringTextInputFormatter.allow(RegExp(r'[\d-]'))],
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
                '${Formato.fechaCorta(c.fecha)}'
                // Un negativo no es un descuento: hay que poder distinguirlo
                // de un ojo, o la lista se lee como si se le cobrara todo.
                '${c.monto < 0 ? ' · se le devuelve' : ''}'
                '${c.liquidado ? ' · ya liquidado' : ''}',
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Formato.pesos(c.monto),
                    style: MyType.labelLg.copyWith(
                      color: c.monto < 0 ? MyColors.tertiary : null,
                    ),
                  ),
                  if (!c.liquidado)
                    IconButton(
                      tooltip: 'Borrar',
                      icon: Icon(Symbols.delete, size: 20, color: MyColors.error),
                      // La lista es un stream: si la liquidación se cerró desde
                      // otro dispositivo y el evento no llegó, el botón todavía
                      // está acá y la base rebota el borrado. Sin mostrar el
                      // error el toque no hacía nada y no se entendía por qué.
                      onPressed: () async {
                        try {
                          await ref.read(liquidacionesRepositoryProvider).borrarCargo(c.id);
                        } catch (e) {
                          if (context.mounted) mostrarError(context, e);
                        }
                      },
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
