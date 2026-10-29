import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';
import 'avisos_mp.dart';
import 'hoja_de_liquidacion.dart';

/// Liquidaciones: qué le queda a cada local y a cada rider en un período.
///
/// La plata la cobra MODO YA (tarjeta en la app) o la junta el rider (el
/// efectivo de los mandados). Acá se arma el reparto:
///
///   Local = lo que vendió − comisión por pedido − cobro con tarjeta
///           − mensualidad − publicidad − ajustes
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
      acciones: [
        // Vivía en la pantalla de cobros, que salió con el pago en efectivo.
        // Acá es donde se mira la plata: si un local dice que un pedido no le
        // entró en la liquidación, lo primero es qué dijo Mercado Pago.
        MyBoton(
          label: 'Avisos de Mercado Pago',
          icon: Symbols.inbox,
          tipo: MyBotonTipo.secundario,
          onPressed: () => mostrarAvisosDeMercadoPago(context),
        ),
      ],
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

/// Cierra la liquidación de un local. Devuelve true si se cerró, para que la
/// hoja desde donde se cerró se pueda ir: ya no tiene nada pendiente que
/// mostrar.
Future<bool> _cerrarComercio(BuildContext context, WidgetRef ref, PendienteComercio p, Periodo periodo) async {
  final ok = await confirmar(
    context,
    titulo: 'Cerrar la liquidación de ${p.comercio}',
    mensaje: p.total >= 0
        ? 'Le vas a pagar ${Formato.pesos(p.total)}. Los pedidos y cargos de este período quedan cerrados.'
        : 'El local te debe ${Formato.pesos(p.total.abs())}. Los pedidos y cargos de este período quedan cerrados.',
    aceptar: 'Cerrar',
  );
  if (!ok) return false;
  try {
    await ref.read(liquidacionesRepositoryProvider).cerrarComercio(p.comercioId, periodo.desde, periodo.hasta);
    if (context.mounted) mostrarAviso(context, 'Liquidación cerrada. Queda en "Cerradas".');
    return true;
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
    return false;
  }
}

Future<bool> _cerrarRider(BuildContext context, WidgetRef ref, PendienteRider p, Periodo periodo) async {
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
  if (!ok) return false;
  try {
    await ref.read(liquidacionesRepositoryProvider).cerrarRider(p.repartidorId, periodo.desde, periodo.hasta);
    if (context.mounted) mostrarAviso(context, 'Liquidación cerrada. Queda en "Cerradas".');
    return true;
  } catch (e) {
    if (context.mounted) mostrarError(context, e);
    return false;
  }
}

/// Una fila de la lista en el celular y la tableta: nombre, saldo y el
/// resumen en un renglón. Tocarla abre la hoja, que es donde están las
/// acciones; sin botones acá, la tarjeta no se parte en dos en 360 px.
class _TarjetaLiquidacion extends StatelessWidget {
  const _TarjetaLiquidacion({required this.nombre, required this.total, required this.resumen, required this.onTap});

  final String nombre;
  final int total;
  final String resumen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(nombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: MySpacing.xs),
                    _Saldo(total),
                  ],
                ),
                const SizedBox(height: MySpacing.xxs),
                Text(resumen, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.xs),
          Icon(Symbols.chevron_right, color: MyColors.secondary),
        ],
      ),
    );
  }
}

class _Locales extends ConsumerWidget {
  const _Locales({required this.periodo});

  final Periodo periodo;

  void _abrir(BuildContext context, WidgetRef ref, PendienteComercio p) => mostrarHojaDeComercio(
        context,
        p,
        periodo.desde,
        periodo.hasta,
        // Las acciones van en la hoja y no en la fila: se cierra mirando el
        // renglón por renglón, no un total suelto.
        acciones: (hoja) => [
          MyBoton(
            label: 'Cargos',
            icon: Symbols.receipt,
            tipo: MyBotonTipo.texto,
            onPressed: () => mostrarCargos(hoja, ref, p.comercioId, p.comercio),
          ),
          MyBoton(
            label: 'Cerrar liquidación',
            icon: Symbols.done_all,
            onPressed: () async {
              if (await _cerrarComercio(hoja, ref, p, periodo) && hoja.mounted) Navigator.pop(hoja);
            },
          ),
        ],
      );

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
        // Seis columnas de plata no entran en una tableta con la barra
        // lateral: hasta la compu van tarjetas.
        if (!context.esEscritorio) {
          return Column(
            children: [
              for (final p in lista) ...[
                _TarjetaLiquidacion(
                  nombre: p.comercio,
                  total: p.total,
                  resumen: '${p.pedidos} pedidos · vendió ${Formato.pesos(p.ventas)} · '
                      'descuentos ${Formato.pesos(p.cargos)}',
                  onTap: () => _abrir(context, ref, p),
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
            MyColumna('', alDerecha: true),
          ],
          filas: [
            for (final p in lista)
              MyFila(
                // Toda la fila abre la hoja con el renglón por renglón: el
                // resumen no alcanza para explicarle un descuento.
                onTap: () => _abrir(context, ref, p),
                celdas: [
                  Text(p.comercio, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${p.pedidos}', style: MyType.bodyMd),
                  Text(Formato.pesos(p.ventas), style: MyType.bodyMd),
                  Text(Formato.pesos(p.cargos), style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  _Saldo(p.total),
                  // El cierre de fin de semana son varios seguidos: en la compu
                  // queda a mano en la fila, además de en la hoja.
                  MyBoton(
                    label: 'Cerrar',
                    icon: Symbols.done_all,
                    tipo: MyBotonTipo.secundario,
                    onPressed: () => _cerrarComercio(context, ref, p, periodo),
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

  void _abrir(BuildContext context, WidgetRef ref, PendienteRider p) => mostrarHojaDeRider(
        context,
        p,
        periodo.desde,
        periodo.hasta,
        acciones: (hoja) => [
          MyBoton(
            label: 'Cerrar liquidación',
            icon: Symbols.done_all,
            onPressed: () async {
              if (await _cerrarRider(hoja, ref, p, periodo) && hoja.mounted) Navigator.pop(hoja);
            },
          ),
        ],
      );

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
        if (!context.esEscritorio) {
          return Column(
            children: [
              for (final p in lista) ...[
                _TarjetaLiquidacion(
                  nombre: p.rider,
                  total: p.total,
                  // El efectivo es el de los mandados: el rider lo cobra en la
                  // puerta y se le descuenta acá.
                  resumen: '${p.envios} envíos · ganó ${Formato.pesos(p.ganancias)} · '
                      'cobró ${Formato.pesos(p.efectivo)} en efectivo'
                      '${p.cargos == 0 ? '' : ' · cargos ${Formato.pesos(p.cargos)}'}',
                  onTap: () => _abrir(context, ref, p),
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
                // Toda la fila abre la hoja: el resumen no alcanza para
                // discutirlo con el rider.
                onTap: () => _abrir(context, ref, p),
                celdas: [
                  Text(p.rider, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  MyBoton(
                    label: 'Cerrar',
                    icon: Symbols.done_all,
                    tipo: MyBotonTipo.secundario,
                    onPressed: () => _cerrarRider(context, ref, p, periodo),
                  ),
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
              _Cerrada(liquidacion: l),
              const SizedBox(height: MySpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _Cerrada extends ConsumerWidget {
  const _Cerrada({required this.liquidacion});

  final Liquidacion liquidacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = liquidacion;
    final estado = l.pagada
        ? const MyBadge('Pagada', tone: MyBadgeTone.success, icon: Symbols.check)
        : MyBoton(
            label: 'Marcar pagada',
            icon: Symbols.payments,
            onPressed: () async {
              try {
                await ref.read(liquidacionesRepositoryProvider).marcarPagada(l);
              } catch (e) {
                if (context.mounted) mostrarError(context, e);
              }
            },
          );
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.nombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          '${Formato.fechaCorta(l.desde)} al ${Formato.fechaCorta(l.hasta)} · '
          '${l.esComercio ? "vendió" : "ganó"} ${Formato.pesos(l.aFavor)} · '
          '${l.esComercio ? "descuentos" : "efectivo"} ${Formato.pesos(l.enContra)}'
          // Los cargos del rider salen de su propia columna: sin nombrarlos, la
          // resta no da el saldo de al lado.
          '${l.ajustes == 0 ? "" : " · cargos ${Formato.pesos(l.ajustes)}"}',
          style: MyType.bodySm.copyWith(color: MyColors.secondary),
        ),
      ],
    );

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      // Tres semanas después "$84.500 del 1 al 7" no se puede explicar: la
      // hoja trae lo que entró en ese cierre.
      onTap: () => mostrarHojaCerrada(context, l),
      // En una fila sola, icono + textos + saldo + "Marcar pagada" no entran en
      // un celular: el botón baja a su propio renglón.
      child: MyResponsivo(
        builder: (context, _, ancho) {
          final icono = MyIconoCaja(l.esComercio ? Symbols.storefront : Symbols.sports_motorsports);
          if (ancho < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icono,
                    const SizedBox(width: MySpacing.sm),
                    Expanded(child: textos),
                    const SizedBox(width: MySpacing.xs),
                    _Saldo(l.total),
                  ],
                ),
                const SizedBox(height: MySpacing.sm),
                Align(alignment: Alignment.centerRight, child: estado),
              ],
            );
          }
          return Row(
            children: [
              icono,
              const SizedBox(width: MySpacing.sm),
              Expanded(child: textos),
              const SizedBox(width: MySpacing.sm),
              _Saldo(l.total),
              const SizedBox(width: MySpacing.sm),
              estado,
            ],
          );
        },
      ),
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
  final _form = GlobalKey<FormState>();
  final _detalle = TextEditingController();
  final _monto = TextEditingController();
  var _concepto = 'mensualidad';

  static const _conceptos = {
    'mensualidad': 'Mensualidad del plan',
    'publicidad': 'Publicidad',
    'ajuste': 'Ajuste',
  };

  /// Un ejemplo distinto para cada concepto: "Plan Básico de septiembre" en un
  /// ajuste confunde más de lo que ayuda.
  static const _ejemplos = {
    'mensualidad': 'Plan Básico de septiembre',
    'publicidad': 'Destacado en el inicio, semana del 20',
    'ajuste': 'Penalidad por rechazar P-1234',
  };

  @override
  void dispose() {
    _detalle.dispose();
    _monto.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    // La validación va al lado de cada campo: antes un aviso flotante decía
    // "Escribí un detalle y un monto" sin señalar cuál faltaba.
    if (!_form.currentState!.validate()) return;
    try {
      await ref.read(liquidacionesRepositoryProvider).agregarCargo(
            comercioId: widget.comercioId,
            concepto: _concepto,
            detalle: _detalle.text.trim(),
            // Respeta el signo: un negativo es una devolución (0035) y es la
            // única forma de devolverle una penalidad ya liquidada, porque
            // borrar el cargo no recalcula los totales guardados.
            monto: MilesFormatter.leer(_monto.text)!,
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
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nuevo cargo', style: MyType.headlineSm),
              const SizedBox(height: MySpacing.xxs),
              Text(
                'Se le descuenta de lo que cobra en su próxima liquidación. '
                'Un monto negativo se lo devuelve.',
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
              const SizedBox(height: MySpacing.md),
              const MyOverline('Qué es'),
              const SizedBox(height: MySpacing.xs),
              Wrap(
                spacing: MySpacing.xs,
                runSpacing: MySpacing.xs,
                children: [
                  for (final e in _conceptos.entries)
                    MyChip(e.value, selected: _concepto == e.key, onTap: () => setState(() => _concepto = e.key)),
                ],
              ),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: _detalle,
                label: 'Detalle',
                hint: _ejemplos[_concepto],
                icon: Symbols.description,
              ),
              MyCampo(
                controller: _monto,
                label: 'Cuánto',
                hint: '15.000 · -15.000 para devolverle',
                icon: Symbols.payments,
                // `soloNumeros` filtra con `digitsOnly`, que se come el signo
                // mientras se tipea: el campo quedaba sin forma de cargar una
                // devolución.
                miles: true,
                negativos: true,
                validar: (v) {
                  final n = MilesFormatter.leer(v);
                  if (n == null || n == 0) return 'Escribí un monto distinto de cero';
                  return null;
                },
              ),
              MyBotonAccion(label: 'Agregar cargo', icon: Symbols.add, onPressed: _agregar),
            ],
          ),
        ),
        const Divider(height: MySpacing.xl),
        Text('Cargados', style: MyType.headlineSm),
        const SizedBox(height: MySpacing.xs),
        if (cargos.isEmpty)
          Text('Todavía no tiene cargos.', style: MyType.bodyMd.copyWith(color: MyColors.secondary))
        else
          for (final c in cargos) _Cargo(cargo: c),
      ],
    );
  }
}

class _Cargo extends ConsumerWidget {
  const _Cargo({required this.cargo});

  final CargoComercio cargo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = cargo;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
      child: Row(
        children: [
          Icon(
            switch (c.concepto) {
              'publicidad' => Symbols.campaign,
              'ajuste' => Symbols.tune,
              _ => Symbols.card_membership,
            },
            color: MyColors.secondary,
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.detalle, style: MyType.labelMd, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  '${Formato.fechaCorta(c.fecha)}'
                  // Un negativo no es un descuento: hay que poder distinguirlo
                  // de un ojo, o la lista se lee como si se le cobrara todo.
                  '${c.monto < 0 ? ' · se le devuelve' : ''}'
                  '${c.liquidado ? ' · ya liquidado' : ''}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.xs),
          Text(
            Formato.pesos(c.monto),
            style: MyType.labelLg.copyWith(color: c.monto < 0 ? MyColors.tertiary : null),
          ),
          if (!c.liquidado)
            IconButton(
              tooltip: 'Borrar',
              icon: Icon(Symbols.delete, size: 20, color: MyColors.error),
              // La lista es un stream: si la liquidación se cerró desde otro
              // dispositivo y el evento no llegó, el botón todavía está acá y
              // la base rebota el borrado. Sin mostrar el error el toque no
              // hacía nada y no se entendía por qué.
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
    );
  }
}
