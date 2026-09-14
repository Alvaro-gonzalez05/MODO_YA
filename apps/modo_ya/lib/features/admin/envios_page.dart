import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Envios en curso con su trazabilidad y el reparto del dinero.
class AdminEnviosPage extends ConsumerWidget {
  const AdminEnviosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activos = ref.watch(enviosActivosProvider);

    return ListView(
      padding: const EdgeInsets.all(MySpacing.xl),
      children: [
        const AdminPageHeader(titulo: 'Envios', bajada: 'Todo lo que esta en la calle, en vivo'),
        MyAsync(
          valor: activos,
          onReintentar: () => ref.invalidate(enviosActivosProvider),
          datos: (lista) => lista.isEmpty
              ? const MyEmptyState(
                  icon: Symbols.package_2,
                  title: 'No hay envios activos',
                  message: 'Se actualiza solo cuando un local pide un rider.',
                )
              : Column(
                  children: [
                    for (final e in lista) ...[
                      _EnvioExpandible(envio: e),
                      const SizedBox(height: MySpacing.xs),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _EnvioExpandible extends ConsumerWidget {
  const _EnvioExpandible({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: MySpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(MySpacing.md, 0, MySpacing.md, MySpacing.md),
          title: Wrap(
            spacing: MySpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(envio.codigo, style: MyType.labelLg),
              Text('${envio.comercioNombre} -> ${envio.destino.calle}', style: MyType.bodyMd),
              MyBadge(envio.estado.label),
            ],
          ),
          subtitle: Text(
            'Creado ${Formato.haceCuanto(envio.creadoEn)} - Rider: ${envio.repartidorNombre ?? "sin asignar"}'
            '${envio.pedidoId != null ? " - pedido de la app" : ""}',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          children: [
            MyRouteTimeline(
              stops: [
                MyRouteStop(
                  overline: 'Retiro',
                  title: envio.comercioNombre,
                  subtitle: envio.origen.calle,
                  icon: Symbols.storefront,
                ),
                MyRouteStop(
                  overline: 'Entrega',
                  title: envio.destino.calle,
                  subtitle: '${envio.cliente.nombre} - ${envio.cliente.telefono}',
                  icon: Symbols.home,
                  iconBackground: MyColors.dock,
                ),
              ],
            ),
            const SizedBox(height: MySpacing.sm),
            Wrap(
              spacing: MySpacing.lg,
              runSpacing: MySpacing.xs,
              children: [
                Text('Rider ${Formato.pesos(envio.cotizacion.gananciaRepartidor)}', style: MyType.labelMd),
                Text('MODO YA ${Formato.pesos(envio.cotizacion.comision)}', style: MyType.labelMd),
                Text('Total ${Formato.pesos(envio.total)}', style: MyType.labelLg.copyWith(color: MyColors.primary)),
                Text(Formato.km(envio.cotizacion.distanciaKm), style: MyType.labelMd),
                Text('Paga: ${envio.quienPaga.label}', style: MyType.labelMd),
              ],
            ),
            const SizedBox(height: MySpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final motivo = await pedirTexto(
                    context,
                    titulo: 'Cancelar ${envio.codigo}',
                    label: 'Motivo',
                    aceptar: 'Cancelar envio',
                  );
                  if (motivo == null) return;
                  try {
                    await ref.read(enviosRepositoryProvider).cancelar(envio.id, motivo);
                  } catch (e) {
                    if (context.mounted) mostrarError(context, e);
                  }
                },
                icon: const Icon(Symbols.cancel, size: 18),
                label: const Text('Cancelar envio'),
                style: TextButton.styleFrom(foregroundColor: MyColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
