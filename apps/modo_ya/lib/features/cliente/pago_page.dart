import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_tarjeta.dart';

/// Pago del pedido con tarjeta, dentro de la app.
///
/// El pedido ya está creado y esperando el pago: si la tarjeta rebota, el local
/// no llega a verlo y se puede probar con otra.
class PagoPage extends ConsumerWidget {
  const PagoPage({super.key, required this.pedidoId});

  final String pedidoId;

  Future<String?> _pagar(BuildContext context, WidgetRef ref, Pedido pedido, DatosTarjeta d) async {
    try {
      final repo = ref.read(pagosRepositoryProvider);
      final r = d.guardada != null
          ? await repo.pagarConTarjetaGuardada(
              pedidoId: pedido.id,
              tarjeta: d.guardada!,
              codigo: d.codigo,
              cuotas: d.cuotas,
            )
          : await repo.pagarConTarjetaNueva(
              pedidoId: pedido.id,
              numero: d.numero,
              titular: d.titular,
              mes: d.mes,
              anio: d.anio,
              codigo: d.codigo,
              documento: d.documento,
              cuotas: d.cuotas,
              guardar: d.guardar,
              marca: d.marca,
            );

      if (r.enRevision) {
        // El cobro **ya se hizo** y el banco lo está mirando. Antes esto caía
        // en la tarjeta roja de error con el botón habilitado: el cliente lo
        // leía como un fallo, volvía a tocar "Pagar" y se le cobraba dos veces
        // (hallazgo A3). Al invalidar, la pantalla se rearma mostrando que el
        // pago está en revisión en lugar de pedir la tarjeta otra vez.
        ref.invalidate(estadoDelPagoProvider(pedido.id));
        return null;
      }
      if (!r.aprobado) return r.detalle ?? 'El pago fue rechazado.';
      if (!context.mounted) return null;

      MySonidos.tocar(MySonido.pedidoConfirmado);
      await mostrarExito(
        context,
        titulo: '¡Pago aprobado!',
        mensaje: r.simulado
            ? 'Pago de prueba: todavía no están las credenciales de Mercado Pago.'
            : 'Ya le avisamos a ${pedido.comercioNombre}.',
      );
      if (context.mounted) context.go('/cliente/pedidos/${pedido.id}');
      return null;
    } catch (e) {
      return e is ErrorModoYa ? e.mensaje : 'No se pudo completar el pago.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidoAsync = ref.watch(pedidoProvider(pedidoId));
    final pagoEnRevision = ref.watch(estadoDelPagoProvider(pedidoId)).value == 'en_revision';

    return MyPantallaClara(
      child: MyPagina(
        volver: () => context.go('/cliente'),
        rotulo: 'Pago seguro',
        titulo: 'Pagar con tarjeta',
        conDock: false,
        anchoMaximo: 560,
        children: [
          MyAsync(
            valor: pedidoAsync,
            onReintentar: () => ref.invalidate(pedidoProvider(pedidoId)),
            datos: (pedido) {
              if (pedido == null) {
                return const MyCard(
                  child: MyEmptyState(icon: Symbols.error, title: 'No encontramos el pedido', message: ''),
                );
              }
              if (pedido.estado != EstadoPedido.pendientePago) {
                // Ya se pagó (o se canceló): no hay nada que cobrar.
                return MyCard(
                  child: MyEmptyState(
                    icon: pedido.estado == EstadoPedido.cancelado ? Symbols.cancel : Symbols.check_circle,
                    title: pedido.estado == EstadoPedido.cancelado ? 'El pedido se canceló' : 'Este pedido ya está pago',
                    message: 'Podés ver cómo viene en "Mis pedidos".',
                    action: MyBoton(
                      label: 'Ver el pedido',
                      onPressed: () => context.go('/cliente/pedidos/${pedido.id}'),
                    ),
                  ),
                );
              }
              if (pagoEnRevision) {
                // Hay un cobro hecho y el banco no contestó todavía. Volver a
                // mostrar el formulario es invitar a pagar dos veces el mismo
                // pedido, y la base ya no lo permitiría igual
                // (`tomar_el_cobro`). Cuando el pago se resuelve, el pedido
                // cambia de estado y esta pantalla se va sola: `pedidoProvider`
                // está en vivo.
                return MyCard(
                  child: MyEmptyState(
                    icon: Symbols.hourglass_top,
                    title: 'El banco está revisando tu pago',
                    // "Ya cobramos" y "si no sale no se te cobra" juntos se
                    // contradecían: lo que hay es un cobro que el banco todavía
                    // puede rechazar.
                    message: 'No lo pagues de nuevo: el cobro de ${Formato.pesos(pedido.total)} ya está '
                        'hecho y el banco lo está revisando. Si lo aprueba, el pedido le llega a '
                        '${pedido.comercioNombre}; si no, no se te cobra nada.',
                    action: MyBoton(
                      label: 'Ver el pedido',
                      onPressed: () => context.go('/cliente/pedidos/${pedido.id}'),
                    ),
                  ),
                );
              }
              return FormularioTarjeta(
                etiquetaBoton: 'Pagar ${Formato.pesos(pedido.total)}',
                cuotas: true,
                debajoDelTotal: _Resumen(pedido: pedido),
                onPagar: (d) => _pagar(context, ref, pedido, d),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Productos', style: MyType.bodyMd)),
              Text(Formato.pesos(pedido.subtotal), style: MyType.bodyMd),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: Text('Envío', style: MyType.bodyMd)),
              if (pedido.envioCubierto > 0)
                const MyBadge('Gratis con Plus', tone: MyBadgeTone.success)
              else
                Text(Formato.pesos(pedido.costoEnvio), style: MyType.bodyMd),
            ],
          ),
          const Divider(),
          Row(
            children: [
              Expanded(child: Text('Total', style: MyType.headlineSm)),
              Text(Formato.pesos(pedido.total), style: MyType.headlineMd.copyWith(color: MyColors.tertiary)),
            ],
          ),
        ],
      ),
    );
  }
}
