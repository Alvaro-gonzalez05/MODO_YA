import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';


/// Lo que ve el cliente del envío de su pedido. Se recalcula cada vez que el
/// pedido cambia.
final _seguimientoProvider = FutureProvider.family<SeguimientoPedido?, String>((ref, id) async {
  final pedido = await ref.watch(pedidoProvider(id).future);
  if (pedido?.envioId == null) return null;
  return ref.read(pedidosRepositoryProvider).seguimiento(id);
});

/// Seguimiento en vivo del pedido (D4).
class PedidoSeguimientoPage extends ConsumerStatefulWidget {
  const PedidoSeguimientoPage({super.key, required this.pedidoId});

  final String pedidoId;

  @override
  ConsumerState<PedidoSeguimientoPage> createState() => _PedidoSeguimientoPageState();
}

class _PedidoSeguimientoPageState extends ConsumerState<PedidoSeguimientoPage> {
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    // El cliente no puede leer la tabla de envios (RLS), asi que no le llegan
    // por Realtime los pasos intermedios del rider (asignado, en el local) ni
    // su posicion. Mientras el pedido esta en curso se relee cada 15 s.
    _refresco = Timer.periodic(const Duration(seconds: 15), (_) {
      final p = ref.read(pedidoProvider(widget.pedidoId)).value;
      if (p != null && !p.estado.esFinal) ref.invalidate(_seguimientoProvider(widget.pedidoId));
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pedido = ref.watch(pedidoProvider(widget.pedidoId));
    final seg = ref.watch(_seguimientoProvider(widget.pedidoId)).value;

    return MyPantallaClara(
      child: MyAsync(
        valor: pedido,
        datos: (p) => p == null
            ? const MyEmptyState(title: 'Pedido no encontrado', message: 'Puede que ya no exista.')
            : _Contenido(pedido: p, seguimiento: seg),
      ),
    );
  }
}

class _Contenido extends ConsumerWidget {
  const _Contenido({required this.pedido, required this.seguimiento});

  final Pedido pedido;
  final SeguimientoPedido? seguimiento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = seguimiento;
    final e = pedido.estado;
    final destino = pedido.entrega;

    final (titulo, bajada) = switch (e) {
      EstadoPedido.pendientePago => ('Recibimos tu pedido', 'Estamos confirmando el pago. Te avisamos enseguida.'),
      EstadoPedido.pagado => ('Enviado al local', 'Esperando que ${pedido.comercioNombre} lo acepte.'),
      EstadoPedido.aceptado => ('Pedido aceptado', '${pedido.comercioNombre} ya lo tiene.'),
      EstadoPedido.enPreparacion => ('En preparación', 'Lo están preparando.'),
      EstadoPedido.listo => (
          s?.repartidorNombre == null ? 'Listo, buscando rider' : '${s!.repartidorNombre} va a buscarlo',
          s?.repartidorNombre == null ? 'Le estamos avisando al rider más cercano.' : 'En unos minutos sale para tu casa.'
        ),
      EstadoPedido.enCamino => ('En camino', '${s?.repartidorNombre ?? 'Tu rider'} va para tu casa.'),
      EstadoPedido.entregado => ('Entregado', '¡Que lo disfrutes!'),
      EstadoPedido.rechazado => ('El local no pudo tomarlo', pedido.motivoRechazo ?? 'Te devolvemos el dinero.'),
      EstadoPedido.cancelado => ('Pedido cancelado', 'Si ya habías pagado, te devolvemos el dinero.'),
      EstadoPedido.carrito => ('', ''),
    };

    return MyPagina(
      volver: () => context.canPop() ? context.pop() : context.go('/cliente/pedidos'),
      rotulo: pedido.comercioNombre,
      titulo: 'Tu pedido',
      bajada: 'Se actualiza solo',
      anchoMaximo: 760,
      conDock: false,
      children: [
        if (!e.esFinal && destino.tieneCoordenadas) ...[
          MyMapaVista(
            alto: context.esMovil ? 220 : 320,
            radio: MyRadius.card,
            marcadores: [
              MyMarcador(punto: LatLng(destino.lat!, destino.lng!), icono: Symbols.home, color: MyColors.dock),
              if (s?.riderLat != null && s?.riderLng != null)
                MyMarcador(
                  punto: LatLng(s!.riderLat!, s.riderLng!),
                  icono: Symbols.sports_motorsports,
                  etiqueta: s.repartidorNombre?.split(' ').first,
                ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
        ],
        Row(
          children: [
            MyBadge(titulo, tone: e.esFinal && e != EstadoPedido.entregado ? MyBadgeTone.danger : MyBadgeTone.ember, dot: !e.esFinal),
            const Spacer(),
            Text('Pedido ${pedido.codigo}', style: MyType.labelMd.copyWith(color: MyColors.claroTextoSecundario)),
          ],
        ),
        const SizedBox(height: MySpacing.sm),
        if (!e.esFinal && pedido.minutosEstimados != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('~${s?.minutosEstimados ?? pedido.minutosEstimados}', style: MyType.displayLg),
              const SizedBox(width: MySpacing.xxs),
              Text('min', style: MyType.headlineSm.copyWith(color: MyColors.claroAcento)),
            ],
          ),
        Text(bajada, style: MyType.bodyMd.copyWith(color: MyColors.claroTextoSecundario)),
        const SizedBox(height: MySpacing.lg),

        if (!e.esFinal || e == EstadoPedido.entregado) ...[
          _Pasos(estado: e),
          const SizedBox(height: MySpacing.lg),
        ],

        if (s?.codigoEntrega != null && e == EstadoPedido.enCamino) ...[
          MyCard(
            color: MyColors.primaryFixed,
            shadows: const [],
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
                  child: const Icon(Symbols.verified_user, color: Colors.white),
                ),
                const SizedBox(width: MySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text('Código de entrega',
                                  style: MyType.labelLg.copyWith(color: MyColors.onPrimaryFixed))),
                          Text(s!.codigoEntrega!, style: MyType.headlineLg.copyWith(color: MyColors.primary, letterSpacing: 4)),
                        ],
                      ),
                      Text('Decile este código al rider cuando te entregue.',
                          style: MyType.bodySm.copyWith(color: MyColors.onPrimaryFixedVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MySpacing.md),
        ],

        if (s?.repartidorNombre != null && !e.esFinal) ...[
          MyCard(
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(color: MyColors.primaryFixed, shape: BoxShape.circle),
                  child: const Icon(Symbols.sports_motorsports, color: MyColors.primary),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s!.repartidorNombre!, style: MyType.headlineSm),
                      Text(s.vehiculo?.label ?? '', style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
                    ],
                  ),
                ),
                const MyBadge('Tu rider', tone: MyBadgeTone.ember),
              ],
            ),
          ),
          const SizedBox(height: MySpacing.md),
        ],

        MyCard(
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              shape: const Border(),
              leading: const Icon(Symbols.receipt_long, color: MyColors.primary),
              title: Text('Detalle del pedido', style: MyType.labelLg),
              subtitle: Text('${pedido.cantidadProductos} productos · ${Formato.pesos(pedido.total)}',
                  style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
              childrenPadding: const EdgeInsets.fromLTRB(MySpacing.md, 0, MySpacing.md, MySpacing.md),
              children: [
                for (final i in pedido.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MySpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i.cantidad}× ', style: MyType.labelLg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.nombreProducto, style: MyType.bodyMd),
                              for (final o in i.opciones) Text(o, style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
                            ],
                          ),
                        ),
                        Text(Formato.pesos(i.subtotal), style: MyType.labelMd),
                      ],
                    ),
                  ),
                const Divider(),
                _Linea('Productos', Formato.pesos(pedido.subtotal)),
                _Linea('Envío', Formato.pesos(pedido.costoEnvio)),
                _Linea('Total', Formato.pesos(pedido.total), destacado: true),
                const SizedBox(height: MySpacing.xs),
                _Linea('Entrega', destino.calle),
              ],
            ),
          ),
        ),

        if (e == EstadoPedido.pendientePago || e == EstadoPedido.pagado) ...[
          const SizedBox(height: MySpacing.lg),
          TextButton.icon(
            onPressed: () async {
              final ok = await confirmar(
                context,
                titulo: 'Cancelar pedido',
                mensaje: 'El local todavía no lo empezó a preparar. Si ya pagaste, te devolvemos el dinero.',
                aceptar: 'Cancelar pedido',
                peligroso: true,
              );
              if (!ok) return;
              try {
                await ref.read(pedidosRepositoryProvider).cancelar(pedido.id, 'Cancelado por el cliente');
              } catch (err) {
                if (context.mounted) mostrarError(context, err);
              }
            },
            style: TextButton.styleFrom(foregroundColor: MyColors.claroError),
            icon: const Icon(Symbols.cancel, size: 18),
            label: const Text('Cancelar pedido'),
          ),
        ],
        const SizedBox(height: MySpacing.xl),
      ],
    );
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.estado});

  final EstadoPedido estado;

  @override
  Widget build(BuildContext context) {
    final pasos = [
      ('Confirmado', Symbols.check, EstadoPedido.aceptado),
      ('En cocina', Symbols.skillet, EstadoPedido.enPreparacion),
      ('En camino', Symbols.sports_motorsports, EstadoPedido.enCamino),
      ('Entregado', Symbols.home, EstadoPedido.entregado),
    ];
    bool hecho(EstadoPedido p) => estado.index >= p.index;

    return MyCard(
      color: MyColors.claroSuperficieAlt,
      shadows: const [],
      padding: const EdgeInsets.all(MySpacing.md),
      child: Row(
        children: [
          for (var i = 0; i < pasos.length; i++) ...[
            if (i > 0)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  height: 2,
                  color: hecho(pasos[i].$3) ? MyColors.primary : MyColors.claroBorde,
                ),
              ),
            Column(
              children: [
                MyPasoCirculo(
                  activo: hecho(pasos[i].$3),
                  icon: pasos[i].$2,
                  size: 32,
                  iconSize: 16,
                  colorActivo: MyColors.primary,
                  colorInactivo: MyColors.claroBorde,
                  iconoActivo: MyColors.onPrimary,
                  iconoInactivo: MyColors.claroTextoSecundario,
                ),
                const SizedBox(height: MySpacing.xxs),
                Text(pasos[i].$1, style: MyType.labelSm.copyWith(color: hecho(pasos[i].$3) ? MyColors.claroAcento : MyColors.claroTextoSecundario)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.label, this.valor, {this.destacado = false});

  final String label;
  final String valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MySpacing.xxs),
        child: Row(
          children: [
            Text(label, style: MyType.bodyMd.copyWith(color: MyColors.claroTextoSecundario)),
            const SizedBox(width: MySpacing.md),
            Expanded(
              child: Text(
                valor,
                textAlign: TextAlign.right,
                style: destacado ? MyType.headlineSm.copyWith(color: MyColors.claroAcento) : MyType.labelLg,
              ),
            ),
          ],
        ),
      );
}
