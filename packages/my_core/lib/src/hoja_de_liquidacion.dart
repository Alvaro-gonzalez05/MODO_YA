/// Una liquidación lista para leer, armada una sola vez para los tres roles.
///
/// La administración, el rider y el local miran el mismo documento. Lo que
/// cambia es de dónde salen los datos (la administración elige a quién mirar,
/// los otros dos se miran a sí mismos); el armado —qué renglones hay, qué se
/// suma, qué se resta y cómo se escribe cada número— es este archivo y nada
/// más. Si cada pantalla armara su hoja, un día el rider y la administración
/// iban a estar discutiendo dos números distintos.
///
/// Los importes se guardan ya formateados: la hoja se dibuja en pantalla
/// (`MyHojaDeLiquidacion`) y se escribe en papel (`guardarHojaEnPdf`) desde
/// esta misma estructura, así que no hay dos formateos que puedan diferir.
library;

import 'formato.dart';
import 'repositories/liquidaciones_repository.dart';

/// Los períodos que se pueden mirar.
///
/// Una liquidación no tiene período propio hasta que se cierra: hasta entonces
/// es "lo que hay entre dos fechas". Estas cuatro opciones son las que se usan
/// de verdad, y viven acá para que la administración, el rider y el local
/// cuenten las semanas igual. La semana arranca el lunes.
enum RangoDePeriodo {
  estaSemana('Esta semana'),
  semanaPasada('Semana pasada'),
  esteMes('Este mes'),
  mesPasado('Mes pasado');

  const RangoDePeriodo(this.rotulo);

  final String rotulo;

  (DateTime desde, DateTime hasta) get periodo {
    final hoy = DateTime.now();
    final lunes = DateTime(hoy.year, hoy.month, hoy.day).subtract(Duration(days: hoy.weekday - 1));
    return switch (this) {
      RangoDePeriodo.estaSemana => (lunes, lunes.add(const Duration(days: 6))),
      RangoDePeriodo.semanaPasada => (
          lunes.subtract(const Duration(days: 7)),
          lunes.subtract(const Duration(days: 1)),
        ),
      // Día 0 del mes siguiente: el último del mes, sin tener que saber si
      // tiene 28, 30 o 31.
      RangoDePeriodo.esteMes => (DateTime(hoy.year, hoy.month), DateTime(hoy.year, hoy.month + 1, 0)),
      RangoDePeriodo.mesPasado => (DateTime(hoy.year, hoy.month - 1), DateTime(hoy.year, hoy.month, 0)),
    };
  }

  /// "01/10/26 al 07/10/26".
  String get texto {
    final (d, h) = periodo;
    return '${Formato.fechaCorta(d)} al ${Formato.fechaCorta(h)}';
  }
}

/// De qué lado cae un número de la hoja.
enum TonoDeRenglon {
  /// Un importe que se lee solo, sin signo (lo que ganó, lo que vendió).
  neutro,

  /// Un dato de contexto, en gris (el efectivo que juntó en la puerta).
  apagado,

  /// Se le resta.
  contra,

  /// Se le suma.
  aFavor,
}

/// Un renglón de la hoja: concepto a la izquierda, número a la derecha.
class RenglonDeHoja {
  const RenglonDeHoja(
    this.concepto,
    this.valor, {
    this.detalle,
    this.tono = TonoDeRenglon.neutro,
    this.fuerte = false,
  });

  final String concepto;
  final String valor;
  final String? detalle;
  final TonoDeRenglon tono;
  final bool fuerte;
}

/// Un bloque de la hoja: "Envíos entregados", "Cargos", "Pedidos del período".
class BloqueDeHoja {
  const BloqueDeHoja({required this.titulo, required this.renglones, required this.vacio});

  final String titulo;
  final List<RenglonDeHoja> renglones;

  /// Qué decir cuando no hay renglones. Un bloque vacío se muestra igual:
  /// "sin cargos en este período" es información, no un bloque de más.
  final String vacio;
}

/// El documento completo.
class HojaDeLiquidacion {
  const HojaDeLiquidacion({
    required this.titular,
    required this.periodo,
    required this.etiqueta,
    required this.aFavor,
    required this.bloques,
    required this.cierre,
    required this.total,
    required this.archivo,
    this.pie,
  });

  /// El nombre del rider o del local.
  final String titular;

  /// "Del 01/10/26 al 07/10/26".
  final String periodo;

  /// "A pagarle" / "Tiene que rendir" / "Te pagamos".
  final String etiqueta;

  /// De qué lado cae el saldo, para el color y la pastilla.
  final bool aFavor;

  final List<BloqueDeHoja> bloques;

  /// La resta, renglón por renglón, antes del total.
  final List<RenglonDeHoja> cierre;

  final RenglonDeHoja total;

  /// Nombre del archivo PDF, sin extensión.
  final String archivo;

  /// "Emitido el 21 de octubre, 18:42." Solo va al papel.
  final String? pie;
}

String _archivo(String titular, DateTime hasta) =>
    'liquidacion-${titular.toLowerCase().replaceAll(' ', '-')}-'
    '${Formato.fechaCorta(hasta).replaceAll('/', '-')}';

String _pie() => 'Emitido el ${Formato.fechaHora(DateTime.now())}.';

String _periodo(DateTime desde, DateTime hasta) =>
    'Del ${Formato.fechaCorta(desde)} al ${Formato.fechaCorta(hasta)}';

/// La hoja de un rider en el período en curso.
///
/// [paraElMismo] cambia solo el tratamiento: la administración lee "A pagarle"
/// y el rider lee "Te pagamos". Los números son los mismos.
HojaDeLiquidacion hojaDeRider({
  required PendienteRider resumen,
  required List<RenglonDeRider> envios,
  required List<RenglonDeCargo> cargos,
  required DateTime desde,
  required DateTime hasta,
  bool paraElMismo = false,
}) {
  final r = resumen;
  final aFavor = r.total >= 0;

  return HojaDeLiquidacion(
    titular: r.rider,
    periodo: _periodo(desde, hasta),
    etiqueta: aFavor
        ? (paraElMismo ? 'Te pagamos' : 'A pagarle')
        : (paraElMismo ? 'Tenés que rendir' : 'Tiene que rendir'),
    aFavor: aFavor,
    bloques: [
      BloqueDeHoja(
        titulo: 'Envíos entregados',
        vacio: paraElMismo
            ? 'Todavía no entregaste nada en este período.'
            : 'No entregó nada en este período.',
        renglones: [
          for (final e in envios)
            RenglonDeHoja(
              '${e.codigo} · ${e.comercio}',
              Formato.pesos(e.ganancia),
              detalle: '${Formato.fechaHora(e.entregado)} · ${e.destino}'
                  '${e.efectivo == 0 ? '' : ' · cobró ${Formato.pesos(e.efectivo)}'}',
            ),
        ],
      ),
      BloqueDeHoja(
        titulo: 'Cargos',
        vacio: 'Sin cargos en este período.',
        renglones: [for (final c in cargos) _renglonDeCargo(c)],
      ),
    ],
    cierre: [
      RenglonDeHoja(
        '${paraElMismo ? "Ganaste" : "Ganó"} por ${r.envios} ${r.envios == 1 ? "envío" : "envíos"}',
        Formato.pesos(r.ganancias),
      ),
      if (r.efectivo != 0)
        RenglonDeHoja(
          '${paraElMismo ? "Cobraste" : "Cobró"} en efectivo',
          '− ${Formato.pesos(r.efectivo)}',
          detalle: paraElMismo
              ? 'Lo juntaste en la puerta y lo tenés que rendir'
              : 'Lo juntó en la puerta y lo tiene que rendir',
          tono: TonoDeRenglon.apagado,
        ),
      if (r.cargos != 0)
        RenglonDeHoja('Cargos', '− ${Formato.pesos(r.cargos)}', tono: TonoDeRenglon.contra),
    ],
    total: RenglonDeHoja(
      aFavor
          ? (paraElMismo ? 'Te pagamos' : 'A pagarle')
          : (paraElMismo ? 'Tenés que rendir' : 'Tiene que rendir'),
      Formato.pesos(r.total.abs()),
      fuerte: true,
      tono: aFavor ? TonoDeRenglon.aFavor : TonoDeRenglon.contra,
    ),
    archivo: _archivo(r.rider, hasta),
    pie: _pie(),
  );
}

/// La hoja de un local en el período en curso.
HojaDeLiquidacion hojaDeComercio({
  required PendienteComercio resumen,
  required List<RenglonDeComercio> pedidos,
  required List<RenglonDeCargo> cargos,
  required DateTime desde,
  required DateTime hasta,
  bool paraElMismo = false,
}) {
  final c = resumen;
  final aFavor = c.total >= 0;

  return HojaDeLiquidacion(
    titular: c.comercio,
    periodo: _periodo(desde, hasta),
    etiqueta: aFavor
        ? (paraElMismo ? 'Te pagamos' : 'A pagarle')
        : (paraElMismo ? 'Nos debés' : 'El local debe'),
    aFavor: aFavor,
    bloques: [
      BloqueDeHoja(
        titulo: 'Pedidos entregados',
        vacio: paraElMismo
            ? 'Todavía no entregaste ningún pedido en este período.'
            : 'No entregó pedidos en este período.',
        renglones: [
          for (final p in pedidos)
            RenglonDeHoja(
              '${p.codigo} · ${p.cliente}',
              Formato.pesos(p.productos),
              detalle: Formato.fechaHora(p.entregado),
            ),
        ],
      ),
      BloqueDeHoja(
        titulo: 'Descuentos',
        vacio: 'Sin descuentos en este período.',
        renglones: [for (final x in cargos) _renglonDeCargo(x)],
      ),
    ],
    cierre: [
      RenglonDeHoja(
        '${paraElMismo ? "Vendiste" : "Vendió"} en ${c.pedidos} ${c.pedidos == 1 ? "pedido" : "pedidos"}',
        Formato.pesos(c.ventas),
        // El envío no entra en la cuenta del local: esa plata es de MODO YA,
        // que le paga al rider su parte. Dicho acá se evita el reclamo de
        // "me falta el envío".
        detalle: 'Solo los productos: el envío lo cobra MODO YA',
      ),
      if (c.cargos != 0)
        RenglonDeHoja('Descuentos', '− ${Formato.pesos(c.cargos)}', tono: TonoDeRenglon.contra),
    ],
    total: RenglonDeHoja(
      aFavor
          ? (paraElMismo ? 'Te pagamos' : 'A pagarle')
          : (paraElMismo ? 'Nos debés' : 'El local debe'),
      Formato.pesos(c.total.abs()),
      fuerte: true,
      tono: aFavor ? TonoDeRenglon.aFavor : TonoDeRenglon.contra,
    ),
    archivo: _archivo(c.comercio, hasta),
    pie: _pie(),
  );
}

/// La hoja de una liquidación **ya cerrada**, de un local o de un rider.
///
/// Es el comprobante de lo que ya se pagó, así que el total no se recalcula:
/// sale de la fila que quedó guardada al cerrarla. Los renglones son los que
/// entraron en ese cierre, no los de hoy.
HojaDeLiquidacion hojaCerrada({
  required Liquidacion liquidacion,
  required List<RenglonCerrado> renglones,
  String? titular,
  bool paraElMismo = false,
}) {
  final l = liquidacion;
  final aFavor = l.total >= 0;
  final movimientos = renglones.where((r) => !r.esCargo).toList();
  final cargos = renglones.where((r) => r.esCargo).toList();

  return HojaDeLiquidacion(
    titular: titular ?? l.nombre,
    periodo: _periodo(l.desde, l.hasta),
    etiqueta: l.pagada ? 'Pagada' : (aFavor ? 'A cobrar' : 'A rendir'),
    aFavor: l.pagada || aFavor,
    bloques: [
      BloqueDeHoja(
        titulo: l.esComercio ? 'Pedidos entregados' : 'Envíos entregados',
        vacio: 'No hubo movimientos en este período.',
        renglones: [
          for (final r in movimientos)
            RenglonDeHoja(
              r.titulo,
              Formato.pesos(r.monto),
              detalle: _con(Formato.fechaHora(r.cuando), r.detalle),
            ),
        ],
      ),
      BloqueDeHoja(
        titulo: l.esComercio ? 'Descuentos' : 'Cargos',
        vacio: 'Sin descuentos en este período.',
        renglones: [
          for (final r in cargos)
            RenglonDeHoja(
              r.rotulo,
              Formato.pesos(r.monto),
              detalle: _con(Formato.fechaCorta(r.cuando), r.detalle),
              tono: r.monto > 0 ? TonoDeRenglon.contra : TonoDeRenglon.aFavor,
            ),
        ],
      ),
    ],
    cierre: [
      RenglonDeHoja(
        l.esComercio
            ? (paraElMismo ? 'Vendiste' : 'Vendió')
            : (paraElMismo ? 'Ganaste' : 'Ganó'),
        Formato.pesos(l.aFavor),
      ),
      if (l.enContra != 0)
        RenglonDeHoja(
          l.esComercio
              ? 'Descuentos'
              : (paraElMismo ? 'Cobraste en efectivo' : 'Cobró en efectivo'),
          '− ${Formato.pesos(l.enContra)}',
          tono: l.esComercio ? TonoDeRenglon.contra : TonoDeRenglon.apagado,
        ),
      // El rider tiene un tercer renglón: los cargos salen de una columna
      // propia (`ajustes`). Sin él la resta no da el total que está guardado.
      if (l.ajustes != 0)
        RenglonDeHoja('Cargos', '− ${Formato.pesos(l.ajustes)}', tono: TonoDeRenglon.contra),
    ],
    total: RenglonDeHoja(
      l.pagada
          ? (paraElMismo ? 'Te pagamos' : 'Pagada')
          : (aFavor ? 'A cobrar' : 'A rendir'),
      Formato.pesos(l.total.abs()),
      fuerte: true,
      tono: aFavor ? TonoDeRenglon.aFavor : TonoDeRenglon.contra,
    ),
    archivo: _archivo(titular ?? l.nombre, l.hasta),
    pie: _pie(),
  );
}

/// Pega la fecha con el resto del detalle, que puede no venir.
String _con(String fecha, String? resto) =>
    (resto == null || resto.isEmpty) ? fecha : '$fecha · $resto';

RenglonDeHoja _renglonDeCargo(RenglonDeCargo c) => RenglonDeHoja(
      c.rotulo,
      Formato.pesos(c.monto),
      detalle: '${Formato.fechaCorta(c.fecha)} · ${c.detalle}',
      // Un cargo negativo es una devolución: va del otro lado.
      tono: c.monto > 0 ? TonoDeRenglon.contra : TonoDeRenglon.aFavor,
    );
