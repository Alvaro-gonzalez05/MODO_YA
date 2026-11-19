import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// La app en la compu (Windows).
///
/// **La X minimiza para el local y la administración.** El timbre de un pedido
/// nuevo sale de la app abierta (Realtime): Windows no tiene un push que
/// despierte una app cerrada, así que cerrarla era dejar de enterarse. Al
/// minimizar sale un aviso del sistema que lo dice, con un botón para cerrarla
/// del todo: si no, no habría forma de salir.
///
/// Para el cliente la X cierra como siempre: no espera nada urgente y una app
/// que no se cierra molesta.
abstract final class Escritorio {
  static var _iniciado = false;
  static var _segundoPlano = false;
  static final _oyente = _Oyente();

  static bool get _windows => !kIsWeb && Platform.isWindows;

  /// Una vez, antes de `runApp`. Nunca rompe el arranque.
  static Future<void> iniciar() async {
    if (!_windows || _iniciado) return;
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(_oyente);
      // Los avisos de Windows necesitan un acceso directo con el id de la app;
      // `requireCreate` lo crea si el instalador no lo dejó.
      await localNotifier.setup(appName: 'MODO YA', shortcutPolicy: ShortcutPolicy.requireCreate);
      _iniciado = true;
    } catch (e) {
      debugPrint('Escritorio: no se pudo iniciar: $e');
    }
  }

  /// Prende o apaga "la X minimiza". Se llama con cada cambio de sesión.
  static Future<void> quedarEnSegundoPlano(bool activo) async {
    if (!_iniciado || activo == _segundoPlano) return;
    _segundoPlano = activo;
    try {
      await windowManager.setPreventClose(activo);
    } catch (e) {
      debugPrint('Escritorio: no se pudo cambiar el cierre: $e');
    }
  }

  /// Un aviso de Windows, solo si la ventana no está a la vista: con la app
  /// delante ya suena el timbre y aparece el cartel adentro. Tocarlo la trae.
  static Future<void> avisar(String titulo, String cuerpo) async {
    if (!_iniciado) return;
    try {
      final aLaVista = await windowManager.isVisible() &&
          !await windowManager.isMinimized() &&
          await windowManager.isFocused();
      if (aLaVista) return;
      final aviso = LocalNotification(title: titulo, body: cuerpo);
      aviso.onClick = _traer;
      await aviso.show();
    } catch (e) {
      debugPrint('Escritorio: no se pudo avisar: $e');
    }
  }

  static Future<void> _traer() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  static Future<void> _alCerrar() async {
    // Sin el cierre interceptado la ventana ya se está cerrando sola.
    if (!_segundoPlano) return;
    await windowManager.minimize();
    try {
      final aviso = LocalNotification(
        title: 'MODO YA sigue abierta',
        body: 'Quedó minimizada para avisarte cuando entre un pedido. '
            'Si la cerrás del todo, no te va a sonar nada.',
        actions: [LocalNotificationAction(text: 'Cerrar del todo')],
      );
      aviso.onClick = _traer;
      aviso.onClickAction = (_) => _cerrarDelTodo();
      await aviso.show();
    } catch (e) {
      debugPrint('Escritorio: no se pudo avisar el segundo plano: $e');
    }
  }

  /// Para el menú de la cuenta: el camino para salir si el aviso de Windows
  /// no aparece (avisos apagados en la compu).
  static bool get puedeCerrarDelTodo => _segundoPlano;

  static Future<void> cerrarDelTodo() => _cerrarDelTodo();

  static Future<void> _cerrarDelTodo() async {
    _segundoPlano = false;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}

class _Oyente with WindowListener {
  @override
  void onWindowClose() => Escritorio._alCerrar();
}
