import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Resultado de pedir la ubicacion.
sealed class Lectura {
  const Lectura();
}

class LecturaOk extends Lectura {
  const LecturaOk(this.lat, this.lng, {this.simulada = false});
  final double lat;
  final double lng;
  final bool simulada;
}

class LecturaError extends Lectura {
  const LecturaError(this.mensaje);
  final String mensaje;
}

/// Hay permiso de ubicación pero solo "mientras se usa la app": con la
/// pantalla apagada deja de mandar. Se muestra un aviso para cambiarlo.
class LecturaSinSegundoPlano extends LecturaOk {
  const LecturaSinSegundoPlano(super.lat, super.lng);
}

/// Simular la ubicacion solo se permite en desarrollo o en una build de prueba
/// compilada con --dart-define=MY_SIMULAR_UBICACION=true.
const permitirSimularUbicacion = kDebugMode || bool.fromEnvironment('MY_SIMULAR_UBICACION');

/// Ubicacion del rider mientras esta conectado.
///
/// Escucha el GPS y manda la posicion a la base (como mucho cada 10 s, y al
/// menos cada 30 s aunque no se mueva). Es lo que usa el motor de asignacion
/// para elegir al rider mas cercano.
///
/// En Android corre en un foreground service: sigue mandando con la pantalla
/// apagada o la app minimizada, con una notificacion fija mientras esta
/// conectado. Para eso pide "Permitir todo el tiempo".
class UbicacionRider extends Notifier<Lectura?> {
  Timer? _timer;
  StreamSubscription<Position>? _gps;
  Position? _ultima;
  DateTime? _ultimoEnvio;
  var _segundoPlano = false;

  /// Solo en desarrollo: si la PC no tiene GPS (o Windows tiene la ubicacion
  /// apagada), se usa el centro de Malargue para poder probar el flujo entero.
  var simular = false;

  @override
  Lectura? build() {
    ref.onDispose(parar);
    return null;
  }

  bool get _esAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Pide el permiso y, en el celular, el de segundo plano. Devuelve un error
  /// para mostrar o null si se puede seguir.
  Future<String?> _pedirPermiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'La ubicación del dispositivo esta apagada.';
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
    if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
      return 'Sin permiso de ubicación no te podemos ofrecer envíos cercanos.';
    }
    // En Android, pedirlo otra vez con "mientras se usa" ya concedido abre la
    // pantalla del sistema para elegir "Permitir todo el tiempo".
    if (_esAndroid && permiso == LocationPermission.whileInUse) {
      permiso = await Geolocator.requestPermission();
    }
    _segundoPlano = !_esAndroid || permiso == LocationPermission.always;
    return null;
  }

  /// Abre los ajustes de la app para cambiar el permiso a "todo el tiempo".
  Future<void> abrirAjustes() => Geolocator.openAppSettings();

  LecturaOk _lectura(double lat, double lng) =>
      _segundoPlano ? LecturaOk(lat, lng) : LecturaSinSegundoPlano(lat, lng);

  LocationSettings get _ajustes => _esAndroid
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
          intervalDuration: const Duration(seconds: 10),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'MODO YA Rider: conectado',
            notificationText: 'Mandando tu ubicación para ofrecerte envíos cercanos',
            notificationChannelName: 'Ubicación mientras estás conectado',
            enableWakeLock: true,
            setOngoing: true,
          ),
        )
      : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);

  Future<Lectura> leer() async {
    if (simular && permitirSimularUbicacion) {
      return LecturaOk(MyMapa.centroMalargue.latitude, MyMapa.centroMalargue.longitude, simulada: true);
    }
    try {
      final error = await _pedirPermiso();
      if (error != null) return LecturaError(error);
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      _ultima = p;
      return _lectura(p.latitude, p.longitude);
    } catch (e) {
      return LecturaError('No pudimos leer tu ubicación ($e).');
    }
  }

  /// Lee, manda a la base y actualiza el estado. Devuelve la lectura.
  Future<Lectura> enviar() async {
    final l = await leer();
    if (l is LecturaOk) await _mandar(l);
    if (state is! LecturaError || l is! LecturaOk) state = l;
    return state ?? l;
  }

  Future<void> _mandar(LecturaOk l) async {
    try {
      await ref.read(repartidoresRepositoryProvider).actualizarUbicacion(l.lat, l.lng);
      _ultimoEnvio = DateTime.now();
      state = l;
    } catch (e) {
      state = LecturaError('$e');
    }
  }

  /// Empieza a escuchar el GPS (en Android, con el servicio en segundo plano).
  void empezar() {
    parar();
    if (simular && permitirSimularUbicacion) {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => enviar());
      return;
    }
    _gps = Geolocator.getPositionStream(locationSettings: _ajustes).listen(
      (p) {
        _ultima = p;
        final hace = _ultimoEnvio == null ? null : DateTime.now().difference(_ultimoEnvio!);
        if (hace == null || hace >= const Duration(seconds: 10)) _mandar(_lectura(p.latitude, p.longitude));
      },
      onError: (Object e) => state = LecturaError('No pudimos leer tu ubicación ($e).'),
    );
    // Aunque no se mueva, cada 30 s confirma que sigue ahí.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final p = _ultima;
      if (p != null) _mandar(_lectura(p.latitude, p.longitude));
    });
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
    _gps?.cancel();
    _gps = null;
  }

  bool get activo => _timer != null || _gps != null;
}

final ubicacionRiderProvider = NotifierProvider<UbicacionRider, Lectura?>(UbicacionRider.new);
