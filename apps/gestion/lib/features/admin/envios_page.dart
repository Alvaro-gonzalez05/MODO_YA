import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// C5 - Envios y trazabilidad.
///
/// El administrador necesita ver la linea de tiempo completa de cada operacion
/// para resolver reclamos, asi que cada fila se despliega con sus marcas de
/// tiempo y el detalle del reparto del dinero.
class AdminEnviosPage extends ConsumerWidget {
  const AdminEnviosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activos = ref.watch(enviosActivosProvider);

    return activos.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (lista) => ListView(
        padding: const EdgeInsets.all(MySpacing.xl),
        children: [
          const AdminPageHeader(
            titulo: 'Envios',
            bajada: 'Trazabilidad completa de cada operacion',
          ),
          if (lista.isEmpty)
            const MyEmptyState(
              icon: Symbols.package_2,
              title: 'No hay envios activos',
              message: 'Los envios cerrados van a estar en el historico.',
            )
          else
            for (final e in lista) ...[
              _EnvioExpandible(envio: e),
              const SizedBox(height: MySpacing.xs),
            ],
        ],
      ),
    );
  }
}

class _EnvioExpandible extends StatelessWidget {
  const _EnvioExpandible({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          tilePadding:
              const EdgeInsets.symmetric(horizontal: MySpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(
            MySpacing.md,
            0,
            MySpacing.md,
            MySpacing.md,
          ),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: MyColors.secondaryContainer,
              borderRadius: BorderRadius.circular(MyRadius.md),
            ),
            child: const Icon(Symbols.package_2,
                size: 21, color: MyColors.primary),
          ),
          title: Row(
            children: [
              Text('#${envio.codigo}', style: MyType.labelLg),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  '${envio.comercioNombre} -> ${envio.destino.calle}',
                  style: MyType.bodyMd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MyBadge(envio.estado.label),
              const SizedBox(width: MySpacing.sm),
              Text(Formato.pesos(envio.total), style: MyType.labelLg),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Creado ${Formato.haceCuanto(envio.creadoEn)} - '
              'Cadete: ${envio.repartidorNombre ?? "sin asignar"}',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
          ),
          children: [
            const Divider(),
            const SizedBox(height: MySpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MyRouteTimeline(
                    background: MyColors.surfaceContainerLow,
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
                        subtitle: envio.destino.referencia,
                        icon: Symbols.home,
                        iconBackground: MyColors.dock,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MyOverline('Trazabilidad'),
                      const SizedBox(height: MySpacing.xs),
                      _Marca('Creado', envio.creadoEn),
                      _Marca('Retirado', envio.retiradoEn),
                      _Marca('Entregado', envio.entregadoEn),
                      const SizedBox(height: MySpacing.sm),
                      const MyOverline('Reparto del dinero'),
                      const SizedBox(height: MySpacing.xs),
                      _Monto(
                        'Cadete',
                        envio.cotizacion.gananciaRepartidor,
                      ),
                      _Monto('MODO YA', envio.cotizacion.comision),
                      _Monto('Total', envio.total, destacado: true),
                      const SizedBox(height: MySpacing.xs),
                      Text(
                        'Paga: ${envio.quienPaga.label}',
                        style: MyType.bodySm
                            .copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca(this.label, this.momento);

  final String label;
  final DateTime? momento;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            momento == null ? Symbols.radio_button_unchecked : Symbols.check_circle,
            size: 16,
            color: momento == null ? MyColors.outline : MyColors.primary,
            fill: momento == null ? 0 : 1,
          ),
          const SizedBox(width: MySpacing.xs),
          Text(label, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          const Spacer(),
          Text(
            momento == null ? '-' : Formato.hora(momento!),
            style: MyType.labelMd,
          ),
        ],
      ),
    );
  }
}

class _Monto extends StatelessWidget {
  const _Monto(this.label, this.valor, {this.destacado = false});

  final String label;
  final int valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Text(label, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          const Spacer(),
          Text(
            Formato.pesos(valor),
            style: destacado
                ? MyType.labelLg.copyWith(color: MyColors.primary)
                : MyType.labelMd,
          ),
        ],
      ),
    );
  }
}
