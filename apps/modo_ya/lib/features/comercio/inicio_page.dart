import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/envio_tile.dart';

/// Inicio del local (A4): estado, pedidos por atender, pedir un rider y los
/// envíos de hoy.
class InicioComercioPage extends ConsumerWidget {
  const InicioComercioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercio = ref.watch(comercioActualProvider).value;
    final envios = ref.watch(enviosDelComercioProvider).value ?? const <Envio>[];
    final pedidos = ref.watch(pedidosDelComercioProvider).value ?? const <Pedido>[];

    final hoy = DateTime.now();
    bool esDeHoy(DateTime d) => d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
    final nuevos = pedidos.where((p) => p.estado == EstadoPedido.pagado).length;
    final enCocina = pedidos.where((p) => p.estado == EstadoPedido.aceptado || p.estado == EstadoPedido.enPreparacion).length;
    final listos = pedidos.where((p) => p.estado == EstadoPedido.listo).length;
    final enviosHoy = envios.where((e) => e.estado.esActivo || esDeHoy(e.creadoEn)).toList();
    final entregadosHoy = envios.where((e) => e.estado == EstadoEnvio.entregado && esDeHoy(e.creadoEn)).length;

    final kpis = MyGrilla(
      anchoMinimo: context.esMovil ? 150 : 200,
      children: [
        MyKpi(
          rotulo: 'Pedidos nuevos',
          valor: '$nuevos',
          icono: Symbols.notifications_active,
          detalle: nuevos > 0 ? 'Tocá para aceptarlos' : 'Nada por aceptar',
          destacado: nuevos > 0,
          onTap: () => context.go('/local/pedidos'),
        ),
        MyKpi(
          rotulo: 'En cocina',
          valor: '$enCocina',
          icono: Symbols.skillet,
          detalle: listos > 0 ? '$listos listos esperando rider' : 'Aceptados y en preparación',
          onTap: () => context.go('/local/pedidos'),
        ),
        MyKpi(
          rotulo: 'Envíos en la calle',
          valor: '${envios.where((e) => e.estado.esActivo).length}',
          icono: Symbols.sports_motorsports,
          detalle: 'Cadetería y pedidos de la app',
        ),
        MyKpi(
          rotulo: 'Entregados hoy',
          valor: '$entregadosHoy',
          icono: Symbols.task_alt,
          detalle: 'Confirmados con código',
        ),
      ],
    );

    final estado = comercio == null ? const SizedBox() : _EstadoLocal(comercio: comercio);
    final cadeteria = _Cadeteria(comercio: comercio);
    final listaEnvios = _EnviosDeHoy(envios: enviosHoy);

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
          const SizedBox(height: MySpacing.md),
          kpis,
          const SizedBox(height: MySpacing.md),
          cadeteria,
          const SizedBox(height: MySpacing.xl),
          listaEnvios,
        ] else ...[
          kpis,
          const SizedBox(height: MySpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: listaEnvios),
              const SizedBox(width: MySpacing.lg),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [estado, const SizedBox(height: MySpacing.md), cadeteria],
                ),
              ),
            ],
          ),
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
                backgroundColor: Colors.white,
                foregroundColor: MyColors.inverseOnSurface,
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
  const _EnviosDeHoy({required this.envios});

  final List<Envio> envios;

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
        if (envios.isEmpty)
          const MyCard(
            child: MyEmptyState(
              icon: Symbols.sports_motorsports,
              title: 'Sin envíos hoy',
              message: 'Los envíos de la cadetería y los de pedidos de la app aparecen acá.',
            ),
          )
        else
          for (final e in envios) ...[
            EnvioTile(envio: e, onTap: () => context.go('/local/envios/${e.id}')),
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
          Switch(
            value: comercio.aceptaPedidos,
            onChanged: (v) async {
              try {
                await ref.read(comerciosRepositoryProvider).actualizar(comercio.id, aceptaPedidos: v);
                ref.invalidate(comercioActualProvider);
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
