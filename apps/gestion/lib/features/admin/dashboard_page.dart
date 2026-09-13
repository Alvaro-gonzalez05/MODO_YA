import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// C1 - Dashboard general.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercios = ref.watch(todosLosComerciosProvider).value ?? const [];
    final repartidores =
        ref.watch(todosLosRepartidoresProvider).value ?? const [];
    final activos = ref.watch(enviosActivosProvider).value ?? const [];

    final conectados = repartidores.where((r) => r.conectado).length;
    final comerciosActivos =
        comercios.where((c) => c.aprobacion.puedeOperar).length;
    final pendientes = [
      ...comercios.where((c) => c.aprobacion == EstadoAprobacion.pendiente),
      ...repartidores.where((r) => r.aprobacion == EstadoAprobacion.pendiente),
    ].length;

    // Ingresos por comision de los envios ya entregados hoy.
    final comisionesHoy = activos.fold<int>(0, (s, e) => s + e.cotizacion.comision);

    return ListView(
      padding: const EdgeInsets.all(MySpacing.xl),
      children: [
        const AdminPageHeader(
          titulo: 'Resumen',
          bajada: 'Como viene la operacion en Malargue hoy',
        ),

        LayoutBuilder(
          builder: (context, c) {
            final columnas = c.maxWidth > 900 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columnas,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: MySpacing.md,
              mainAxisSpacing: MySpacing.md,
              childAspectRatio: 1.7,
              children: [
                _Kpi(
                  icon: Symbols.storefront,
                  valor: '$comerciosActivos',
                  label: 'Comercios activos',
                  detalle: '${comercios.length} en total',
                ),
                _Kpi(
                  icon: Symbols.sports_motorsports,
                  valor: '$conectados',
                  label: 'Cadetes conectados',
                  detalle: '${repartidores.length} registrados',
                ),
                _Kpi(
                  icon: Symbols.package_2,
                  valor: '${activos.length}',
                  label: 'Envios en curso',
                  detalle: 'Ahora mismo en la calle',
                ),
                _Kpi(
                  icon: Symbols.payments,
                  valor: Formato.pesos(comisionesHoy),
                  label: 'Comisiones en curso',
                  detalle: 'Se liquidan al entregar',
                  destacado: true,
                ),
              ],
            );
          },
        ),

        if (pendientes > 0) ...[
          const SizedBox(height: MySpacing.lg),
          MyCard(
            color: MyColors.primaryFixed,
            shadows: const [],
            child: Row(
              children: [
                const Icon(Symbols.pending_actions,
                    size: 26, color: MyColors.primary),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$pendientes ${pendientes == 1 ? "solicitud" : "solicitudes"} '
                        'esperando aprobacion',
                        style: MyType.headlineSm,
                      ),
                      Text(
                        'Ni los comercios ni los cadetes pueden operar hasta '
                        'que los valides.',
                        style: MyType.bodySm
                            .copyWith(color: MyColors.onPrimaryFixedVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: MySpacing.xl),
        Text('Envios en curso', style: MyType.headlineMd),
        const SizedBox(height: MySpacing.sm),

        if (activos.isEmpty)
          const MyEmptyState(
            icon: Symbols.package_2,
            title: 'No hay envios activos',
            message: 'Cuando un comercio pida un cadete, va a aparecer aca.',
          )
        else
          for (final e in activos) ...[
            _FilaEnvio(envio: e),
            const SizedBox(height: MySpacing.xs),
          ],
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.valor,
    required this.label,
    required this.detalle,
    this.destacado = false,
  });

  final IconData icon;
  final String valor;
  final String label;
  final String detalle;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 24,
          color: destacado ? Colors.white : MyColors.primary,
        ),
        const SizedBox(height: MySpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            valor,
            style: MyType.headlineLg.copyWith(
              color: destacado ? Colors.white : MyColors.onSurface,
            ),
          ),
        ),
        Text(
          label,
          style: MyType.labelLg.copyWith(
            color: destacado ? Colors.white : MyColors.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          detalle,
          style: MyType.bodySm.copyWith(
            color: destacado ? Colors.white70 : MyColors.secondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return destacado
        ? MyHeroCard(
            padding: const EdgeInsets.all(MySpacing.md),
            child: child,
          )
        : MyCard(padding: const EdgeInsets.all(MySpacing.md), child: child);
  }
}

class _FilaEnvio extends StatelessWidget {
  const _FilaEnvio({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text('#${envio.codigo}', style: MyType.labelLg),
          ),
          Expanded(
            flex: 3,
            child: Text(
              envio.comercioNombre,
              style: MyType.bodyMd,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              envio.destino.calle,
              style: MyType.bodyMd.copyWith(color: MyColors.secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              envio.repartidorNombre ?? 'Sin asignar',
              style: MyType.bodyMd.copyWith(color: MyColors.secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              Formato.pesos(envio.total),
              style: MyType.labelLg,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          MyBadge(
            envio.estado.label,
            tone: envio.estado == EstadoEnvio.buscandoRepartidor
                ? MyBadgeTone.neutral
                : MyBadgeTone.ember,
            dot: envio.estado == EstadoEnvio.buscandoRepartidor,
          ),
        ],
      ),
    );
  }
}
