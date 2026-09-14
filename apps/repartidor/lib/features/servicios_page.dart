import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Servicios del rider: el que tiene en curso y los ultimos que hizo.
class ServiciosPage extends ConsumerWidget {
  const ServiciosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envios = ref.watch(enviosDelRepartidorProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Mis servicios'),
        Expanded(
          child: MyAsync(
            valor: envios,
            onReintentar: () => ref.invalidate(enviosDelRepartidorProvider),
            datos: (lista) => lista.isEmpty
                ? const MyEmptyState(
                    icon: Symbols.local_shipping,
                    title: 'Todavia no hiciste servicios',
                    message: 'Cuando aceptes una oferta, aparece aca.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const SizedBox(height: MySpacing.sm),
                    itemBuilder: (_, i) {
                      final e = lista[i];
                      return MyCard(
                        onTap: () => context.push('/servicio/${e.id}'),
                        color: e.estado.esActivo ? MyColors.primaryFixed : MyColors.surfaceContainerLowest,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      MyOverline(e.codigo),
                                      const SizedBox(width: MySpacing.xs),
                                      MyBadge(e.estado.label,
                                          tone: e.estado.esActivo
                                              ? MyBadgeTone.ember
                                              : (e.estado == EstadoEnvio.entregado ? MyBadgeTone.success : MyBadgeTone.danger)),
                                    ],
                                  ),
                                  const SizedBox(height: MySpacing.xxs),
                                  Text(e.comercioNombre, style: MyType.headlineSm),
                                  Text('-> ${e.destino.calle}', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                                  Text('${Formato.fechaCorta(e.creadoEn)} ${Formato.hora(e.creadoEn)}',
                                      style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                                ],
                              ),
                            ),
                            Text(Formato.pesos(e.cotizacion.gananciaRepartidor),
                                style: MyType.headlineSm.copyWith(color: MyColors.primary)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
