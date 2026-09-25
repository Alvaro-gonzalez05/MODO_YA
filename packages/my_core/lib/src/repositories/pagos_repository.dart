import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend.dart';
import '../config/entorno.dart';
import '../models/models.dart';

/// Una tarjeta que el cliente dejó guardada. El número vive en Mercado Pago:
/// acá solo está lo que hace falta para mostrarla y para cobrar.
class TarjetaGuardada {
  const TarjetaGuardada({
    required this.id,
    required this.mpCardId,
    required this.marca,
    required this.ultimos4,
    required this.venceMes,
    required this.venceAnio,
    this.titular,
    this.predeterminada = false,
  });

  final String id;
  final String mpCardId;

  /// "visa", "master"... (como la llama Mercado Pago).
  final String marca;
  final String ultimos4;
  final int venceMes;
  final int venceAnio;
  final String? titular;
  final bool predeterminada;

  String get vencimiento => '${venceMes.toString().padLeft(2, '0')}/${venceAnio.toString().substring(2)}';

  factory TarjetaGuardada.fromRow(Map<String, dynamic> f) => TarjetaGuardada(
        id: Fila.texto(f, 'id'),
        mpCardId: Fila.texto(f, 'mp_card_id'),
        marca: Fila.texto(f, 'marca'),
        ultimos4: Fila.texto(f, 'ultimos4'),
        venceMes: Fila.entero(f, 'vence_mes'),
        venceAnio: Fila.entero(f, 'vence_anio'),
        titular: Fila.textoOpcional(f, 'titular'),
        predeterminada: Fila.booleano(f, 'predeterminada'),
      );
}

/// MODO YA Plus del cliente: hasta cuándo lo tiene y cuánto sale renovarlo.
class EstadoPlus {
  const EstadoPlus({
    required this.activo,
    required this.precio,
    this.hasta,
    this.renovar = false,
    this.fallos = 0,
    this.ultimoError,
  });

  final bool activo;
  final int precio;
  final DateTime? hasta;

  /// Si al vencerse se le vuelve a cobrar con la tarjeta guardada.
  final bool renovar;

  /// Cuántas veces rebotó la tarjeta al intentar renovar. A las 3 se deja de
  /// intentar y hay que renovar a mano.
  final int fallos;
  final String? ultimoError;

  bool get seRindio => renovar && fallos >= 3;

  factory EstadoPlus.sinDatos(int precio) => EstadoPlus(activo: false, precio: precio);
}

/// Resultado de intentar cobrar un pedido.
class ResultadoPago {
  const ResultadoPago({required this.aprobado, this.detalle, this.simulado = false});

  final bool aprobado;

  /// Por qué no salió, en castellano ("La tarjeta no tiene fondos suficientes").
  final String? detalle;

  /// El cobro no fue real: todavía no están las credenciales de Mercado Pago.
  final bool simulado;
}

/// Cobros con tarjeta dentro de la app.
///
/// Los datos de la tarjeta NO pasan por nuestro servidor: se los manda directo
/// a Mercado Pago, que devuelve un token de un solo uso. Con ese token cobra la
/// Edge Function `pagar-pedido`, que es la única que tiene la clave secreta.
class PagosRepository {
  const PagosRepository();

  SupabaseClient get _db => Backend.db;

  /// Sin clave pública configurada se trabaja simulado (para mostrar la
  /// pantalla antes de tener la cuenta de Mercado Pago).
  bool get simulado => Entorno.mpPublicKey.isEmpty;

  /// Manda la tarjeta a Mercado Pago y devuelve el token de un solo uso.
  Future<String> _tokenizar({
    required String numero,
    required String titular,
    required int mes,
    required int anio,
    required String codigo,
    String? documento,
  }) async {
    if (simulado) return 'token-simulado-${DateTime.now().millisecondsSinceEpoch}';

    final r = await http.post(
      Uri.parse('https://api.mercadopago.com/v1/card_tokens?public_key=${Entorno.mpPublicKey}'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'card_number': numero.replaceAll(RegExp(r'\D'), ''),
        'expiration_month': mes,
        'expiration_year': anio,
        'security_code': codigo,
        'cardholder': {
          'name': titular,
          if (documento != null && documento.isNotEmpty)
            'identification': {'type': 'DNI', 'number': documento},
        },
      }),
    );
    final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300 || cuerpo['id'] == null) {
      throw ErrorModoYa(_errorDeTokenizacion(cuerpo));
    }
    return cuerpo['id'] as String;
  }

  String _errorDeTokenizacion(Map<String, dynamic> cuerpo) {
    final causa = (cuerpo['cause'] as List?)?.firstOrNull as Map?;
    return switch (causa?['code']?.toString()) {
      '205' => 'Escribí el número de la tarjeta.',
      '208' || '209' => 'Revisá la fecha de vencimiento.',
      '212' || '213' || '214' => 'Revisá el documento del titular.',
      '220' || '221' => 'Escribí el nombre del titular como figura en la tarjeta.',
      '224' || 'E301' => 'Revisá el código de seguridad.',
      '316' => 'El nombre del titular no es válido.',
      _ => 'Revisá los datos de la tarjeta.',
    };
  }

  /// Cobra el pedido con una tarjeta nueva. Si [guardar], queda guardada para
  /// la próxima vez.
  Future<ResultadoPago> pagarConTarjetaNueva({
    required String pedidoId,
    required String numero,
    required String titular,
    required int mes,
    required int anio,
    required String codigo,
    String? documento,
    int cuotas = 1,
    bool guardar = true,
    required String marca,
  }) async {
    final token = await _tokenizar(
      numero: numero, titular: titular, mes: mes, anio: anio, codigo: codigo, documento: documento,
    );
    final limpio = numero.replaceAll(RegExp(r'\D'), '');
    return _cobrar({
      'pedido_id': pedidoId,
      'token': token,
      'cuotas': cuotas,
      'metodo_pago_id': marca,
      'guardar': guardar,
      'marca': marca,
      'ultimos4': limpio.length >= 4 ? limpio.substring(limpio.length - 4) : limpio,
      'vence_mes': mes,
      'vence_anio': anio,
      'titular': titular,
    });
  }

  /// Cobra con una tarjeta guardada. Mercado Pago pide igual el código de
  /// seguridad: es su regla, no se puede saltear.
  Future<ResultadoPago> pagarConTarjetaGuardada({
    required String pedidoId,
    required TarjetaGuardada tarjeta,
    required String codigo,
    int cuotas = 1,
  }) async {
    final token = simulado
        ? 'token-simulado-guardada'
        : await _tokenDeTarjetaGuardada(tarjeta.mpCardId, codigo);
    return _cobrar({
      'pedido_id': pedidoId,
      'token': token,
      'card_id': tarjeta.mpCardId,
      'cuotas': cuotas,
      'metodo_pago_id': tarjeta.marca,
      'titular': tarjeta.titular,
    });
  }

  Future<String> _tokenDeTarjetaGuardada(String cardId, String codigo) async {
    final r = await http.post(
      Uri.parse('https://api.mercadopago.com/v1/card_tokens?public_key=${Entorno.mpPublicKey}'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'card_id': cardId, 'security_code': codigo}),
    );
    final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 300 || cuerpo['id'] == null) throw ErrorModoYa(_errorDeTokenizacion(cuerpo));
    return cuerpo['id'] as String;
  }

  Future<ResultadoPago> _cobrar(Map<String, dynamic> cuerpo) => intentar(() async {
        final r = await _db.functions.invoke('pagar-pedido', body: cuerpo);
        final d = Map<String, dynamic>.from(r.data as Map);
        if (d['error'] != null) throw ErrorModoYa(d['error'] as String);
        return ResultadoPago(
          aprobado: d['aprobado'] == true,
          detalle: d['detalle'] as String?,
          simulado: d['simulado'] == true,
        );
      });

  /// Estado de MODO YA Plus del cliente que está usando la app.
  Stream<EstadoPlus> watchPlus() => enVivo(
        canal: 'plus',
        tablas: const ['suscripciones_plus', 'tarifarios'],
        leer: () async {
          final precio = await _db.rpc('precio_plus');
          final f = await _db
              .from('suscripciones_plus')
              .select()
              .order('hasta', ascending: false)
              .limit(1)
              .maybeSingle();
          if (f == null) return EstadoPlus.sinDatos(Fila.entero({'p': precio}, 'p'));
          final hasta = Fila.fecha(f, 'hasta');
          return EstadoPlus(
            activo: !hasta.isBefore(DateTime.now().subtract(const Duration(days: 1))),
            precio: Fila.entero({'p': precio}, 'p'),
            hasta: hasta,
            renovar: Fila.booleano(f, 'renovar'),
            fallos: Fila.entero(f, 'intentos_fallidos'),
            ultimoError: Fila.textoOpcional(f, 'ultimo_error'),
          );
        },
      );

  /// Prende o corta la renovación automática. Al prenderla se le vuelve a dar
  /// una chance a la tarjeta que venía rebotando.
  Future<void> renovarPlusAutomaticamente(bool renovar) => intentar(
        () => _db.rpc('cortar_renovacion_plus', params: {'p_renovar': renovar}),
      );

  /// Paga un mes de Plus con una tarjeta nueva.
  Future<ResultadoPago> suscribirsePlus({
    required String numero,
    required String titular,
    required int mes,
    required int anio,
    required String codigo,
    String? documento,
    required String marca,
  }) async {
    final token = await _tokenizar(
      numero: numero, titular: titular, mes: mes, anio: anio, codigo: codigo, documento: documento,
    );
    return _cobrar({
      'accion': 'plus',
      'token': token,
      'metodo_pago_id': marca,
      'titular': titular,
    });
  }

  /// Paga un mes de Plus con una tarjeta ya guardada.
  Future<ResultadoPago> suscribirsePlusConTarjeta(TarjetaGuardada t, String codigo) async {
    final token = simulado ? 'token-simulado-plus' : await _tokenDeTarjetaGuardada(t.mpCardId, codigo);
    return _cobrar({
      'accion': 'plus',
      'token': token,
      'card_id': t.mpCardId,
      'metodo_pago_id': t.marca,
      'titular': t.titular,
    });
  }

  Stream<List<TarjetaGuardada>> watchTarjetas() => enVivo(
        canal: 'tarjetas-guardadas',
        tablas: const ['tarjetas_guardadas'],
        leer: () async => (await _db.from('tarjetas_guardadas').select().order('creado_en'))
            .map(TarjetaGuardada.fromRow)
            .toList(),
      );

  Future<void> borrarTarjeta(String id) => intentar(() async {
        final r = await _db.functions.invoke('pagar-pedido', body: {
          'accion': 'borrar_tarjeta',
          'tarjeta_id': id,
        });
        final d = Map<String, dynamic>.from(r.data as Map);
        if (d['error'] != null) throw ErrorModoYa(d['error'] as String);
      });
}
