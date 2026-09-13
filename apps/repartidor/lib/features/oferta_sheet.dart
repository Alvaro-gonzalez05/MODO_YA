import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// B3 - Oferta de nuevo servicio.
///
/// El cadete tiene una ventana corta para aceptar; si no responde, el envio se
/// le ofrece al siguiente. Por eso el anillo de cuenta regresiva es el centro
/// visual de la pantalla.
class OfertaSheet extends StatefulWidget {
  const OfertaSheet({super.key, required this.oferta});

  final OfertaServicio oferta;

  /// Devuelve `true` si el cadete acepto.
  static Future<bool?> mostrar(BuildContext context, OfertaServicio oferta) =>
      showModalBottomSheet<bool>(
        context: context,
        // Sin el navigator raiz, la hoja se abre dentro de la rama del shell
        // y el dock flotante le queda encima, tapando los botones.
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => OfertaSheet(oferta: oferta),
      );

  @override
  State<OfertaSheet> createState() => _OfertaSheetState();
}

class _OfertaSheetState extends State<OfertaSheet> {
  late Timer _timer;
  late Duration _restante;
  late final Duration _total;

  @override
  void initState() {
    super.initState();
    _restante = widget.oferta.restante;
    _total = _restante == Duration.zero ? const Duration(seconds: 30) : _restante;
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final r = widget.oferta.restante;
      if (!mounted) return;
      setState(() => _restante = r);
      // Si se agota la ventana, la oferta se cierra sola: el motor de
      // asignacion ya la esta pasando al siguiente cadete.
      if (r == Duration.zero) Navigator.of(context).pop(false);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final envio = widget.oferta.envio;
    final progreso = _total.inMilliseconds == 0
        ? 0.0
        : _restante.inMilliseconds / _total.inMilliseconds;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MySpacing.screenEdge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const MyBadge(
                  'NUEVO SERVICIO',
                  tone: MyBadgeTone.ember,
                  icon: Symbols.notifications_active,
                ),
                const Spacer(),
                const Icon(Symbols.near_me,
                    size: 18, color: MyColors.secondary),
                const SizedBox(width: MySpacing.xxs),
                Text('Malargue urbano', style: MyType.labelLg),
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
                        valueColor: const AlwaysStoppedAnimation(
                          MyColors.primary,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MyBadge(
                          '${_restante.inSeconds}s restantes',
                          tone: MyBadgeTone.ember,
                          icon: Symbols.timer,
                        ),
                        const SizedBox(height: MySpacing.xs),
                        Text(
                          Formato.pesos(envio.cotizacion.gananciaRepartidor),
                          style: MyType.displayLg,
                        ),
                        const MyOverline('Tarifa cadete'),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: MySpacing.lg),
            Container(
              padding: const EdgeInsets.all(MySpacing.md),
              decoration: BoxDecoration(
                color: MyColors.secondaryContainer,
                borderRadius: BorderRadius.circular(MyRadius.full),
              ),
              child: Row(
                children: [
                  const Icon(Symbols.verified, size: 20,
                      color: MyColors.primary),
                  const SizedBox(width: MySpacing.xs),
                  Expanded(
                    child: Text(
                      'Ganancia neta garantizada',
                      style: MyType.bodyMd
                          .copyWith(color: MyColors.onSecondaryFixed),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: MySpacing.md),
            MyStatRow(
              tiles: [
                MyStatTile(
                  icon: Symbols.route,
                  value: Formato.km(envio.cotizacion.distanciaKm),
                  label: 'Total viaje',
                ),
                MyStatTile(
                  icon: Symbols.schedule,
                  value: '${envio.cotizacion.minutosEstimados}',
                  label: 'Tiempo est. (min)',
                ),
                MyStatTile(
                  icon: Symbols.receipt_long,
                  value: '1',
                  label: 'Pedido en caja',
                ),
              ],
            ),

            const SizedBox(height: MySpacing.md),
            MyRouteTimeline(
              stops: [
                MyRouteStop(
                  overline: 'Punto de retiro',
                  title: envio.comercioNombre,
                  subtitle: '${envio.origen.calle} - a '
                      '${Formato.km(widget.oferta.distanciaAlRetiroKm)} de vos',
                  badge: 'A preparar',
                  icon: Symbols.restaurant,
                ),
                MyRouteStop(
                  overline: 'Punto de entrega',
                  title: envio.destino.calle,
                  subtitle: 'Distancia de entrega: '
                      '${Formato.km(envio.cotizacion.distanciaKm)}',
                  badge: 'Domicilio',
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
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Symbols.bolt, size: 22, fill: 1),
                    label: const Text('Aceptar pedido'),
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
