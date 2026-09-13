import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// A12 - Suscripcion del comercio y datos de la cuenta.
class SuscripcionPage extends ConsumerWidget {
  const SuscripcionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercio = ref.watch(comercioActualProvider).value;
    final envios = ref.watch(enviosDelComercioProvider).value ?? const [];

    return Column(
      children: [
        const MyTopBar(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MySpacing.screenEdge,
              MySpacing.xs,
              MySpacing.screenEdge,
              MySpacing.dockClearance,
            ),
            children: [
              Text('Mi cuenta', style: MyType.headlineLg),
              const SizedBox(height: MySpacing.lg),

              MyCard(
                padding: const EdgeInsets.all(MySpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: MyColors.primaryFixed,
                        borderRadius: BorderRadius.circular(MyRadius.md),
                      ),
                      child: const Icon(Symbols.storefront,
                          size: 28, color: MyColors.primary),
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comercio?.nombre ?? 'Mi comercio',
                            style: MyType.headlineSm,
                          ),
                          Text(
                            comercio?.direccion.calle ?? '',
                            style: MyType.bodySm
                                .copyWith(color: MyColors.secondary),
                          ),
                          const SizedBox(height: MySpacing.xxs),
                          if (comercio != null)
                            MyBadge(
                              comercio.aprobacion.label,
                              tone: comercio.aprobacion.puedeOperar
                                  ? MyBadgeTone.success
                                  : MyBadgeTone.danger,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: MySpacing.lg),
              Text('Suscripcion', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),
              _TarjetaSuscripcion(estado: comercio?.suscripcion),

              const SizedBox(height: MySpacing.lg),
              Text('Tu actividad', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),
              MyStatRow(
                tiles: [
                  MyStatTile(
                    icon: Symbols.package_2,
                    value: '${comercio?.enviosDelMes ?? envios.length}',
                    label: 'Envios del mes',
                  ),
                  MyStatTile(
                    icon: Symbols.star,
                    value: '4,8',
                    label: 'Reputacion',
                  ),
                ],
              ),

              const SizedBox(height: MySpacing.lg),
              MyCard(
                padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
                child: Column(
                  children: [
                    _Opcion(
                      icon: Symbols.location_on,
                      titulo: 'Direccion de retiro',
                      detalle: comercio?.direccion.calle ?? '',
                    ),
                    _Opcion(
                      icon: Symbols.call,
                      titulo: 'Telefono',
                      detalle: comercio?.telefono ?? '',
                    ),
                    _Opcion(
                      icon: Symbols.notifications,
                      titulo: 'Notificaciones',
                      detalle: 'Avisos de estado de tus envios',
                    ),
                    _Opcion(
                      icon: Symbols.help,
                      titulo: 'Ayuda y reclamos',
                      detalle: 'Reportar un problema con un envio',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: MySpacing.lg),
              OutlinedButton.icon(
                onPressed: () => context.goNamed('bienvenida'),
                icon: const Icon(Symbols.logout, size: 20),
                label: const Text('Cerrar sesion'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TarjetaSuscripcion extends StatelessWidget {
  const _TarjetaSuscripcion({required this.estado});

  final EstadoSuscripcion? estado;

  @override
  Widget build(BuildContext context) {
    final e = estado ?? EstadoSuscripcion.sinSuscripcion;

    return MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MyBadge(e.label, tone: MyBadgeTone.dark),
              const Spacer(),
              const Icon(Symbols.workspace_premium,
                  size: 24, color: Colors.white),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Text(
            'Plan comercio',
            style: MyType.headlineLg.copyWith(color: Colors.white),
          ),
          const SizedBox(height: MySpacing.xxs),
          Text(
            'Envios ilimitados. El importe mensual todavia esta por definirse '
            'con la administracion.',
            style: MyType.bodyMd.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: MySpacing.md),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: MyColors.primary,
                shape: const StadiumBorder(),
              ),
              child: Text(
                e.permiteOperar ? 'Ver comprobantes' : 'Activar suscripcion',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icon,
    required this.titulo,
    required this.detalle,
  });

  final IconData icon;
  final String titulo;
  final String detalle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: MyColors.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: MyColors.primary),
      ),
      title: Text(titulo, style: MyType.labelLg),
      subtitle: detalle.isEmpty
          ? null
          : Text(
              detalle,
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
      trailing: const Icon(Symbols.chevron_right, color: MyColors.outline),
      onTap: () {},
    );
  }
}
