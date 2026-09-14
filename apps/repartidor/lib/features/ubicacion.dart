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

/// Simular la ubicacion solo se permite en desarrollo o en una build de prueba
/// compilada con --dart-define=MY_SIMULAR_UBICACION=true.
const permitirSimularUbicacion = kDebugMode || bool.fromEnvironment('MY_SIMULAR_UBICACION');

/// Ubicacion del rider mientras esta conectado.
///
/// Manda la posicion a la base cada 15 segundos con la app abierta. Esto es lo
/// que usa el motor de asignacion para elegir al rider mas cercano.
///
/// PENDIENTE para produccion: en Android, un foreground service para que siga
/// mandando con la pantalla apagada; en iOS, el modo background "location".
class UbicacionRider extends Notifier<Lectura?> {
  Timer? _timer;

  /// Solo en desarrollo: si la PC no tiene GPS (o Windows tiene la ubicacion
  /// apagada), se usa el centro de Malargue para poder probar el flujo entero.
  var simular = false;

  @override
  Lectura? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  Future<Lectura> leer() async {
    if (simular && permitirSimularUbicacion) {
      return LecturaOk(MyMapa.centroMalargue.latitude, MyMapa.centroMalargue.longitude, simulada: true);
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LecturaError('La ubicacion del dispositivo esta apagada.');
      }
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        return const LecturaError('Sin permiso de ubicacion no te podemos ofrecer envios cercanos.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return LecturaOk(p.latitude, p.longitude);
    } catch (e) {
      return LecturaError('No pudimos leer tu ubicacion ($e).');
    }
  }

  /// Lee, manda a la base y actualiza el estado. Devuelve la lectura.
  Future<Lectura> enviar() async {
    final l = await leer();
    if (l is LecturaOk) {
      try {
        await ref.read(repartidoresRepositoryProvider).actualizarUbicacion(l.lat, l.lng);
      } catch (e) {
        state = LecturaError('$e');
        return state!;
      }
    }
    state = l;
    return l;
  }

  void empezar() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => enviar());
  }

  void parar() {
    _timer?.cancel();
    _timer = null;
  }

  bool get activo => _timer != null;
}

final ubicacionRiderProvider = NotifierProvider<UbicacionRider, Lectura?>(UbicacionRider.new);
