/// La web no tiene ventana que minimizar ni avisos del sistema.
abstract final class Escritorio {
  static Future<void> iniciar() async {}
  static Future<void> quedarEnSegundoPlano(bool activo) async {}
  static Future<void> avisar(String titulo, String cuerpo) async {}
  static bool get puedeCerrarDelTodo => false;
  static Future<void> cerrarDelTodo() async {}
}
