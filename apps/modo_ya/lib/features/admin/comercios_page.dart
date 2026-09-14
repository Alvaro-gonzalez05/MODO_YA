import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Locales: alta, suspension y estado.
class AdminComerciosPage extends ConsumerWidget {
  const AdminComerciosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercios = ref.watch(todosLosComerciosProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(todosLosComerciosProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(MySpacing.xl),
        children: [
          AdminPageHeader(
            titulo: 'Locales',
            bajada: 'Alta de cuentas, suspension y estado de cada local',
            acciones: [
              IconButton(
                tooltip: 'Actualizar',
                onPressed: () => ref.invalidate(todosLosComerciosProvider),
                icon: const Icon(Symbols.refresh),
              ),
              SizedBox(
                width: 180,
                child: FilledButton.icon(
                  onPressed: () => context.push('/admin/alta/local'),
                  icon: const Icon(Symbols.add_business, size: 20),
                  label: const Text('Nuevo local'),
                ),
              ),
            ],
          ),
          MyAsync(
            valor: comercios,
            onReintentar: () => ref.invalidate(todosLosComerciosProvider),
            datos: (lista) => lista.isEmpty
                ? MyEmptyState(
                    icon: Symbols.storefront,
                    title: 'Todavia no hay locales',
                    message: 'Crea el primero con "Nuevo local". Queda aprobado y listo para usar.',
                  )
                : Column(
                    children: [
                      for (final c in lista) ...[
                        _FilaComercio(comercio: c),
                        const SizedBox(height: MySpacing.xs),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilaComercio extends ConsumerWidget {
  const _FilaComercio({required this.comercio});

  final Comercio comercio;

  Future<void> _cambiar(BuildContext context, WidgetRef ref, EstadoAprobacion estado) async {
    String? motivo;
    if (estado == EstadoAprobacion.suspendido) {
      motivo = await pedirTexto(
        context,
        titulo: 'Suspender ${comercio.nombre}',
        label: 'Motivo (lo ve la administracion)',
        aceptar: 'Suspender',
      );
      if (motivo == null) return;
    }
    try {
      await ref.read(comerciosRepositoryProvider).cambiarAprobacion(comercio.id, estado, motivo: motivo);
      ref.invalidate(todosLosComerciosProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operando = comercio.aprobacion.puedeOperar;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: MySpacing.md,
        runSpacing: MySpacing.sm,
        children: [
          SizedBox(
            width: 320,
            child: Row(
              children: [
                MyImagen(url: comercio.logoUrl, ancho: 46, alto: 46, icono: Symbols.storefront),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comercio.nombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${comercio.rubro} - ${comercio.direccion.calle}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          MyBadge(comercio.aprobacion.label, tone: tonoAprobacion(comercio.aprobacion)),
          if (operando)
            MyBadge(
              comercio.abierto ? 'Abierto' : 'Cerrado',
              tone: comercio.abierto ? MyBadgeTone.success : MyBadgeTone.info,
              dot: true,
            ),
          if (!comercio.direccion.tieneCoordenadas)
            const MyBadge('Sin ubicacion', tone: MyBadgeTone.danger, icon: Symbols.location_off),
          Text(comercio.telefono, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          operando
              ? TextButton(
                  onPressed: () => _cambiar(context, ref, EstadoAprobacion.suspendido),
                  child: const Text('Suspender'),
                )
              : FilledButton(
                  onPressed: () => _cambiar(context, ref, EstadoAprobacion.aprobado),
                  style: FilledButton.styleFrom(minimumSize: const Size(120, 40), textStyle: MyType.labelLg),
                  child: Text(comercio.aprobacion == EstadoAprobacion.pendiente ? 'Aprobar' : 'Reactivar'),
                ),
        ],
      ),
    );
  }
}
