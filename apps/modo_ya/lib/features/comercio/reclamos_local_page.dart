import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_core/my_core.dart';

import '../../comun/reclamos.dart';

/// Los reclamos del local. Puede abrir uno de un pedido que atendió o de un
/// envío que pidió, y lee la respuesta de la administración.
class ReclamosLocalPage extends ConsumerWidget {
  const ReclamosLocalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosDelComercioProvider).value ?? const <Pedido>[];
    final envios = ref.watch(enviosDelComercioProvider).value ?? const <Envio>[];

    return MisReclamosPage(
      bajada: 'Lo que nos contaste y qué te contestamos',
      motivos: MotivosDeReclamo.delLocal,
      candidatos: [
        for (final p in pedidos.take(10))
          SobreQue(
            pedidoId: p.id,
            titulo: 'Pedido ${p.codigo}',
            bajada: '${p.estado.label} · ${Formato.fechaCorta(p.creadoEn)} · ${Formato.pesos(p.total)}',
          ),
        for (final e in envios.take(10))
          SobreQue(
            envioId: e.id,
            titulo: 'Envío ${e.codigo}',
            bajada: '${e.estado.label} · ${Formato.fechaCorta(e.creadoEn)} · ${e.destino.calle}',
          ),
      ],
      volver: () => context.canPop() ? context.pop() : context.go('/local/cuenta'),
    );
  }
}
