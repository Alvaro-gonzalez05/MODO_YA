import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Los mandados que pidió el cliente, en vivo.
class MisMandadosPage extends ConsumerWidget {
  const MisMandadosPage({super.key});

  Future<void> _cancelar(BuildContext context, WidgetRef ref, Envio e) async {
    final ok = await confirmar(
      context,
      titulo: 'Cancelar el mandado',
      mensaje: 'Se cancela y dejamos de buscarte un rider.',
      aceptar: 'Cancelar el mandado',
      peligroso: true,
    );
    if (!ok) return;
    try {
      await ref.read(enviosRepositoryProvider).cancelar(e.id, 'Lo canceló el cliente');
      ref.invalidate(misMandadosProvider);
    } catch (err) {
      if (context.mounted) mostrarError(context, err);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mandados = ref.watch(misMandadosProvider);

    return MyPagina(
      volver: () => context.go('/cliente'),
      rotulo: 'Mandados',
      titulo: 'Mis mandados',
      anchoMaximo: 700,
      acciones: [
        MyBoton(
          label: 'Pedir un rider',
          icon: Symbols.add,
          onPressed: () => context.go('/cliente/mandados/nuevo'),
        ),
      ],
      onRefresh: () async => ref.invalidate(misMandadosProvider),
      children: [
        MyAsync(
          valor: mandados,
          onReintentar: () => ref.invalidate(misMandadosProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.sports_motorsports,
                  title: 'Todavía no pediste ningún mandado',
                  message: 'Sirve para que un rider te retire algo de un lado y '
                      'te lo lleve a otro: un sobre, algo que dejaste pago, la ropa.',
                  action: MyBoton(
                    label: 'Pedir un rider',
                    icon: Symbols.add,
                    onPressed: () => context.go('/cliente/mandados/nuevo'),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in lista) ...[
                  _Fila(envio: e, onCancelar: () => _cancelar(context, ref, e)),
                  const SizedBox(height: MySpacing.xs),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.envio, required this.onCancelar});

  final Envio envio;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final e = envio;
    final enCurso = !e.estado.esFinal;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(e.codigo, style: MyType.labelLg)),
              MyBadge(
                e.estado.label,
                tone: e.estado == EstadoEnvio.entregado
                    ? MyBadgeTone.success
                    : e.estado == EstadoEnvio.cancelado
                        ? MyBadgeTone.neutral
                        : MyBadgeTone.info,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          _Tramo(icono: Symbols.inventory_2, texto: 'Retira en ${e.origen.calle}'),
          if ((e.origen.referencia ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                e.origen.referencia!,
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
            ),
          const SizedBox(height: 2),
          _Tramo(icono: Symbols.home_pin, texto: 'Lleva a ${e.destino.calle}'),
          const SizedBox(height: MySpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  e.repartidorNombre == null
                      ? 'Buscando rider…'
                      : 'Lo lleva ${e.repartidorNombre}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ),
              MyPrecio(precio: Formato.pesos(e.cobrarAlEntregar)),
              if (enCurso) ...[
                const SizedBox(width: MySpacing.xs),
                MyBoton(
                  label: 'Cancelar',
                  icon: Symbols.close,
                  tipo: MyBotonTipo.texto,
                  onPressed: onCancelar,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Tramo extends StatelessWidget {
  const _Tramo({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18, color: MyColors.outline),
        const SizedBox(width: MySpacing.xs),
        Expanded(child: Text(texto, style: MyType.bodySm)),
      ],
    );
  }
}
