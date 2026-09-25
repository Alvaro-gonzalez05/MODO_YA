import 'package:intl/intl.dart';

/// Formateo consistente de plata, distancias y tiempos para las tres apps.
abstract final class Formato {
  // NumberFormat.currency con locale es_AR deja el simbolo detras
  // ("3.500 $"). En Argentina se escribe antes, asi que fijamos el patron.
  static final _moneda = NumberFormat(r"$#,##0", 'es_AR');

  static final _hora = DateFormat('HH:mm', 'es_AR');
  static final _fechaHora = DateFormat("d 'de' MMMM, HH:mm", 'es_AR');
  static final _fechaCorta = DateFormat('dd/MM/yy', 'es_AR');
  static final _fechaLarga = DateFormat("d 'de' MMMM", 'es_AR');

  /// `$3.500`
  static String pesos(num monto) => _moneda.format(monto).trim();

  /// `2,4 km`
  static String km(double valor) =>
      '${valor.toStringAsFixed(1).replaceAll('.', ',')} km';

  /// `12 min`
  static String minutos(int valor) => '$valor min';

  /// `18:42`
  static String hora(DateTime d) => _hora.format(d);

  /// `13 de septiembre, 18:42`
  static String fechaHora(DateTime d) => _fechaHora.format(d);

  /// `13/09/26`
  static String fechaCorta(DateTime d) => _fechaCorta.format(d);

  /// `13 de septiembre`
  static String fechaLarga(DateTime d) => _fechaLarga.format(d);

  /// Antiguedad legible: `hace 2 min`, `hace 3 h`.
  static String haceCuanto(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'recien';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  /// Cuenta regresiva `0:24` para la ventana de aceptacion del cadete.
  static String cuentaRegresiva(Duration d) {
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$s';
  }
}
