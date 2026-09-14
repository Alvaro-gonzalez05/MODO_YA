import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Resumen de la operacion, con el mapa en vivo de riders y envios.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercios = ref.watch(todosLosComerciosProvider).value ?? const <Comercio>[];
    final riders = ref.watch(todosLosRepartidoresProvider).value ?? const <Repartidor>[];
    final activos = ref.watch(enviosActivosProvider).value ?? const <Envio>[];
    final porCobrar = ref.watch(pedidosPendientesDePagoProvider).value ?? const <Pedido>[];

    final conectados = riders.where((r) => r.conectado).toList();
    final libres = conectados.where((r) => !r.ocupado).length;
    final abiertos = comercios.where((c) => c.abierto).length;
    final buscando = activos.where((e) => e.estado == EstadoEnvio.buscandoRepartidor).length;

    final marcadores = <MyMarcador>[
      for (final r in conectados)
        if (r.ubicacion?.tieneCoordenadas ?? false)
          MyMarcador(
            punto: LatLng(r.ubicacion!.lat!, r.ubicacion!.lng!),
            icono: Symbols.sports_motorsports,
            color: r.ocupado ? MyColors.primary : MyColors.success,
            etiqueta: r.nombre.split(' ').first,
          ),
      for (final e in activos)
        if (e.destino.tieneCoordenadas)
          MyMarcador(punto: LatLng(e.destino.lat!, e.destino.lng!), icono: Symbols.home, color: MyColors.dock),
    ];

    return ListView(
      padding: const EdgeInsets.all(MySpacing.xl),
      children: [
        const AdminPageHeader(titulo: 'Resumen', bajada: 'Como viene la operacion en Malargue ahora'),

        LayoutBuilder(
          builder: (context, c) {
            final columnas = c.maxWidth > 900 ? 4 : 2;
            return GridView.count(
              crossAxisCount: columnas,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: MySpacing.md,
              mainAxisSpacing: MySpacing.md,
              childAspectRatio: columnas == 4 ? 1.8 : 1.5,
              children: [
                _Kpi(
                  icon: Symbols.storefront,
                  valor: '$abiertos',
                  label: 'Locales abiertos',
                  detalle: '${comercios.length} en total',
                ),
                _Kpi(
                  icon: Symbols.sports_motorsports,
                  valor: '${conectados.length}',
                  label: 'Riders conectados',
                  detalle: '$libres libres ahora',
                ),
                _Kpi(
                  icon: Symbols.package_2,
                  valor: '${activos.length}',
                  label: 'Envios en la calle',
                  detalle: buscando == 0 ? 'Todos con rider' : '$buscando buscando rider',
                ),
                _Kpi(
                  icon: Symbols.payments,
                  valor: '${porCobrar.length}',
                  label: 'Pedidos por cobrar',
                  detalle: porCobrar.isEmpty ? 'Nada pendiente' : 'Toca para confirmar',
                  destacado: porCobrar.isNotEmpty,
                  onTap: () => context.go('/admin/pedidos'),
                ),
              ],
            );
          },
        ),

        if (buscando > 0 && libres == 0) ...[
          const SizedBox(height: MySpacing.lg),
          MyCard(
            color: MyColors.errorContainer,
            shadows: const [],
            child: Row(
              children: [
                const Icon(Symbols.warning, color: MyColors.onErrorContainer),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Text(
                    'Hay $buscando envio(s) buscando rider y no hay ninguno libre conectado.',
                    style: MyType.labelLg.copyWith(color: MyColors.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: MySpacing.xl),
        Text('Mapa en vivo', style: MyType.headlineMd),
        const SizedBox(height: MySpacing.xxs),
        Text(
          'Verde: rider libre. Naranja: rider en servicio. Casa: destino de un envio en curso.',
          style: MyType.bodySm.copyWith(color: MyColors.secondary),
        ),
        const SizedBox(height: MySpacing.sm),
        MyMapaVista(alto: 360, radio: MyRadius.card, interactivo: true, marcadores: marcadores),

        const SizedBox(height: MySpacing.xl),
        Text('Envios en curso', style: MyType.headlineMd),
        const SizedBox(height: MySpacing.sm),
        if (activos.isEmpty)
          const MyEmptyState(
            icon: Symbols.package_2,
            title: 'No hay envios en la calle',
            message: 'Cuando un local pida un rider o acepte un pedido, aparece aca.',
          )
        else
          for (final e in activos) ...[
            MyCard(
              padding: const EdgeInsets.all(MySpacing.md),
              child: Wrap(
                spacing: MySpacing.md,
                runSpacing: MySpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(e.codigo, style: MyType.labelLg),
                  Text(e.comercioNombre, style: MyType.bodyMd),
                  Text('-> ${e.destino.calle}', style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  Text(e.repartidorNombre ?? 'Sin rider', style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  MyBadge(
                    e.estado.label,
                    tone: e.estado == EstadoEnvio.buscandoRepartidor ? MyBadgeTone.neutral : MyBadgeTone.ember,
                    dot: e.estado == EstadoEnvio.buscandoRepartidor,
                  ),
                ],
              ),
            ),
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
    this.onTap,
  });

  final IconData icon;
  final String valor;
  final String label;
  final String detalle;
  final bool destacado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = destacado ? Colors.white : MyColors.onSurface;
    final hijo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 24, color: destacado ? Colors.white : MyColors.primary),
        const SizedBox(height: MySpacing.xs),
        FittedBox(child: Text(valor, style: MyType.headlineLg.copyWith(color: color))),
        Text(label, style: MyType.labelLg.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          detalle,
          style: MyType.bodySm.copyWith(color: destacado ? Colors.white70 : MyColors.secondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    final tarjeta = destacado
        ? MyHeroCard(padding: const EdgeInsets.all(MySpacing.md), child: hijo)
        : MyCard(padding: const EdgeInsets.all(MySpacing.md), child: hijo);

    return onTap == null ? tarjeta : GestureDetector(onTap: onTap, child: tarjeta);
  }
}
