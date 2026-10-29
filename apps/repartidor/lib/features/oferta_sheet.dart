import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Respuesta del rider a una oferta.
enum RespuestaOferta { acepta, rechaza, vencio }

/// Oferta de nuevo servicio (B3). El anillo es la cuenta regresiva: si no
/// responde a tiempo, el envio pasa al siguiente rider.
///
/// Sin datos del cliente: todavia no acepto (la vista de la base tampoco los
/// trae).
class OfertaSheet extends ConsumerStatefulWidget {
  const OfertaSheet({super.key, required this.oferta});

  final OfertaServicio oferta;

  static Future<RespuestaOferta> mostrar(BuildContext context, OfertaServicio oferta) async {
    final r = await showModalBottomSheet<RespuestaOferta>(
      context: context,
      // Sin el navigator raiz, el dock flotante queda encima de los botones.
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => OfertaSheet(oferta: oferta),
    );
    return r ?? RespuestaOferta.vencio;
  }

  @override
  ConsumerState<OfertaSheet> createState() => _OfertaSheetState();
}

class _OfertaSheetState extends ConsumerState<OfertaSheet> {
  late Timer _timer;
  late Duration _restante = widget.oferta.restante;
  late final int _totalMs = (widget.oferta.expiraEn.difference(widget.oferta.envio.creadoEn)).inMilliseconds.clamp(1, 600000);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final r = widget.oferta.restante;
      setState(() => _restante = r);
      if (r == Duration.zero) _cerrar(RespuestaOferta.vencio);
    });
  }

  /// Cierra la hoja una sola vez. El reloj se frena antes: si siguiera
  /// andando mientras la hoja se va, al llegar a cero volveria a cerrar y se
  /// llevaria puestas las pantallas de abajo (la app quedaba en negro si el
  /// rider aceptaba en los ultimos segundos).
  void _cerrar(RespuestaOferta respuesta) {
    if (!_timer.isActive) return;
    _timer.cancel();
    if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop(respuesta);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.oferta;
    final envio = o.envio;
    final progreso = (_restante.inMilliseconds / _totalMs).clamp(0.0, 1.0);
    // Si ya va para ese mismo local (0056), la oferta lo dice: es un pedido que
    // se suma al viaje, no un viaje nuevo. En vivo: al abrir la app la oferta
    // puede llegar antes que la lista de envios en curso.
    final sumaA = envio.esMandado
        ? null
        : (ref.watch(enviosEnCursoProvider).value ?? const <Envio>[])
            .where((e) => !e.esMandado && e.comercioId == envio.comercioId)
            .firstOrNull;

    // Los otros envíos que ya lleva (0077: con uno encima le puede llegar
    // otro, de cualquier local). Que lo sepa antes de aceptar.
    final lleva = (ref.watch(enviosEnCursoProvider).value ?? const <Envio>[]).length;

    // En un celular bajo el anillo grande se comía la pantalla y los botones
    // quedaban debajo, con el reloj corriendo.
    final alto = MediaQuery.sizeOf(context).height;
    final anillo = alto < 700 ? 168.0 : 210.0;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.screenEdge, MySpacing.screenEdge, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: MyBadge(sumaA != null ? 'OTRO PEDIDO' : 'NUEVO SERVICIO',
                              tone: MyBadgeTone.ember, icon: Symbols.notifications_active),
                        ),
                      ),
                      const SizedBox(width: MySpacing.sm),
                      Text(envio.codigo, style: MyType.labelLg),
                    ],
                  ),
                  const SizedBox(height: MySpacing.md),
                  Center(
                    child: SizedBox(
                      width: anillo,
                      height: anillo,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: progreso,
                              strokeWidth: 12,
                              strokeCap: StrokeCap.round,
                              backgroundColor: MyColors.secondaryContainer,
                              valueColor: AlwaysStoppedAnimation(MyColors.primary),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(MySpacing.lg),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MyBadge('${_restante.inSeconds}s', tone: MyBadgeTone.ember, icon: Symbols.timer),
                                const SizedBox(height: MySpacing.xs),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(Formato.pesos(envio.cotizacion.gananciaRepartidor), style: MyType.displayLg),
                                ),
                                const MyOverline('Tu ganancia'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Antes de aceptar tiene que saber si va a manejar plata o posnet.
                  if (envio.hayQueCobrar) ...[
                    const SizedBox(height: MySpacing.sm),
                    Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: MyBadge(
                          envio.textoCobro,
                          tone: MyBadgeTone.ember,
                          icon: envio.cobroMetodo == MetodoPago.tarjeta ? Symbols.credit_card : Symbols.payments,
                        ),
                      ),
                    ),
                  ],
                  // Ya va para ese local: este se retira en el mismo viaje.
                  if (sumaA case final s?) ...[
                    const SizedBox(height: MySpacing.md),
                    _Aviso(
                      icono: Symbols.package_2,
                      texto: 'Es de ${envio.comercioNombre}, igual que tu ${s.codigo}: lo retirás en el mismo viaje.',
                    ),
                  ] else if (lleva > 0) ...[
                    const SizedBox(height: MySpacing.md),
                    _Aviso(
                      icono: Symbols.local_shipping,
                      texto: 'Ya llevás $lleva ${lleva == 1 ? 'envío' : 'envíos'}: si aceptás, '
                          'este se suma a tu recorrido.',
                    ),
                  ],
                  const SizedBox(height: MySpacing.lg),
                  MyStatRow(tiles: [
                    MyStatTile(
                        icon: Symbols.near_me,
                        value: Formato.km(o.distanciaAlRetiroKm),
                        label: envio.esMandado ? 'Hasta el retiro' : 'Hasta el local'),
                    MyStatTile(icon: Symbols.route, value: Formato.km(envio.cotizacion.distanciaKm), label: 'Viaje'),
                    MyStatTile(icon: Symbols.schedule, value: '${envio.cotizacion.minutosEstimados}', label: 'Min est.'),
                  ]),
                  const SizedBox(height: MySpacing.md),
                  if (envio.origen.tieneCoordenadas && envio.destino.tieneCoordenadas) ...[
                    MyMapaVista(
                      alto: alto < 700 ? 120 : 150,
                      marcadores: [
                        MyMarcador(
                          punto: LatLng(envio.origen.lat!, envio.origen.lng!),
                          icono: envio.esMandado ? Symbols.pin_drop : Symbols.storefront,
                          etiqueta: 'Retiro',
                        ),
                        MyMarcador(
                          punto: LatLng(envio.destino.lat!, envio.destino.lng!),
                          icono: Symbols.home,
                          color: MyColors.dock,
                          etiqueta: 'Entrega',
                        ),
                      ],
                    ),
                    const SizedBox(height: MySpacing.md),
                  ],
                  MyRouteTimeline(
                    stops: [
                      MyRouteStop(
                        overline: 'Retiro',
                        title: envio.nombreRetiro,
                        // En un mandado, qué retirar es lo que decide si le sirve.
                        subtitle: [
                          envio.origen.calle,
                          if (envio.esMandado && envio.origen.referencia != null) envio.origen.referencia!,
                        ].join(' - '),
                        icon: Symbols.restaurant,
                      ),
                      MyRouteStop(
                        overline: 'Entrega',
                        title: envio.destino.calle,
                        subtitle: 'Los datos del cliente aparecen al aceptar',
                        icon: Symbols.home,
                        iconBackground: MyColors.dock,
                      ),
                    ],
                  ),
                  const SizedBox(height: MySpacing.md),
                ],
              ),
            ),
          ),
          // Fijos abajo: el detalle se puede bajar, pero aceptar o rechazar
          // tiene que estar a mano sin buscarlo mientras corre el reloj.
          DecoratedBox(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: MyColors.outlineVariant))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.sm, MySpacing.screenEdge, MySpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _cerrar(RespuestaOferta.rechaza),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => _cerrar(RespuestaOferta.acepta),
                      icon: const Icon(Symbols.bolt, size: 22, fill: 1),
                      label: const Text('Aceptar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recuadro amarillo pálido con un dato que cambia la decisión de aceptar.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MySpacing.sm),
      decoration: BoxDecoration(
        color: MyColors.primaryFixed,
        borderRadius: BorderRadius.circular(MyRadius.lg),
      ),
      child: Row(
        children: [
          Icon(icono, color: MyColors.onPrimaryFixed, fill: 1),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Text(texto, style: MyType.labelLg.copyWith(color: MyColors.onPrimaryFixed)),
          ),
        ],
      ),
    );
  }
}
