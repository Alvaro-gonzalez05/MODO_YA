import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_core/my_core.dart';

/// El carrito vive en memoria: un pedido es de un solo local.
class Carrito {
  const Carrito({this.comercio, this.items = const [], this.nota});

  final Comercio? comercio;
  final List<ItemCarrito> items;
  final String? nota;

  bool get vacio => items.isEmpty;
  int get cantidad => items.fold(0, (s, i) => s + i.cantidad);

  /// Orientativo: el total que vale lo calcula el servidor al crear el pedido.
  int get subtotal => items.fold(0, (s, i) => s + i.subtotal);
}

class CarritoNotifier extends Notifier<Carrito> {
  @override
  Carrito build() => const Carrito();

  /// Devuelve false si el carrito tiene cosas de otro local (la UI pregunta
  /// antes de vaciarlo).
  bool puedeAgregarDe(Comercio c) => state.vacio || state.comercio?.id == c.id;

  void agregar(Comercio comercio, ItemCarrito item) {
    final base = puedeAgregarDe(comercio) ? state.items : const <ItemCarrito>[];
    final existente = base.indexWhere((i) => i.clave == item.clave);
    final items = [...base];
    if (existente >= 0) {
      items[existente] = items[existente].conCantidad(items[existente].cantidad + item.cantidad);
    } else {
      items.add(item);
    }
    state = Carrito(comercio: comercio, items: items, nota: state.comercio?.id == comercio.id ? state.nota : null);
  }

  void cambiarCantidad(String clave, int cantidad) {
    final items = [
      for (final i in state.items)
        if (i.clave != clave) i else if (cantidad > 0) i.conCantidad(cantidad),
    ];
    state = items.isEmpty ? const Carrito() : Carrito(comercio: state.comercio, items: items, nota: state.nota);
  }

  void setNota(String nota) =>
      state = Carrito(comercio: state.comercio, items: state.items, nota: nota);

  void vaciar() => state = const Carrito();
}

final carritoProvider = NotifierProvider<CarritoNotifier, Carrito>(CarritoNotifier.new);

/// Cotizacion del envio para un local y una direccion.
final cotizacionEnvioProvider =
    FutureProvider.family<CotizacionPedido, ({String comercioId, String direccionId})>(
  (ref, k) => ref.watch(pedidosRepositoryProvider).cotizar(comercioId: k.comercioId, direccionId: k.direccionId),
);

/// La direccion que se usa por defecto.
final direccionElegidaProvider = NotifierProvider<DireccionElegida, String?>(DireccionElegida.new);

class DireccionElegida extends Notifier<String?> {
  @override
  String? build() {
    final lista = ref.watch(direccionesProvider).value;
    if (lista == null || lista.isEmpty) return null;
    return (lista.where((d) => d.predeterminada).firstOrNull ?? lista.first).id;
  }

  void elegir(String id) => state = id;
}

final direccionActualProvider = Provider<DireccionCliente?>((ref) {
  final id = ref.watch(direccionElegidaProvider);
  return ref.watch(direccionesProvider).value?.where((d) => d.id == id).firstOrNull;
});
