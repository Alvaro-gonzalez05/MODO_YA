import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// B1 - Perfil y documentacion del cadete.
///
/// La documentacion exigida depende del vehiculo y la define la
/// administracion; hasta que la cuenta este aprobada el cadete no puede
/// conectarse.
class PerfilPage extends ConsumerWidget {
  const PerfilPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repartidor = ref.watch(repartidorActualProvider).value;

    return Column(
      children: [
        const MyTopBar(zona: 'Malargue urbano'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MySpacing.screenEdge,
              MySpacing.xs,
              MySpacing.screenEdge,
              MySpacing.dockClearance,
            ),
            children: [
              Text('Mi perfil', style: MyType.headlineLg),
              const SizedBox(height: MySpacing.lg),

              MyCard(
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: MyColors.primaryFixed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Symbols.sports_motorsports,
                          size: 32, color: MyColors.primary),
                    ),
                    const SizedBox(width: MySpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            repartidor?.nombre ?? 'Cadete',
                            style: MyType.headlineMd,
                          ),
                          Text(
                            repartidor?.telefono ?? '',
                            style: MyType.bodySm
                                .copyWith(color: MyColors.secondary),
                          ),
                          const SizedBox(height: MySpacing.xs),
                          if (repartidor != null)
                            MyBadge(
                              repartidor.aprobacion.label,
                              tone: repartidor.aprobacion.puedeOperar
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
              Text('Documentacion', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.xxs),
              Text(
                'Requerida para ${repartidor?.vehiculo.label.toLowerCase() ?? "tu vehiculo"}',
                style: MyType.bodyMd.copyWith(color: MyColors.secondary),
              ),
              const SizedBox(height: MySpacing.sm),

              MyCard(
                padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
                child: Column(
                  children: [
                    for (final doc
                        in repartidor?.vehiculo.documentacionRequerida ??
                            const <String>[])
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: repartidor!.aprobacion.puedeOperar
                                ? MyColors.successContainer
                                : MyColors.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            repartidor.aprobacion.puedeOperar
                                ? Symbols.check_circle
                                : Symbols.upload_file,
                            size: 20,
                            color: repartidor.aprobacion.puedeOperar
                                ? MyColors.success
                                : MyColors.secondary,
                          ),
                        ),
                        title: Text(doc, style: MyType.labelLg),
                        subtitle: Text(
                          repartidor.aprobacion.puedeOperar
                              ? 'Validado'
                              : 'Pendiente de carga',
                          style: MyType.bodySm
                              .copyWith(color: MyColors.secondary),
                        ),
                        trailing: const Icon(Symbols.chevron_right,
                            color: MyColors.outline),
                        onTap: () {},
                      ),
                  ],
                ),
              ),

              const SizedBox(height: MySpacing.lg),
              MyCard(
                color: MyColors.secondaryContainer,
                shadows: const [],
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Symbols.shield, size: 22,
                        color: MyColors.secondary),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Text(
                        'Tu ubicacion se comparte unicamente mientras estas '
                        'conectado o haciendo un servicio.',
                        style: MyType.bodySm
                            .copyWith(color: MyColors.onSecondaryFixed),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
