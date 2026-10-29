import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/envio.dart';

/// Seguimiento de un envío en pantalla completa (A7 a A10). Las cuatro
/// pantallas del diseño son la misma en distintos estados, y se actualiza sola
/// en cuanto el rider avanza.
///
/// Desde las listas el envío se abre en una hoja ([mostrarDetalleEnvio]); esta
/// ruta queda para cuando se llega de afuera, como después de pedir un rider.
class SeguimientoPage extends ConsumerWidget {
  const SeguimientoPage({super.key, required this.envioId});

  final String envioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envio = ref.watch(envioProvider(envioId));

    return MyAsync(
      valor: envio,
      datos: (e) => e == null
          ? const MyEmptyState(icon: Symbols.search_off, title: 'Envío no encontrado', message: 'Puede que ya no exista.')
          : _Contenido(envio: e),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.envio});

  final Envio envio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partes = PartesDeEnvio(context, ref, envio, altoMapa: context.esMovil ? 220 : 360);
    const espacio = SizedBox(height: MySpacing.md);

    return MyPagina(
      volver: () => context.canPop() ? context.pop() : context.go('/local/envios'),
      rotulo: envio.pedidoId != null ? 'Pedido de la app' : 'Cadetería',
      titulo: 'Seguimiento',
      bajada: 'Se actualiza solo',
      anchoMaximo: 1180,
      conDock: false,
      children: context.esMovil
          ? [
              partes.hero,
              if (partes.mapa case final mapa?) ...[espacio, mapa],
              espacio,
              ...partes.detalle,
            ]
          : [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        partes.hero,
                        if (partes.mapa case final mapa?) ...[espacio, mapa],
                      ],
                    ),
                  ),
                  const SizedBox(width: MySpacing.lg),
                  Expanded(
                    flex: 2,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: partes.detalle),
                  ),
                ],
              ),
            ],
    );
  }
}
