import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'tokens.dart';
import 'typography.dart';

/// Los sonidos de MODO YA (de dónde sale cada uno: assets/sonidos/LEEME.md).
enum MySonido {
  /// Cliente: el pedido se confirmó. Campana de logro.
  pedidoConfirmado('pedido_confirmado.mp3'),

  /// Cliente: el rider sale para su casa. Timbre de bici.
  riderEnCamino('rider_en_camino.mp3'),

  /// Local: entró un pedido. Timbre de mostrador, cada un segundo hasta que
  /// lo acepta.
  pedidoNuevo('pedido_nuevo.mp3', pausa: Duration(seconds: 1)),

  /// Rider: le ofrecen un envío. Ringtone de marimba hasta que responde.
  ofertaRider('oferta_rider.mp3');

  const MySonido(this.archivo, {this.pausa = Duration.zero});
  final String archivo;

  /// Silencio entre repeticiones cuando suena en loop.
  final Duration pausa;
}

/// Reproduce los sonidos de la app: una vez ([tocar]) o en loop hasta que se
/// corte ([repetir] / [detener]).
///
/// En el navegador, el audio no suena hasta que la persona tocó algo en la
/// página (regla de los navegadores). Si pasa eso, [bloqueado] se prende y
/// [MyAlarma] muestra un botón para activarlo.
class MySonidos {
  MySonidos._();

  static final _reproductores = <MySonido, AudioPlayer>{};
  static final _enLoop = <MySonido>{};
  static final _esperas = <MySonido, Timer>{};

  /// true si el navegador no dejó sonar por falta de interacción.
  static final bloqueado = ValueNotifier(false);

  static AudioPlayer _reproductor(MySonido s) => _reproductores.putIfAbsent(s, () {
        final p = AudioPlayer(playerId: 'modoya-${s.name}');
        p.audioCache = AudioCache(prefix: 'packages/my_ui/assets/sonidos/');
        // Loop con pausa: al terminar, si sigue activo, espera y vuelve a sonar.
        p.onPlayerComplete.listen((_) {
          if (!_enLoop.contains(s) || s.pausa == Duration.zero) return;
          _esperas[s]?.cancel();
          _esperas[s] = Timer(s.pausa, () {
            if (_enLoop.contains(s)) _play(s, loop: true);
          });
        });
        return p;
      });

  static Future<void> _play(MySonido s, {required bool loop}) async {
    final p = _reproductor(s);
    try {
      // Sin pausa, el loop lo hace el reproductor (sin cortes); con pausa, lo
      // maneja onPlayerComplete.
      await p.setReleaseMode(loop && s.pausa == Duration.zero ? ReleaseMode.loop : ReleaseMode.stop);
      await p.stop();
      await p.play(AssetSource(s.archivo), volume: 1);
      bloqueado.value = false;
    } catch (e) {
      // En web, NotAllowedError: todavía no hubo interacción. En el resto,
      // que falle un sonido nunca tiene que romper la pantalla.
      if (kIsWeb) bloqueado.value = true;
      debugPrint('MySonidos: no se pudo reproducir ${s.name}: $e');
    }
  }

  /// Una vez.
  static Future<void> tocar(MySonido s) => _play(s, loop: false);

  /// En loop hasta [detener]. Si ya estaba sonando, no lo reinicia.
  static Future<void> repetir(MySonido s) async {
    if (_enLoop.contains(s) && !bloqueado.value) return;
    _enLoop.add(s);
    await _play(s, loop: true);
  }

  static Future<void> detener(MySonido s) async {
    _enLoop.remove(s);
    _esperas.remove(s)?.cancel();
    await _reproductores[s]?.stop();
  }

  /// Reintenta los que tenían que estar sonando (después de que la persona
  /// tocó "Activar sonido").
  static Future<void> reintentar() async {
    for (final s in _enLoop.toList()) {
      await _play(s, loop: true);
    }
  }
}

/// Hace sonar [sonido] en loop mientras [activa] sea true, y lo corta cuando
/// pasa a false o la pantalla se cierra. Ej.: el local con pedidos nuevos sin
/// aceptar, o el rider con una oferta abierta.
///
/// Si el navegador bloqueó el audio, muestra arriba un botón "Activar sonido".
class MyAlarma extends StatefulWidget {
  const MyAlarma({super.key, required this.activa, required this.sonido, required this.child});

  final bool activa;
  final MySonido sonido;
  final Widget child;

  @override
  State<MyAlarma> createState() => _MyAlarmaState();
}

class _MyAlarmaState extends State<MyAlarma> {
  @override
  void initState() {
    super.initState();
    _aplicar();
  }

  @override
  void didUpdateWidget(MyAlarma viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.activa != widget.activa || viejo.sonido != widget.sonido) {
      if (viejo.sonido != widget.sonido) MySonidos.detener(viejo.sonido);
      _aplicar();
    }
  }

  void _aplicar() => widget.activa ? MySonidos.repetir(widget.sonido) : MySonidos.detener(widget.sonido);

  @override
  void dispose() {
    MySonidos.detener(widget.sonido);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: MySonidos.bloqueado,
          builder: (context, bloqueado, _) {
            if (!bloqueado || !widget.activa) return const SizedBox.shrink();
            return Positioned(
              top: MediaQuery.paddingOf(context).top + MySpacing.sm,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: MyColors.primary,
                  borderRadius: BorderRadius.circular(MyRadius.full),
                  elevation: 8,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(MyRadius.full),
                    onTap: MySonidos.reintentar,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.notifications_active, color: MyColors.onPrimary, fill: 1),
                          const SizedBox(width: MySpacing.xs),
                          Text('Tocá para activar el sonido', style: MyType.labelLg.copyWith(color: MyColors.onPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
