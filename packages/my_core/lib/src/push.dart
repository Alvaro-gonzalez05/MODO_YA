import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'backend.dart';

/// Las notificaciones que llegan al celular con la app cerrada.
///
/// Firebase entra **solo como el caño**: los datos siguen en Supabase y la app
/// los lee de ahí. FCM es lo único que despierta un Android con la app cerrada,
/// porque el sistema operativo mantiene una sola conexión para todas las apps
/// en vez de una por app.
///
/// Todo lo de acá es opcional a propósito: si Firebase no está configurado, si
/// la persona no da permiso o si la plataforma no lo soporta, la app sigue
/// andando igual y la notificación se ve en la campanita al abrirla. Nunca
/// puede romper el arranque.
class MyPush {
  MyPush._();

  static String? _token;
  static var _iniciado = false;

  /// Lo que se toca al abrir una notificación, para que la app navegue.
  /// Llega el `data` que mandó la Edge Function (destino, pedido_id...).
  static final alTocar = StreamController<Map<String, String>>.broadcast();

  /// Solo Android por ahora. iOS necesita cuenta de desarrollador de Apple y
  /// certificados; Windows no lo soporta FCM (y ahí la app está abierta
  /// mientras se usa, así que recibe todo en vivo por Realtime).
  static bool get soportado =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Arranca Firebase. Se llama una vez, antes de `runApp`.
  static Future<void> iniciar() async {
    if (!soportado || _iniciado) return;
    try {
      await Firebase.initializeApp();
      _iniciado = true;

      // La app abierta desde una notificación: el `data` llega acá.
      FirebaseMessaging.onMessageOpenedApp.listen(_avisar);
      final inicial = await FirebaseMessaging.instance.getInitialMessage();
      if (inicial != null) _avisar(inicial);

      // El token cambia solo (reinstalación, limpieza de datos). Si no se
      // vuelve a guardar, los avisos se mandan a un celular que ya no escucha.
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        _guardar(t);
      });
    } catch (e) {
      // Sin Firebase configurado la app tiene que seguir andando igual.
      debugPrint('MyPush: no se pudo iniciar Firebase: $e');
    }
  }

  static void _avisar(RemoteMessage m) {
    alTocar.add(m.data.map((k, v) => MapEntry(k, '$v')));
  }

  /// Pide permiso y registra el celular. Se llama al iniciar sesión, no al
  /// abrir la app: antes de saber quién es no hay a quién anotarle el token.
  static Future<void> registrar() async {
    if (!soportado || !_iniciado) return;
    try {
      final permiso = await FirebaseMessaging.instance.requestPermission();
      if (permiso.authorizationStatus == AuthorizationStatus.denied) return;

      final t = await FirebaseMessaging.instance.getToken();
      if (t == null) return;
      _token = t;
      await _guardar(t);
    } catch (e) {
      debugPrint('MyPush: no se pudo registrar el celular: $e');
    }
  }

  /// Borra el token al cerrar sesión: si no, el que preste el celular recibe
  /// las notificaciones del dueño anterior.
  static Future<void> olvidar() async {
    final t = _token;
    if (t == null) return;
    _token = null;
    try {
      await Backend.db.rpc('borrar_push_token', params: {'p_token': t});
    } catch (e) {
      debugPrint('MyPush: no se pudo borrar el token: $e');
    }
  }

  static Future<void> _guardar(String token) async {
    try {
      await Backend.db.rpc('guardar_push_token', params: {
        'p_token': token,
        'p_plataforma': 'android',
      });
    } catch (e) {
      debugPrint('MyPush: no se pudo guardar el token: $e');
    }
  }
}
