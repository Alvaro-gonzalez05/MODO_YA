import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../models/estados.dart';
import '../models/marketplace.dart';

/// Pedidos del marketplace.
class PedidosRepository {
  const PedidosRepository();

  SupabaseClient get _db => Backend.db;

  List<Pedido> _lista(List<Map<String, dynamic>> f) => f.map((e) => Pedido.fromRow(e)).toList();

  /// Pedidos del cliente logueado (RLS filtra los suyos).
  Stream<List<Pedido>> watchDelCliente() => enVivo(
        canal: 'pedidos-cliente',
        tablas: const ['pedidos'],
        leer: () async => _lista(await _db
            .from('v_pedidos')
            .select()
            .order('creado_en', ascending: false)
            .limit(50)),
      );

  /// Pedidos de un local. Los que esperan pago no se muestran: el local no
  /// tiene que preparar algo que todavia no se cobro.
  Stream<List<Pedido>> watchDelComercio(String comercioId) => enVivo(
        canal: 'pedidos-local',
        tablas: const ['pedidos'],
        leer: () async {
          final pedidos = _lista(await _db
              .from('v_pedidos')
              .select()
              .eq('comercio_id', comercioId)
              .neq('estado', 'pendiente_pago')
              .order('creado_en', ascending: false)
              .limit(100));
          return _conItems(pedidos);
        },
      );

  /// Pedidos que esperan que la administracion registre el pago.
  Stream<List<Pedido>> watchPendientesDePago() => enVivo(
        canal: 'pedidos-pago',
        tablas: const ['pedidos'],
        leer: () async => _conItems(_lista(await _db
            .from('v_pedidos')
            .select()
            .eq('estado', 'pendiente_pago')
            .order('creado_en', ascending: true))),
      );

  Stream<Pedido?> watchPorId(String id) => enVivo(
        canal: 'pedido-$id',
        // Tambien envios: cuando avanza el envio, cambia lo que ve el cliente.
        tablas: const ['pedidos', 'envios'],
        leer: () async {
          final f = await _db.from('v_pedidos').select().eq('id', id).maybeSingle();
          if (f == null) return null;
          return (await _conItems([Pedido.fromRow(f)])).first;
        },
      );

  Future<List<Pedido>> _conItems(List<Pedido> pedidos) async {
    if (pedidos.isEmpty) return pedidos;
    final filas = await _db
        .from('pedido_items')
        .select('*, pedido_item_opciones(*)')
        .inFilter('pedido_id', pedidos.map((p) => p.id).toList());
    final porPedido = <String, List<PedidoItem>>{};
    for (final f in filas) {
      porPedido.putIfAbsent(f['pedido_id'] as String, () => []).add(PedidoItem.fromRow(f));
    }
    return [for (final p in pedidos) p.conItems(porPedido[p.id] ?? const [])];
  }

  Future<SeguimientoPedido?> seguimiento(String pedidoId) => intentar(() async {
        final r = await _db.rpc('seguimiento_de_mi_pedido', params: {'p_pedido': pedidoId});
        return r == null ? null : SeguimientoPedido.fromJson(Map<String, dynamic>.from(r as Map));
      });

  Future<CotizacionPedido> cotizar({required String comercioId, required String direccionId}) =>
      intentar(() async {
        final r = await _db.rpc('cotizar_para_cliente', params: {
          'p_comercio': comercioId,
          'p_direccion': direccionId,
        });
        return CotizacionPedido.fromJson(Map<String, dynamic>.from(r as Map));
      });

  /// Crea el pedido. Los precios los calcula el servidor desde el catalogo.
  Future<String> crear({
    required String comercioId,
    required String direccionId,
    required List<ItemCarrito> items,
    String? nota,
  }) =>
      intentar(() async {
        final r = await _db.rpc('crear_pedido', params: {
          'p_comercio_id': comercioId,
          'p_direccion_id': direccionId,
          'p_items': items.map((i) => i.toJson()).toList(),
          'p_nota': (nota ?? '').trim().isEmpty ? null : nota!.trim(),
        });
        return (r as Map)['id'] as String;
      });

  Future<void> aceptar(String id) => intentar(() => _db.rpc('aceptar_pedido', params: {'p_pedido': id}));

  Future<void> rechazar(String id, String motivo) =>
      intentar(() => _db.rpc('rechazar_pedido', params: {'p_pedido': id, 'p_motivo': motivo}));

  Future<void> avanzar(String id, EstadoPedido nuevo) =>
      intentar(() => _db.rpc('avanzar_pedido', params: {'p_pedido': id, 'p_nuevo': nuevo.wire}));

  Future<void> cancelar(String id, String motivo) =>
      intentar(() => _db.rpc('cancelar_pedido', params: {'p_pedido': id, 'p_motivo': motivo}));

  /// Solo administracion. Mientras no haya pasarela, es como se confirma un pago.
  Future<void> marcarPagado(String id, MetodoPago metodo) => intentar(
        () => _db.rpc('marcar_pedido_pagado', params: {'p_pedido': id, 'p_metodo': metodo.wire}),
      );
}
