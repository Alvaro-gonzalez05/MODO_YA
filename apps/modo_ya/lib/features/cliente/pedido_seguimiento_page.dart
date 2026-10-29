import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/reclamos.dart';
import 'detalle_pedido.dart';

/// Lo que ve el cliente del envío de su pedido, en vivo.
///
/// `envios` y `repartidores` son invisibles para el cliente (RLS, a propósito:
/// ahí están los datos del rider y de la operación), así que Realtime no le
/// manda ni los pasos del envío ni la posición de la motito: eso hay que ir a
/// buscarlo. Lo que sí le llega en vivo es su fila de `pedidos`, y con eso el
/// seguimiento se relee en el mismo instante en que el pedido cambia de
/// estado, sin esperar ningún reloj.
///
/// Entre estado y estado lo único que se mueve es el rider, y eso marca el
/// ritmo del refresco. La app del rider manda su posición como mucho cada 10 s
/// (ver `apps/repartidor/lib/features/ubicacion.dart`), así que releer cada 5 s
/// mientras viene alcanza para no perderse ninguna lectura y no tiene sentido
/// ir más rápido. Antes de que salga del local se relee cada 20 s (no hay nada
/// que mirar) y cuando el pedido termina no se relee más.
///
/// Es público solo para que los tests de la pantalla lo puedan reemplazar: el
/// de verdad necesita Supabase.
final seguimientoDelPedidoProvider = StreamProvider.family<SeguimientoPedido?, String>((ref, id) {
  final estado = ref.watch(pedidoProvider(id).select((p) => p.value?.estado));
  if (estado == null || estado == EstadoPedido.carrito) return Stream.value(null);

  final pedidos = ref.read(pedidosRepositoryProvider);
  SeguimientoPedido? ultimo;

  return enVivo(
    canal: 'seguimiento-$id',
    tablas: const ['pedidos'],
    // Si se corta la red se devuelve la última lectura: un error de un segundo
    // no tiene por qué borrarle la motito del mapa.
    leer: () async {
      try {
        return ultimo = await pedidos.seguimiento(id);
      } catch (_) {
        return ultimo;
      }
    },
    refrescarCada: estado.esFinal
        ? null
        : estado == EstadoPedido.enCamino
            ? const Duration(seconds: 5)
            : const Duration(seconds: 20),
  );
});

/// Seguimiento en vivo del pedido (D4).
class PedidoSeguimientoPage extends ConsumerWidget {
  const PedidoSeguimientoPage({super.key, required this.pedidoId});

  final String pedidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedido = ref.watch(pedidoProvider(pedidoId));
    final seg = ref.watch(seguimientoDelPedidoProvider(pedidoId)).value;

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

class _Contenido extends ConsumerStatefulWidget {
  const _Contenido({required this.pedido, required this.seguimiento});

  final Pedido pedido;
  final SeguimientoPedido? seguimiento;

  @override
  ConsumerState<_Contenido> createState() => _ContenidoState();
}

class _ContenidoState extends ConsumerState<_Contenido> {
  /// El camino del rider hasta la casa. Se queda con el último calculado
  /// mientras llega el siguiente, así la línea no desaparece en cada lectura.
  MyRuta? _ruta;

  /// Posición del rider con la que se pidió [_ruta].
  LatLng? _rutaDesde;

  /// Para descartar una respuesta vieja que llega tarde y pisaría a la nueva.
  var _vuelta = 0;

  @override
  void initState() {
    super.initState();
    _pedirRuta();
  }

  @override
  void didUpdateWidget(_Contenido anterior) {
    super.didUpdateWidget(anterior);
    _pedirRuta();
  }

  LatLng? get _rider {
    final s = widget.seguimiento;
    if (s?.riderLat == null || s?.riderLng == null) return null;
    return LatLng(s!.riderLat!, s.riderLng!);
  }

  LatLng? get _destino {
    final d = widget.pedido.entrega;
    return d.tieneCoordenadas ? LatLng(d.lat!, d.lng!) : null;
  }

  void _pedirRuta() {
    final rider = _rider;
    final destino = _destino;
    if (rider == null || destino == null || widget.pedido.estado.esFinal) return;
    // El GPS tiembla aunque la moto esté parada: por menos de media cuadra no
    // vale la pena otra consulta (y el servidor de rutas es público y gratis,
    // conviene no castigarlo).
    //
    // La comparación es contra el punto del que ya se pidió, esté la respuesta
    // o no. Si acá se mirara `_ruta`, cada reconstrucción de la pantalla
    // mientras la primera consulta está en el aire largaría otra y anularía la
    // anterior con `_vuelta`: si la consulta tarda más que el refresco, nunca
    // llega ninguna y no se dibuja ningún camino.
    final desde = _rutaDesde;
    if (desde != null && MyMapa.metrosEntre(desde, rider) < 40) return;

    _rutaDesde = rider;
    final vuelta = ++_vuelta;
    // MyMapa.ruta nunca falla: si el servicio no contesta vuelve la recta.
    MyMapa.ruta(desde: rider, hasta: destino).then((r) {
      if (mounted && vuelta == _vuelta) setState(() => _ruta = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pedido = widget.pedido;
    final s = widget.seguimiento;
    final e = pedido.estado;
    final destino = pedido.entrega;
    final rider = _rider;

    // Mientras viene, los minutos que salen del camino real valen mucho más
    // que el estimado fijo que calculó el servidor cuando se creó el envío.
    final duracion = _ruta?.duracion;
    final minutos = (e == EstadoPedido.enCamino && duracion != null
            ? math.max(1, (duracion.inSeconds / 60).round())
            : null) ??
        s?.minutosEstimados ??
        pedido.minutosEstimados;

    final (titulo, bajada) = switch (e) {
      EstadoPedido.pendientePago => ('Falta pagarlo', 'Terminá el pago y el local lo empieza a preparar.'),
      EstadoPedido.pagado => (
          'Enviado al local',
          'Esperando que ${pedido.comercioNombre} lo acepte. Si no responde en '
              '${Pedido.minutosParaResponder} minutos, te devolvemos todo.'
        ),
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
            // Se puede mover y hacer zoom: el que quiere ver por qué calle
            // viene no tiene que conformarse con el encuadre automático.
            interactivo: true,
            // El camino solo tiene sentido si hay un rider de dónde salir.
            ruta: rider == null ? null : _ruta?.puntos,
            marcadores: [
              MyMarcador(punto: LatLng(destino.lat!, destino.lng!), icono: Symbols.home, color: MyColors.dock),
              if (rider != null)
                MyMarcador(
                  punto: rider,
                  icono: Symbols.sports_motorsports,
                  etiqueta: s?.repartidorNombre?.split(' ').first,
                  animado: true,
                ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
        ],
        // Wrap y no Row: a 360 px "Listo, buscando rider" y el código no
        // entraban juntos y la pastilla desbordaba (su texto no se achica).
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: MySpacing.sm,
          runSpacing: MySpacing.xs,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!e.esFinal) ...[const MyPulso(size: 8), const SizedBox(width: MySpacing.xxs)],
                MyBadge(
                  titulo,
                  tone: e == EstadoPedido.entregado
                      ? MyBadgeTone.success
                      : e.esFinal
                          ? MyBadgeTone.danger
                          : MyBadgeTone.ember,
                ),
              ],
            ),
            Text('Pedido ${pedido.codigo}', style: MyType.labelMd.copyWith(color: MyColors.claroTextoSecundario)),
          ],
        ),
        const SizedBox(height: MySpacing.sm),
        if (!e.esFinal && minutos != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('~$minutos', style: MyType.displayLg),
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
          // El código grande y solo en su renglón: es lo que hay que dictar
          // en la puerta. Al lado del título, a 360 px el título se partía
          // en dos y el número quedaba apretado contra el borde.
          MyCard(
            color: MyColors.primaryFixed,
            shadows: const [],
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
                  child: Icon(Symbols.verified_user, color: MyColors.onPrimary, fill: 1),
                ),
                const SizedBox(width: MySpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MyOverline('Código de entrega', color: MyColors.onPrimaryFixedVariant),
                      SelectableText(
                        s!.codigoEntrega!.split('').join(' '),
                        style: MyType.displayLg.copyWith(color: MyColors.onPrimaryFixed, letterSpacing: 4),
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
                  decoration: BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
                  child: Icon(Symbols.sports_motorsports, color: MyColors.onPrimary, fill: 1),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s!.repartidorNombre!, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
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
              leading: Icon(Symbols.receipt_long, color: MyColors.onSurface),
              title: Text('Detalle del pedido', style: MyType.labelLg),
              subtitle: Text('${pedido.cantidadProductos} productos · ${Formato.pesos(pedido.total)}',
                  style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
              childrenPadding: const EdgeInsets.fromLTRB(MySpacing.md, 0, MySpacing.md, MySpacing.md),
              // Un pedido terminado ya no tiene mapa ni pasos que mirar: el
              // detalle viene abierto.
              initiallyExpanded: e.esFinal,
              children: [DetalleDelPedido(pedido: pedido)],
            ),
          ),
        ),

        // Sin esto, un pedido que quedó esperando el pago no se puede pagar: el
        // único enlace a la pantalla de pago estaba en el carrito, justo
        // después de crearlo. El que se iba de ahí lo perdía, y a la media hora
        // lo cerraba `cerrar_pagos_vencidos()`.
        if (e == EstadoPedido.pendientePago) ...[
          const SizedBox(height: MySpacing.lg),
          MyBoton(
            label: 'Pagar ${Formato.pesos(pedido.total)}',
            icon: Symbols.credit_card,
            onPressed: () => context.go('/cliente/pagar/${pedido.id}'),
          ),
        ],

        // El reclamo recién tiene sentido cuando el pedido ya pasó por el
        // local: antes de eso lo que se quiere es cancelarlo, no reclamar.
        if (e != EstadoPedido.pendientePago && e != EstadoPedido.carrito) ...[
          const SizedBox(height: MySpacing.lg),
          ReclamoDelPedido(pedido: pedido),
        ],

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

    Widget linea(bool encendida) => Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            height: 2,
            color: encendida ? MyColors.primary : MyColors.claroBorde,
          ),
        );

    // Cuatro columnas del mismo ancho, con la línea que las une partida en
    // dos mitades por paso. Antes cada paso medía lo que su texto y la línea
    // ocupaba lo que sobraba: a 360 px no sobraba nada.
    return MyCard(
      color: MyColors.claroSuperficieAlt,
      shadows: const [],
      padding: const EdgeInsets.symmetric(horizontal: MySpacing.xs, vertical: MySpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < pasos.length; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      if (i == 0) const Spacer() else linea(hecho(pasos[i].$3)),
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
                      if (i == pasos.length - 1) const Spacer() else linea(hecho(pasos[i + 1].$3)),
                    ],
                  ),
                  const SizedBox(height: MySpacing.xxs),
                  Text(
                    pasos[i].$1,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: MyType.labelSm.copyWith(
                      color: hecho(pasos[i].$3) ? MyColors.claroAcento : MyColors.claroTextoSecundario,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

