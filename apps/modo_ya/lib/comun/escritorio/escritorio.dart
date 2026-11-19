/// Lo que la app hace distinto en la compu (Windows): la X minimiza y los
/// avisos del sistema con la ventana minimizada. En el celular y en la web no
/// hace nada.
///
/// Va separado por import condicional porque `window_manager` y
/// `local_notifier` no existen en la web y el build web (el server local) no
/// compilaría.
library;

export 'escritorio_stub.dart' if (dart.library.io) 'escritorio_io.dart';
