import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/models.dart';

/// A quién le llega una notificación.
enum SegmentoNotificacion {
  todos('todos', 'Todos', 'Clientes, locales y riders'),
  clientes('clientes', 'Clientes', 'Todas las personas que usan la app'),
  clientesPlus('clientes_plus', 'Con Plus', 'Los que hoy tienen MODO YA Plus'),
  clientesInactivos('clientes_inactivos', 'Dormidos', 'Sin pedir hace un tiempo'),
  comercios('comercios', 'Locales', 'Los locales aprobados'),
  riders('riders', 'Riders', 'Los riders aprobados');

  const SegmentoNotificacion(this.wire, this.rotulo, this.detalle);

  final String wire;
  final String rotulo;
  final String detalle;

  /// Solo este segmento usa la ventana de días.
  bool get usaDias => this == SegmentoNotificacion.clientesInactivos;

  static SegmentoNotificacion fromWire(String? v) => SegmentoNotificacion.values
      .firstWhere((e) => e.wire == v, orElse: () => SegmentoNotificacion.clientes);
}

/// Qué hace que la notificación salga sola.
enum DisparadorNotificacion {
  carritoAbandonado(
    'carrito_abandonado',
    'Carrito abandonado',
    'Al que armó un pedido y no llegó a pagarlo. Sale antes de que el pedido se '
        'cancele solo, y lo lleva derecho a pagarlo.',
  ),
  clienteInactivo(
    'cliente_inactivo',
    'Cliente dormido',
    'Al que hace rato no pide. Se le escribe una vez y no se le vuelve a '
        'insistir hasta pasado el período.',
  );

  const DisparadorNotificacion(this.wire, this.rotulo, this.detalle);

  final String wire;
  final String rotulo;
  final String detalle;

  static DisparadorNotificacion? fromWire(String? v) =>
      v == null ? null : DisparadorNotificacion.values.where((e) => e.wire == v).firstOrNull;
}

/// Qué abre la notificación cuando la tocan.
enum DestinoNotificacion {
  ninguno('ninguno', 'No abre nada'),
  inicio('inicio', 'El inicio'),
  misPedidos('mis_pedidos', 'Mis pedidos'),
  plus('plus', 'MODO YA Plus'),
  local('local', 'Un local');

  const DestinoNotificacion(this.wire, this.rotulo);

  final String wire;
  final String rotulo;

  static DestinoNotificacion fromWire(String? v) => DestinoNotificacion.values
      .firstWhere((e) => e.wire == v, orElse: () => DestinoNotificacion.ninguno);
}

/// Un mensaje que la administración le manda a un segmento.
class Notificacion {
  const Notificacion({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    this.segmento = SegmentoNotificacion.clientes,
    this.diasInactividad = 30,
    this.destino = DestinoNotificacion.ninguno,
    this.destinoId,
    this.enviada = false,
    this.enviadaEn,
    this.alcance = 0,
    this.leidas = 0,
    this.creadoEn,
    this.disparador,
    this.activa = true,
    this.minutosEspera = 10,
    this.repetirCadaDias = 30,
  });

  final String id;
  final String titulo;
  final String cuerpo;
  final SegmentoNotificacion segmento;
  final int diasInactividad;
  final DestinoNotificacion destino;
  final String? destinoId;

  final bool enviada;
  final DateTime? enviadaEn;

  /// Cuánta gente la recibió. Es una foto del momento del envío.
  final int alcance;

  /// Cuántos la abrieron.
  final int leidas;
  final DateTime? creadoEn;

  /// Nulo: la manda una persona. Si no, la manda el reloj cuando se cumple
  /// la condición.
  final DisparadorNotificacion? disparador;
  final bool activa;

  /// Carrito abandonado: cuánto se espera antes de escribirle.
  final int minutosEspera;

  /// Cliente dormido: cada cuánto, como mucho, se le vuelve a escribir.
  final int repetirCadaDias;

  bool get esAutomatica => disparador != null;

  factory Notificacion.fromRow(Map<String, dynamic> f) => Notificacion(
        id: Fila.texto(f, 'id'),
        titulo: Fila.texto(f, 'titulo'),
        cuerpo: Fila.texto(f, 'cuerpo'),
        segmento: SegmentoNotificacion.fromWire(f['segmento'] as String?),
        diasInactividad: Fila.entero(f, 'dias_inactividad', 30),
        destino: DestinoNotificacion.fromWire(f['destino'] as String?),
        destinoId: f['destino_id'] as String?,
        enviada: Fila.texto(f, 'estado') == 'enviada',
        enviadaEn: Fila.fechaOpcional(f, 'enviada_en'),
        alcance: Fila.entero(f, 'alcance'),
        leidas: Fila.entero(f, 'leidas'),
        creadoEn: Fila.fechaOpcional(f, 'creado_en'),
        disparador: DisparadorNotificacion.fromWire(f['disparador'] as String?),
        activa: Fila.booleano(f, 'activa', true),
        minutosEspera: Fila.entero(f, 'minutos_espera', 10),
        repetirCadaDias: Fila.entero(f, 'repetir_cada_dias', 30),
      );
}

/// Una notificación tal como le llegó a una persona.
class MiNotificacion {
  const MiNotificacion({
    required this.envioId,
    required this.titulo,
    required this.cuerpo,
    required this.destino,
    this.destinoId,
    this.pedidoId,
    this.leida = false,
    this.creadoEn,
  });

  final String envioId;
  final String titulo;
  final String cuerpo;
  final DestinoNotificacion destino;
  final String? destinoId;

  /// El pedido que motivó el aviso (carrito abandonado).
  final String? pedidoId;
  final bool leida;
  final DateTime? creadoEn;

  /// La ruta que abre, o null si no lleva a ningún lado.
  ///
  /// El pedido manda sobre el destino elegido: si el aviso salió porque quedó
  /// un pedido sin pagar, lo único que sirve es abrir el pago de *ese* pedido.
  String? get ruta => switch ((pedidoId, destino)) {
        (final String id, _) => '/cliente/pagar/$id',
        (_, DestinoNotificacion.ninguno) => null,
        (_, DestinoNotificacion.inicio) => '/cliente',
        (_, DestinoNotificacion.misPedidos) => '/cliente/pedidos',
        (_, DestinoNotificacion.plus) => '/cliente/plus',
        (_, DestinoNotificacion.local) => destinoId == null ? null : '/cliente/local/$destinoId',
      };

  factory MiNotificacion.fromRow(Map<String, dynamic> f) => MiNotificacion(
        envioId: Fila.texto(f, 'envio_id'),
        titulo: Fila.texto(f, 'titulo'),
        cuerpo: Fila.texto(f, 'cuerpo'),
        destino: DestinoNotificacion.fromWire(f['destino'] as String?),
        destinoId: f['destino_id'] as String?,
        pedidoId: f['pedido_id'] as String?,
        leida: f['leida_en'] != null,
        creadoEn: Fila.fechaOpcional(f, 'creado_en'),
      );
}

/// Notificaciones: la administración escribe y elige a quién le llega.
///
/// Por ahora la notificación vive adentro de la app (la campanita del cliente).
/// El push al celular se suma después sin tocar estas tablas: cada destinatario
/// ya tiene su fila con a quién mandársela.
class NotificacionesRepository {
  const NotificacionesRepository();

  SupabaseClient get _db => Backend.db;

  /// Todas las notificaciones, para el panel. Las últimas primero.
  Stream<List<Notificacion>> watchTodas() => enVivo(
        canal: 'notificaciones',
        tablas: const ['notificaciones', 'notificacion_envios'],
        leer: () async => (await _db
                .from('v_notificaciones_admin')
                .select()
                .order('creado_en', ascending: false))
            .map(Notificacion.fromRow)
            .toList(),
      );

  /// La bandeja de quien está usando la app.
  Stream<List<MiNotificacion>> watchMias() => enVivo(
        canal: 'mis-notificaciones',
        tablas: const ['notificacion_envios'],
        leer: () async => (await _db
                .from('v_notificaciones')
                .select()
                .order('creado_en', ascending: false)
                .limit(50))
            .map(MiNotificacion.fromRow)
            .toList(),
      );

  /// A cuánta gente le llegaría hoy. Se muestra antes de mandar.
  Future<int> alcanceDe(SegmentoNotificacion segmento, {int dias = 30}) =>
      intentar(() async => (await _db.rpc('alcance_de', params: {
            'p_segmento': segmento.wire,
            'p_dias': dias,
          })) as int);

  /// Crea o edita un borrador. Una ya enviada no se toca.
  Future<String> guardar({
    required String titulo,
    required String cuerpo,
    String? id,
    SegmentoNotificacion segmento = SegmentoNotificacion.clientes,
    int diasInactividad = 30,
    DestinoNotificacion destino = DestinoNotificacion.ninguno,
    String? destinoId,
  }) =>
      intentar(() async {
        final datos = {
          'titulo': titulo.trim(),
          'cuerpo': cuerpo.trim(),
          'segmento': segmento.wire,
          'dias_inactividad': diasInactividad,
          'destino': destino.wire,
          'destino_id': destino == DestinoNotificacion.local ? destinoId : null,
        };

        if (id == null) {
          final f = await _db.from('notificaciones').insert(datos).select('id').single();
          return f['id'] as String;
        }
        await _db.from('notificaciones').update(datos).eq('id', id);
        return id;
      });

  /// Crea o edita la automática de un disparador. Hay una sola por disparador.
  ///
  /// No se "manda": queda prendida y el reloj la dispara cuando se cumple la
  /// condición, todas las veces que haga falta.
  Future<void> guardarAutomatica({
    required DisparadorNotificacion disparador,
    required String titulo,
    required String cuerpo,
    String? id,
    bool activa = true,
    int minutosEspera = 10,
    int diasInactividad = 30,
    int repetirCadaDias = 30,
  }) =>
      intentar(() async {
        final datos = {
          'titulo': titulo.trim(),
          'cuerpo': cuerpo.trim(),
          'disparador': disparador.wire,
          'activa': activa,
          'minutos_espera': minutosEspera,
          'dias_inactividad': diasInactividad,
          'repetir_cada_dias': repetirCadaDias,
          'segmento': disparador == DisparadorNotificacion.clienteInactivo
              ? SegmentoNotificacion.clientesInactivos.wire
              : SegmentoNotificacion.clientes.wire,
        };
        if (id == null) {
          await _db.from('notificaciones').insert(datos);
        } else {
          await _db.from('notificaciones').update(datos).eq('id', id);
        }
      });

  Future<void> prender(String id, {required bool activa}) =>
      intentar(() => _db.from('notificaciones').update({'activa': activa}).eq('id', id));

  /// La manda. Devuelve a cuánta gente le llegó.
  Future<int> enviar(String id) => intentar(() async {
        final f = await _db.rpc('enviar_notificacion', params: {'p_notificacion': id});
        return Fila.entero(Map<String, dynamic>.from(f as Map), 'alcance');
      });

  Future<void> borrar(String id) =>
      intentar(() => _db.from('notificaciones').delete().eq('id', id));

  Future<void> marcarLeida(String envioId) =>
      intentar(() => _db.rpc('marcar_notificacion_leida', params: {'p_envio': envioId}));
}
