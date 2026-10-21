import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/reclamos.dart';

/// Los reclamos del cliente. Se puede abrir uno de cualquier pedido suyo o
/// uno general, y acá mismo lee la respuesta de la administración.
class MisReclamosClientePage extends ConsumerWidget {
  const MisReclamosClientePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidos = ref.watch(pedidosDelClienteProvider).value ?? const <Pedido>[];

    return MyPantallaClara(
      child: MisReclamosPage(
        bajada: 'Lo que nos contaste y qué te contestamos',
        motivos: MotivosDeReclamo.delCliente,
        // Un pedido en el carrito todavía no es un pedido para el cliente.
        candidatos: [
          for (final p in pedidos.where((p) => p.estado != EstadoPedido.carrito))
            SobreQue(
              pedidoId: p.id,
              titulo: 'Pedido ${p.codigo} · ${p.comercioNombre}',
              bajada: '${p.estado.label} · ${Formato.fechaCorta(p.creadoEn)} · ${Formato.pesos(p.total)}',
            ),
        ],
        volver: () => context.canPop() ? context.pop() : context.go('/cliente/cuenta'),
      ),
    );
  }
}
