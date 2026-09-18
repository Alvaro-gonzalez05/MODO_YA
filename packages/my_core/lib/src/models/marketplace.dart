import 'estados.dart';
import 'models.dart';

/// Categoria del listado general (los chips del home del cliente).
class Rubro {
  const Rubro({required this.id, required this.nombre, this.icono, this.orden = 0});

  final String id;
  final String nombre;

  /// Nombre de un icono de Material Symbols ("local_pizza").
  final String? icono;
  final int orden;

  factory Rubro.fromRow(Map<String, dynamic> f) => Rubro(
        id: Fila.texto(f, 'id'),
        nombre: Fila.texto(f, 'nombre'),
        icono: Fila.textoOpcional(f, 'icono'),
        orden: Fila.entero(f, 'orden'),
      );
}

/// Cartel del inicio del cliente (el banner negro "El mejor sabor, en tu
/// casa"). Los escribe la administracion desde el panel.
class Cartel {
  const Cartel({
    required this.id,
    required this.titulo,
    this.subtitulo = '',
    this.activo = true,
    this.orden = 0,
  });

  final String id;

  /// Puede tener un salto de linea para cortar el titulo donde se quiera.
  final String titulo;
  final String subtitulo;
  final bool activo;
  final int orden;

  factory Cartel.fromRow(Map<String, dynamic> f) => Cartel(
        id: Fila.texto(f, 'id'),
        titulo: Fila.texto(f, 'titulo'),
        subtitulo: Fila.texto(f, 'subtitulo'),
        activo: Fila.booleano(f, 'activo', true),
        orden: Fila.entero(f, 'orden'),
      );

  Cartel copyWith({String? titulo, String? subtitulo, bool? activo, int? orden}) => Cartel(
        id: id,
        titulo: titulo ?? this.titulo,
        subtitulo: subtitulo ?? this.subtitulo,
        activo: activo ?? this.activo,
        orden: orden ?? this.orden,
      );
}

/// Un turno de atencion. Si [cierra] es menor que [abre], cruza la medianoche.
class Horario {
  const Horario({required this.dia, required this.abre, required this.cierra});

  /// 0 = domingo ... 6 = sabado.
  final int dia;

  /// "HH:mm"
  final String abre;
  final String cierra;

  bool get cruzaMedianoche => cierra.compareTo(abre) < 0;

  static const nombresDias = [
    'Domingo', 'Lunes', 'Martes', 'Miercoles', 'Jueves', 'Viernes', 'Sabado',
  ];

  factory Horario.fromRow(Map<String, dynamic> f) => Horario(
        dia: Fila.entero(f, 'dia'),
        abre: Fila.texto(f, 'abre').substring(0, 5),
        cierra: Fila.texto(f, 'cierra').substring(0, 5),
      );

  Map<String, dynamic> toJson() => {'dia': dia, 'abre': abre, 'cierra': cierra};
}

/// Seccion del menu de un local ("Pizzas", "Bebidas").
class SeccionMenu {
  const SeccionMenu({
    required this.id,
    required this.comercioId,
    required this.nombre,
    this.orden = 0,
    this.activa = true,
  });

  final String id;
  final String comercioId;
  final String nombre;
  final int orden;
  final bool activa;

  factory SeccionMenu.fromRow(Map<String, dynamic> f) => SeccionMenu(
        id: Fila.texto(f, 'id'),
        comercioId: Fila.texto(f, 'comercio_id'),
        nombre: Fila.texto(f, 'nombre'),
        orden: Fila.entero(f, 'orden'),
        activa: Fila.booleano(f, 'activa', true),
      );
}

class OpcionItem {
  const OpcionItem({
    required this.nombre,
    this.id,
    this.precioExtra = 0,
    this.disponible = true,
    this.orden = 0,
  });

  /// Null mientras no se guardo.
  final String? id;
  final String nombre;
  final int precioExtra;
  final bool disponible;
  final int orden;

  factory OpcionItem.fromRow(Map<String, dynamic> f) => OpcionItem(
        id: Fila.texto(f, 'id'),
        nombre: Fila.texto(f, 'nombre'),
        precioExtra: Fila.entero(f, 'precio_extra'),
        disponible: Fila.booleano(f, 'disponible', true),
        orden: Fila.entero(f, 'orden'),
      );
}

/// Grupo de personalizacion de un producto: "Tamano", "Agregados".
class OpcionProducto {
  const OpcionProducto({
    required this.nombre,
    required this.items,
    this.id,
    this.tipo = TipoOpcion.unica,
    this.obligatoria = false,
    this.maxSelecciones,
    this.orden = 0,
  });

  final String? id;
  final String nombre;
  final TipoOpcion tipo;
  final bool obligatoria;
  final int? maxSelecciones;
  final int orden;
  final List<OpcionItem> items;

  factory OpcionProducto.fromRow(Map<String, dynamic> f) {
    final items = ((f['opcion_items'] as List?) ?? const [])
        .map((e) => OpcionItem.fromRow(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    return OpcionProducto(
      id: Fila.texto(f, 'id'),
      nombre: Fila.texto(f, 'nombre'),
      tipo: TipoOpcion.fromWire(f['tipo'] as String?),
      obligatoria: Fila.booleano(f, 'obligatoria'),
      maxSelecciones: Fila.enteroOpcional(f, 'max_selecciones'),
      orden: Fila.entero(f, 'orden'),
      items: items,
    );
  }
}

class Producto {
  const Producto({
    required this.id,
    required this.comercioId,
    required this.nombre,
    required this.precio,
    this.seccionId,
    this.descripcion,
    this.fotoUrl,
    this.disponible = true,
    this.orden = 0,
    this.opciones = const [],
  });

  final String id;
  final String comercioId;
  final String? seccionId;
  final String nombre;
  final String? descripcion;
  final int precio;
  final String? fotoUrl;
  final bool disponible;
  final int orden;
  final List<OpcionProducto> opciones;

  bool get tienePersonalizacion => opciones.isNotEmpty;

  factory Producto.fromRow(Map<String, dynamic> f) {
    final opciones = ((f['opciones_producto'] as List?) ?? const [])
        .map((e) => OpcionProducto.fromRow(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.orden.compareTo(b.orden));
    return Producto(
      id: Fila.texto(f, 'id'),
      comercioId: Fila.texto(f, 'comercio_id'),
      seccionId: Fila.textoOpcional(f, 'seccion_id'),
      nombre: Fila.texto(f, 'nombre'),
      descripcion: Fila.textoOpcional(f, 'descripcion'),
      precio: Fila.entero(f, 'precio'),
      fotoUrl: Fila.textoOpcional(f, 'foto_url'),
      disponible: Fila.booleano(f, 'disponible', true),
      orden: Fila.entero(f, 'orden'),
      opciones: opciones,
    );
  }
}

/// El menu completo de un local, listo para dibujar.
class Menu {
  const Menu({required this.secciones, required this.productos});

  final List<SeccionMenu> secciones;
  final List<Producto> productos;

  List<Producto> deSeccion(String? seccionId) =>
      productos.where((p) => p.seccionId == seccionId).toList();

  /// Productos que quedaron sin seccion (por ejemplo, si se borro la seccion).
  List<Producto> get sinSeccion => productos
      .where((p) => p.seccionId == null || secciones.every((s) => s.id != p.seccionId))
      .toList();
}

/// Direccion guardada por un cliente. Se lee de `v_direcciones`.
class DireccionCliente {
  const DireccionCliente({
    required this.id,
    required this.alias,
    required this.calle,
    required this.lat,
    required this.lng,
    this.referencia,
    this.predeterminada = false,
  });

  final String id;
  final String alias;
  final String calle;
  final String? referencia;
  final double lat;
  final double lng;
  final bool predeterminada;

  factory DireccionCliente.fromRow(Map<String, dynamic> f) => DireccionCliente(
        id: Fila.texto(f, 'id'),
        alias: Fila.texto(f, 'alias'),
        calle: Fila.texto(f, 'calle'),
        referencia: Fila.textoOpcional(f, 'referencia'),
        lat: Fila.decimal(f, 'lat'),
        lng: Fila.decimal(f, 'lng'),
        predeterminada: Fila.booleano(f, 'predeterminada'),
      );
}

class PedidoItem {
  const PedidoItem({
    required this.nombreProducto,
    required this.cantidad,
    required this.precioUnitario,
    required this.subtotal,
    this.opciones = const [],
    this.nota,
  });

  final String nombreProducto;
  final int cantidad;
  final int precioUnitario;
  final int subtotal;

  /// "Tamano: Grande", "Agregados: Extra queso".
  final List<String> opciones;
  final String? nota;

  factory PedidoItem.fromRow(Map<String, dynamic> f) => PedidoItem(
        nombreProducto: Fila.texto(f, 'nombre_producto'),
        cantidad: Fila.entero(f, 'cantidad', 1),
        precioUnitario: Fila.entero(f, 'precio_unitario'),
        subtotal: Fila.entero(f, 'subtotal'),
        nota: Fila.textoOpcional(f, 'nota'),
        opciones: ((f['pedido_item_opciones'] as List?) ?? const [])
            .map((e) {
              final o = Map<String, dynamic>.from(e as Map);
              return '${Fila.texto(o, 'nombre_opcion')}: ${Fila.texto(o, 'nombre_item')}';
            })
            .toList(),
      );
}

/// Pedido del marketplace. Se lee de `v_pedidos`.
class Pedido {
  const Pedido({
    required this.id,
    required this.codigo,
    required this.estado,
    required this.comercioId,
    required this.comercioNombre,
    required this.entrega,
    required this.subtotal,
    required this.costoEnvio,
    required this.total,
    required this.creadoEn,
    this.clienteNombre,
    this.clienteTelefono,
    this.comercioLogoUrl,
    this.envioId,
    this.minutosEstimados,
    this.nota,
    this.motivoRechazo,
    this.items = const [],
  });

  final String id;
  final String codigo;
  final EstadoPedido estado;
  final String? clienteNombre;
  final String? clienteTelefono;
  final String comercioId;
  final String comercioNombre;
  final String? comercioLogoUrl;
  final Direccion entrega;
  final int subtotal;
  final int costoEnvio;
  final int total;
  final String? envioId;
  final int? minutosEstimados;
  final String? nota;
  final String? motivoRechazo;
  final DateTime creadoEn;
  final List<PedidoItem> items;

  int get cantidadProductos => items.fold(0, (s, i) => s + i.cantidad);

  factory Pedido.fromRow(Map<String, dynamic> f, {List<PedidoItem> items = const []}) => Pedido(
        id: Fila.texto(f, 'id'),
        codigo: Fila.texto(f, 'codigo'),
        estado: EstadoPedido.fromWire(f['estado'] as String?),
        clienteNombre: Fila.textoOpcional(f, 'cliente_nombre'),
        clienteTelefono: Fila.textoOpcional(f, 'cliente_telefono'),
        comercioId: Fila.texto(f, 'comercio_id'),
        comercioNombre: Fila.texto(f, 'comercio_nombre'),
        comercioLogoUrl: Fila.textoOpcional(f, 'comercio_logo_url'),
        entrega: Direccion(
          calle: Fila.texto(f, 'entrega_calle'),
          referencia: Fila.textoOpcional(f, 'entrega_referencia'),
          lat: Fila.decimalOpcional(f, 'entrega_lat'),
          lng: Fila.decimalOpcional(f, 'entrega_lng'),
        ),
        subtotal: Fila.entero(f, 'subtotal'),
        costoEnvio: Fila.entero(f, 'costo_envio'),
        total: Fila.entero(f, 'total'),
        envioId: Fila.textoOpcional(f, 'envio_id'),
        minutosEstimados: Fila.enteroOpcional(f, 'envio_minutos_estimados'),
        nota: Fila.textoOpcional(f, 'nota_cliente'),
        motivoRechazo: Fila.textoOpcional(f, 'motivo_rechazo'),
        creadoEn: Fila.fecha(f, 'creado_en'),
        items: items,
      );

  Pedido conItems(List<PedidoItem> nuevos) => Pedido(
        id: id,
        codigo: codigo,
        estado: estado,
        clienteNombre: clienteNombre,
        clienteTelefono: clienteTelefono,
        comercioId: comercioId,
        comercioNombre: comercioNombre,
        comercioLogoUrl: comercioLogoUrl,
        entrega: entrega,
        subtotal: subtotal,
        costoEnvio: costoEnvio,
        total: total,
        envioId: envioId,
        minutosEstimados: minutosEstimados,
        nota: nota,
        motivoRechazo: motivoRechazo,
        creadoEn: creadoEn,
        items: nuevos,
      );
}

/// Lo que el cliente ve del envio de su pedido (via seguimiento_de_mi_pedido).
class SeguimientoPedido {
  const SeguimientoPedido({
    this.estadoEnvio,
    this.repartidorNombre,
    this.vehiculo,
    this.codigoEntrega,
    this.minutosEstimados,
    this.riderLat,
    this.riderLng,
  });

  final EstadoEnvio? estadoEnvio;
  final String? repartidorNombre;
  final Vehiculo? vehiculo;
  final String? codigoEntrega;
  final int? minutosEstimados;
  final double? riderLat;
  final double? riderLng;

  factory SeguimientoPedido.fromJson(Map<String, dynamic> f) => SeguimientoPedido(
        estadoEnvio: f['estado_envio'] == null ? null : EstadoEnvio.fromWire(f['estado_envio'] as String),
        repartidorNombre: Fila.textoOpcional(f, 'repartidor_nombre'),
        vehiculo: f['vehiculo'] == null ? null : Vehiculo.fromWire(f['vehiculo'] as String),
        codigoEntrega: Fila.textoOpcional(f, 'codigo_entrega'),
        minutosEstimados: Fila.enteroOpcional(f, 'minutos_estimados'),
        riderLat: Fila.decimalOpcional(f, 'rider_lat'),
        riderLng: Fila.decimalOpcional(f, 'rider_lng'),
      );
}

/// Cotizacion del envio de un pedido, antes de confirmarlo.
class CotizacionPedido {
  const CotizacionPedido({
    required this.distanciaKm,
    required this.costoEnvio,
    required this.minutosEstimados,
  });

  final double distanciaKm;
  final int costoEnvio;
  final int minutosEstimados;

  factory CotizacionPedido.fromJson(Map<String, dynamic> f) => CotizacionPedido(
        distanciaKm: Fila.decimal(f, 'distancia_km'),
        costoEnvio: Fila.entero(f, 'costo_envio'),
        minutosEstimados: Fila.entero(f, 'minutos_estimados'),
      );
}

/// Un renglon del carrito, antes de pedir.
///
/// El precio que se muestra aca es orientativo: el que vale lo calcula
/// crear_pedido() en el servidor leyendo el catalogo.
class ItemCarrito {
  const ItemCarrito({
    required this.producto,
    required this.cantidad,
    this.elegidas = const [],
    this.nota,
  });

  final Producto producto;
  final int cantidad;
  final List<OpcionItem> elegidas;
  final String? nota;

  int get precioUnitario => producto.precio + elegidas.fold(0, (s, o) => s + o.precioExtra);
  int get subtotal => precioUnitario * cantidad;

  /// Dos renglones con el mismo producto, las mismas opciones y la misma nota
  /// son el mismo renglon: se suman cantidades en vez de duplicar.
  String get clave {
    final ids = elegidas.map((e) => e.id ?? e.nombre).toList()..sort();
    return '${producto.id}|${ids.join(',')}|${nota ?? ''}';
  }

  ItemCarrito conCantidad(int c) =>
      ItemCarrito(producto: producto, cantidad: c, elegidas: elegidas, nota: nota);

  Map<String, dynamic> toJson() => {
        'producto_id': producto.id,
        'cantidad': cantidad,
        if (nota != null && nota!.trim().isNotEmpty) 'nota': nota!.trim(),
        'opciones': elegidas.map((e) => e.id).whereType<String>().toList(),
      };
}

/// Resultado del alta de un local o rider por la administracion.
class AltaCuenta {
  const AltaCuenta({required this.email, this.passwordTemporal});

  final String email;

  /// Se muestra una sola vez: no queda guardada en ningun lado.
  final String? passwordTemporal;
}
