import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/envio.dart';
import 'widgets/envio_tile.dart';
import 'widgets/kpi_cargando.dart';
import 'widgets/pedido.dart';

/// Un indicador que depende de una lectura en vivo: mientras no llegó la
/// primera, se dibuja cargando y no con un cero.
Widget _kpi(
  AsyncValue<Object?> fuente, {
  required String rotulo,
  required IconData icono,
  required VoidCallback reintentar,
  required MyKpi Function() listo,
}) {
  if (fuente.hasValue) return listo();
  if (fuente.hasError) {
    return MyKpi(
      rotulo: rotulo,
      valor: '—',
      icono: icono,
      detalle: 'No se pudo cargar. Tocá para reintentar',
      onTap: reintentar,
    );
  }
  return KpiCargando(rotulo: rotulo, icono: icono);
}

/// Lo que lleva cobrado la semana. Tocarlo abre la hoja de la liquidación al
/// costado, sin salir del inicio.
///
/// Va en el inicio porque es la pregunta que el local se hace sin entrar a
/// buscarla, y porque antes el saldo le llegaba sin que pudiera verlo venir.
class _KpiDeLaSemana extends ConsumerWidget {
  const _KpiDeLaSemana();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (desde, hasta) = RangoDePeriodo.estaSemana.periodo;
    final periodo = (desde: desde, hasta: hasta);
    final resumen = ref.watch(miLiquidacionDeComercioProvider(periodo));

    return _kpi(
      resumen,
      rotulo: 'Vas a cobrar',
      icono: Symbols.payments,
      reintentar: () => ref.invalidate(pendientesComerciosProvider(periodo)),
      listo: () {
        final r = resumen.value;
        return MyKpi(
          rotulo: 'Vas a cobrar',
          // Sin movimientos todavía no hay fila (ver 0065): se muestra un guion
          // en vez de un "$0" que haría pensar que el cálculo dio cero.
          valor: r == null ? '—' : Formato.pesos(r.total),
          icono: Symbols.payments,
          detalle: r == null ? 'Esta semana, sin movimientos' : 'Esta semana · tocá para ver el detalle',
          onTap: r == null
              ? () => context.go('/local/dinero')
              : () => mostrarHojaLateral(
                    context,
                    titulo: 'Esta semana',
                    builder: (hoja) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MyHojaDeComercio(resumen: r, desde: desde, hasta: hasta, paraElMismo: true),
                        const SizedBox(height: MySpacing.md),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: MyBoton(
                            label: 'Ver liquidaciones cerradas',
                            icon: Symbols.history,
                            tipo: MyBotonTipo.secundario,
                            onPressed: () {
                              Navigator.of(hoja).pop();
                              context.go('/local/dinero');
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
        );
      },
    );
  }
}

/// Inicio del local (A4): estado, pedidos por atender, pedir un rider y los
/// envíos de hoy.
///
/// Todo lo que se toca acá se abre en el lugar (pedido, envío, liquidación):
/// el inicio es lo que el local deja abierto mientras trabaja, y mandarlo a
/// otra pestaña le hacía perder de vista lo demás.
class InicioComercioPage extends ConsumerWidget {
  const InicioComercioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercio = ref.watch(comercioActualProvider).value;
    final enviosAsync = ref.watch(enviosDelComercioProvider);
    final pedidosAsync = ref.watch(pedidosDelComercioProvider);
    final envios = enviosAsync.value ?? const <Envio>[];
    final pedidos = pedidosAsync.value ?? const <Pedido>[];

    final hoy = DateTime.now();
    bool esDeHoy(DateTime d) => d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
    bool esNuevo(Pedido p) => p.estado == EstadoPedido.pagado;
    bool enCocina(Pedido p) => p.estado == EstadoPedido.aceptado || p.estado == EstadoPedido.enPreparacion;
    bool enLaCalle(Envio e) => e.estado.esActivo;
    bool entregadoHoy(Envio e) => e.estado == EstadoEnvio.entregado && esDeHoy(e.creadoEn);

    final nuevos = pedidos.where(esNuevo).toList()..sort((a, b) => a.creadoEn.compareTo(b.creadoEn));
    final cocina = pedidos.where(enCocina).length;
    final listos = pedidos.where((p) => p.estado == EstadoPedido.listo).length;
    final calle = envios.where(enLaCalle).length;
    final entregados = envios.where(entregadoHoy).length;
    final enviosHoy = envios.where((e) => e.estado.esActivo || esDeHoy(e.creadoEn)).toList();

    void reintentarPedidos() => ref.invalidate(pedidosDelComercioProvider);
    void reintentarEnvios() => ref.invalidate(enviosDelComercioProvider);

    final kpis = MyGrilla(
      anchoMinimo: context.esMovil ? 150 : 200,
      children: [
        _kpi(
          pedidosAsync,
          rotulo: 'Pedidos nuevos',
          icono: Symbols.notifications_active,
          reintentar: reintentarPedidos,
          listo: () => MyKpi(
            rotulo: 'Pedidos nuevos',
            valor: '${nuevos.length}',
            icono: Symbols.notifications_active,
            detalle: nuevos.isNotEmpty ? 'Tocá para aceptarlos' : 'Nada por aceptar',
            destacado: nuevos.isNotEmpty,
            onTap: nuevos.isEmpty
                ? null
                : () => mostrarPedidos(context, titulo: 'Pedidos nuevos', filtro: esNuevo, ahora: pedidos),
          ),
        ),
        _kpi(
          pedidosAsync,
          rotulo: 'En cocina',
          icono: Symbols.skillet,
          reintentar: reintentarPedidos,
          listo: () => MyKpi(
            rotulo: 'En cocina',
            valor: '$cocina',
            icono: Symbols.skillet,
            detalle: listos > 0 ? '$listos ${listos == 1 ? 'listo esperando' : 'listos esperando'} rider' : 'Aceptados y en preparación',
            onTap: cocina + listos == 0
                ? null
                : () => mostrarPedidos(
                      context,
                      titulo: 'En cocina y listos',
                      filtro: (p) => enCocina(p) || p.estado == EstadoPedido.listo,
                      ahora: pedidos,
                    ),
          ),
        ),
        _kpi(
          enviosAsync,
          rotulo: 'Envíos en la calle',
          icono: Symbols.sports_motorsports,
          reintentar: reintentarEnvios,
          listo: () => MyKpi(
            rotulo: 'Envíos en la calle',
            valor: '$calle',
            icono: Symbols.sports_motorsports,
            detalle: 'Cadetería y pedidos de la app',
            onTap: calle == 0 ? null : () => mostrarEnvios(context, titulo: 'En la calle', filtro: enLaCalle, ahora: envios),
          ),
        ),
        _kpi(
          enviosAsync,
          rotulo: 'Entregados hoy',
          icono: Symbols.task_alt,
          reintentar: reintentarEnvios,
          listo: () => MyKpi(
            rotulo: 'Entregados hoy',
            valor: '$entregados',
            icono: Symbols.task_alt,
            detalle: 'Confirmados con código',
            onTap: entregados == 0
                ? null
                : () => mostrarEnvios(context, titulo: 'Entregados hoy', filtro: entregadoHoy, ahora: envios),
          ),
        ),
        const _KpiDeLaSemana(),
      ],
    );

    final estado = comercio == null ? const SizedBox() : _EstadoLocal(comercio: comercio);
    final cadeteria = _Cadeteria(comercio: comercio);
    final listaEnvios = _EnviosDeHoy(envios: enviosHoy, cargando: !enviosAsync.hasValue && !enviosAsync.hasError);
    // Los pedidos que esperan respuesta van a la vista y con su botón: son lo
    // único del inicio que tiene un reloj corriendo.
    final porAceptar = nuevos.isEmpty ? null : _PorAceptar(pedidos: nuevos);

    const espacio = SizedBox(height: MySpacing.md);
    return MyPagina(
      rotulo: DateFormat("EEEE d 'de' MMMM", 'es_AR').format(hoy),
      titulo: comercio?.nombre ?? 'Mi local',
      bajada: 'Todo lo de hoy en un lugar',
      onRefresh: () async {
        ref.invalidate(comercioActualProvider);
        ref.invalidate(tarifarioProvider);
      },
      children: [
        if (context.esMovil) ...[
          estado,
          espacio,
          if (porAceptar != null) ...[porAceptar, const SizedBox(height: MySpacing.xl)],
          kpis,
          espacio,
          cadeteria,
          const SizedBox(height: MySpacing.xl),
          listaEnvios,
        ] else ...[
          kpis,
          const SizedBox(height: MySpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (porAceptar != null) ...[porAceptar, const SizedBox(height: MySpacing.xl)],
                    listaEnvios,
                  ],
                ),
              ),
              const SizedBox(width: MySpacing.lg),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [estado, espacio, cadeteria],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PorAceptar extends StatelessWidget {
  const _PorAceptar({required this.pedidos});

  final List<Pedido> pedidos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MySectionHeader(
          title: pedidos.length == 1 ? 'Un pedido para aceptar' : '${pedidos.length} pedidos para aceptar',
          subtitle: 'Tocalo para ver todo lo que pidió',
          actionLabel: 'Ir a Pedidos',
          onAction: () => context.go('/local/pedidos'),
        ),
        const SizedBox(height: MySpacing.md),
        for (final p in pedidos) ...[
          TarjetaPedido(pedido: p, mostrarEstado: false),
          const SizedBox(height: MySpacing.sm),
        ],
      ],
    );
  }
}

class _Cadeteria extends ConsumerWidget {
  const _Cadeteria({required this.comercio});

  final Comercio? comercio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tarifario = ref.watch(tarifarioProvider).value;
    final puede = comercio?.puedePedirEnvios ?? false;

    return MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MyBadge('CADETERÍA', tone: MyBadgeTone.dark, icon: Symbols.bolt),
          const SizedBox(height: MySpacing.md),
          Text('Pedir un rider', style: MyType.headlineLg.copyWith(color: Colors.white)),
          Text(
            'Para pedidos que te llegan por teléfono o WhatsApp.',
            style: MyType.bodyMd.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: MySpacing.md),
          if (tarifario != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: MySpacing.xs,
              children: [
                Text(Formato.pesos(tarifario.precioBase), style: MyType.displayLg.copyWith(color: Colors.white)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('hasta ${Formato.km(tarifario.kmIncluidos)}', style: MyType.bodyMd.copyWith(color: Colors.white70)),
                ),
              ],
            ),
          const SizedBox(height: MySpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: puede ? () => context.go('/local/envios/nuevo') : null,
              style: FilledButton.styleFrom(
                backgroundColor: MyColors.primary,
                foregroundColor: MyColors.onPrimary,
                disabledBackgroundColor: Colors.white24,
              ),
              icon: const Text('Pedir ahora'),
              label: const Icon(Symbols.arrow_forward, size: 20),
            ),
          ),
          if (comercio != null && !comercio!.direccion.tieneCoordenadas)
            Padding(
              padding: const EdgeInsets.only(top: MySpacing.xs),
              child: Text(
                'Primero marcá la ubicación del local en "Mi local".',
                style: MyType.bodySm.copyWith(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _EnviosDeHoy extends StatelessWidget {
  const _EnviosDeHoy({required this.envios, required this.cargando});

  final List<Envio> envios;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MySectionHeader(
          title: 'Envíos de hoy',
          subtitle: 'Se actualizan solos',
          actionLabel: 'Ver todos',
          onAction: () => context.go('/local/envios'),
        ),
        const SizedBox(height: MySpacing.md),
        if (cargando)
          // "Sin envíos hoy" mientras carga era tan engañoso como el cero.
          const MyCard(child: Padding(padding: EdgeInsets.all(MySpacing.lg), child: MyCargando()))
        else if (envios.isEmpty)
          const MyCard(
            child: MyEmptyState(
              icon: Symbols.sports_motorsports,
              title: 'Sin envíos hoy',
              message: 'Los envíos de la cadetería y los de pedidos de la app aparecen acá.',
            ),
          )
        else
          for (final e in envios) ...[
            EnvioTile(envio: e, onTap: () => mostrarDetalleEnvio(context, e.id)),
            const SizedBox(height: MySpacing.sm),
          ],
      ],
    );
  }
}

/// Abierto / pausado, con el interruptor a mano: es lo que más se toca en un
/// día de mucho trabajo.
class _EstadoLocal extends ConsumerWidget {
  const _EstadoLocal({required this.comercio});

  final Comercio comercio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyCard(
      padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: comercio.abierto ? MyColors.success : MyColors.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comercio.abierto ? 'Recibiendo pedidos' : 'Cerrado para la app', style: MyType.labelLg),
                Text(
                  comercio.aceptaPedidos
                      ? (comercio.abierto ? 'Los clientes te ven abierto' : 'Fuera de tu horario')
                      : 'Pausado a mano',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
          MyInterruptor(
            valor: comercio.aceptaPedidos,
            onChanged: (v) async {
              try {
                await ref.read(comerciosRepositoryProvider).actualizar(comercio.id, aceptaPedidos: v);
                ref.invalidate(comercioActualProvider);
              } catch (e) {
                if (context.mounted) mostrarError(context, e);
                rethrow;
              }
            },
          ),
        ],
      ),
    );
  }
}
