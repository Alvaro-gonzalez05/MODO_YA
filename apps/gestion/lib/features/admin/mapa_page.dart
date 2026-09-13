import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// C2 - Mapa en vivo.
///
/// El mapa real todavia no esta: va `flutter_map` con el archivo
/// `malargue.pmtiles` (OpenStreetMap via Protomaps) y las posiciones llegando
/// por Realtime Broadcast. Mientras tanto esta pantalla muestra los mismos
/// datos en formato lista, para que el panel sea usable desde el dia uno.
class MapaEnVivoPage extends ConsumerWidget {
  const MapaEnVivoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repartidores =
        ref.watch(todosLosRepartidoresProvider).value ?? const [];
    final activos = ref.watch(enviosActivosProvider).value ?? const [];
    final conectados = repartidores.where((r) => r.conectado).toList();

    return ListView(
      padding: const EdgeInsets.all(MySpacing.xl),
      children: [
        const AdminPageHeader(
          titulo: 'Mapa en vivo',
          bajada: 'Cadetes conectados y envios en curso',
        ),

        // Lienzo del mapa. Cuando entre flutter_map, el widget va aca dentro.
        AspectRatio(
          aspectRatio: 16 / 7,
          child: Container(
            decoration: BoxDecoration(
              color: MyColors.inverseSurface,
              borderRadius: BorderRadius.circular(MyRadius.hero),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Symbols.map,
                          size: 44, color: MyColors.inverseOnSurface),
                      const SizedBox(height: MySpacing.sm),
                      Text(
                        'Mapa de Malargue',
                        style: MyType.headlineSm
                            .copyWith(color: MyColors.inverseOnSurface),
                      ),
                      const SizedBox(height: MySpacing.xxs),
                      Text(
                        'Pendiente de integrar: flutter_map + malargue.pmtiles',
                        style: MyType.bodySm.copyWith(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: MySpacing.md,
                  left: MySpacing.md,
                  child: MyBadge(
                    '${conectados.length} cadetes conectados',
                    tone: MyBadgeTone.success,
                    dot: true,
                  ),
                ),
                Positioned(
                  top: MySpacing.md,
                  right: MySpacing.md,
                  child: MyBadge(
                    '${activos.length} envios activos',
                    tone: MyBadgeTone.ember,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: MySpacing.xl),
        Text('Cadetes conectados', style: MyType.headlineMd),
        const SizedBox(height: MySpacing.sm),

        if (conectados.isEmpty)
          const MyEmptyState(
            icon: Symbols.sports_motorsports,
            title: 'No hay cadetes conectados',
            message: 'Los cadetes aparecen aca cuando aprietan "Conectarme".',
          )
        else
          for (final r in conectados) ...[
            MyCard(
              padding: const EdgeInsets.all(MySpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: r.ocupado
                          ? MyColors.primaryFixed
                          : MyColors.successContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.sports_motorsports,
                      size: 21,
                      color: r.ocupado ? MyColors.primary : MyColors.success,
                    ),
                  ),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.nombre, style: MyType.headlineSm),
                        Text(
                          r.ubicacion?.calle ?? 'Ubicacion no disponible',
                          style: MyType.bodySm
                              .copyWith(color: MyColors.secondary),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.vehiculo.label,
                      style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                    ),
                  ),
                  MyBadge(
                    r.ocupado ? 'En servicio' : 'Libre',
                    tone: r.ocupado ? MyBadgeTone.ember : MyBadgeTone.success,
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
