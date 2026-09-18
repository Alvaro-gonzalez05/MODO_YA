import 'dart:async';

import 'package:flutter/material.dart';
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
class OfertaSheet extends StatefulWidget {
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
  State<OfertaSheet> createState() => _OfertaSheetState();
}

class _OfertaSheetState extends State<OfertaSheet> {
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
      if (r == Duration.zero) Navigator.of(context).pop(RespuestaOferta.vencio);
    });
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

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MySpacing.screenEdge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const MyBadge('NUEVO SERVICIO', tone: MyBadgeTone.ember, icon: Symbols.notifications_active),
                const Spacer(),
                Text(envio.codigo, style: MyType.labelLg),
              ],
            ),
            const SizedBox(height: MySpacing.lg),
            Center(
              child: SizedBox(
                width: 210,
                height: 210,
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
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MyBadge('${_restante.inSeconds}s', tone: MyBadgeTone.ember, icon: Symbols.timer),
                        const SizedBox(height: MySpacing.xs),
                        Text(Formato.pesos(envio.cotizacion.gananciaRepartidor), style: MyType.displayLg),
                        const MyOverline('Tu ganancia'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MySpacing.lg),
            MyStatRow(tiles: [
              MyStatTile(icon: Symbols.near_me, value: Formato.km(o.distanciaAlRetiroKm), label: 'Hasta el local'),
              MyStatTile(icon: Symbols.route, value: Formato.km(envio.cotizacion.distanciaKm), label: 'Viaje'),
              MyStatTile(icon: Symbols.schedule, value: '${envio.cotizacion.minutosEstimados}', label: 'Min est.'),
            ]),
            const SizedBox(height: MySpacing.md),
            if (envio.origen.tieneCoordenadas && envio.destino.tieneCoordenadas) ...[
              MyMapaVista(
                alto: 150,
                marcadores: [
                  MyMarcador(punto: LatLng(envio.origen.lat!, envio.origen.lng!), icono: Symbols.storefront),
                  MyMarcador(punto: LatLng(envio.destino.lat!, envio.destino.lng!), icono: Symbols.home, color: MyColors.dock),
                ],
              ),
              const SizedBox(height: MySpacing.md),
            ],
            MyRouteTimeline(
              stops: [
                MyRouteStop(
                  overline: 'Retiro',
                  title: envio.comercioNombre,
                  subtitle: envio.origen.calle,
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
            const SizedBox(height: MySpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(RespuestaOferta.rechaza),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(RespuestaOferta.acepta),
                    icon: const Icon(Symbols.bolt, size: 22, fill: 1),
                    label: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
