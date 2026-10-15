import 'package:my_core/my_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// La liquidación del rider, en papel.
///
/// Se arma aparte de la pantalla a propósito: en el PDF no van los botones ni
/// el panel, y el papel tiene reglas propias (márgenes, una tipografía que
/// exista en el documento, el pie que se repite). Lo que sí comparte es de
/// dónde salen los números — los mismos que muestra la hoja.
Future<void> guardarLiquidacionEnPdf({
  required PendienteRider rider,
  required List<RenglonDeRider> envios,
  required List<CargoRider> cargos,
  required DateTime desde,
  required DateTime hasta,
}) async {
  final doc = pw.Document(title: 'Liquidación ${rider.rider}');

  // Las fuentes se empaquetan desde Google Fonts: el PDF no puede depender de
  // lo que tenga instalado quien lo abre.
  final base = await PdfGoogleFonts.interRegular();
  final negrita = await PdfGoogleFonts.interSemiBold();

  final amarillo = PdfColor.fromInt(0xFFFFC107);
  final gris = PdfColor.fromInt(0xFF6B7280);

  pw.Widget renglon(String concepto, String valor, {String? detalle, bool fuerte = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(concepto, style: pw.TextStyle(font: fuerte ? negrita : base, fontSize: 10)),
                if (detalle != null)
                  pw.Text(detalle, style: pw.TextStyle(font: base, fontSize: 8, color: gris)),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(valor,
              style: pw.TextStyle(font: fuerte ? negrita : base, fontSize: fuerte ? 12 : 10, color: color)),
        ],
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 32),
      footer: (c) => pw.Text(
        'MODO YA · Malargüe · página ${c.pageNumber} de ${c.pagesCount}',
        style: pw.TextStyle(font: base, fontSize: 8, color: gris),
      ),
      build: (c) => [
        // ---- Encabezado ------------------------------------------------------
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MODO YA', style: pw.TextStyle(font: negrita, fontSize: 10, color: gris)),
                  pw.SizedBox(height: 2),
                  pw.Text(rider.rider, style: pw.TextStyle(font: negrita, fontSize: 18)),
                  pw.Text(
                    'Liquidación del ${Formato.fechaCorta(desde)} al ${Formato.fechaCorta(hasta)}',
                    style: pw.TextStyle(font: base, fontSize: 9, color: gris),
                  ),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                color: amarillo,
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Text(
                rider.total >= 0 ? 'A pagarle' : 'Tiene que rendir',
                style: pw.TextStyle(font: negrita, fontSize: 9),
              ),
            ),
          ],
        ),
        pw.Divider(height: 24),

        // ---- Envíos -----------------------------------------------------------
        pw.Text('Envíos entregados', style: pw.TextStyle(font: negrita, fontSize: 11)),
        pw.SizedBox(height: 4),
        if (envios.isEmpty)
          pw.Text('No entregó nada en este período.',
              style: pw.TextStyle(font: base, fontSize: 9, color: gris))
        else
          for (final e in envios)
            renglon(
              '${e.codigo} · ${e.comercio}',
              Formato.pesos(e.ganancia),
              detalle: '${Formato.fechaHora(e.entregado)} · ${e.destino}'
                  '${e.efectivo == 0 ? '' : ' · cobró ${Formato.pesos(e.efectivo)}'}',
            ),

        pw.Divider(height: 24),

        // ---- Cargos ------------------------------------------------------------
        pw.Text('Cargos', style: pw.TextStyle(font: negrita, fontSize: 11)),
        pw.SizedBox(height: 4),
        if (cargos.isEmpty)
          pw.Text('Sin cargos en este período.',
              style: pw.TextStyle(font: base, fontSize: 9, color: gris))
        else
          for (final c in cargos)
            renglon(
              c.concepto.rotulo,
              Formato.pesos(c.monto),
              detalle: '${Formato.fechaCorta(c.fecha)} · ${c.detalle}',
            ),

        pw.Divider(height: 24),

        // ---- Cierre -------------------------------------------------------------
        renglon('Ganó por ${rider.envios} ${rider.envios == 1 ? "envío" : "envíos"}',
            Formato.pesos(rider.ganancias)),
        if (rider.efectivo != 0)
          renglon('Cobró en efectivo', '- ${Formato.pesos(rider.efectivo)}',
              detalle: 'Lo juntó en la puerta y lo tiene que rendir'),
        if (rider.cargos != 0) renglon('Cargos', '- ${Formato.pesos(rider.cargos)}'),
        pw.Divider(height: 16),
        renglon(
          rider.total >= 0 ? 'A pagarle' : 'Tiene que rendir',
          Formato.pesos(rider.total.abs()),
          fuerte: true,
        ),

        pw.SizedBox(height: 28),
        pw.Text(
          'Emitido el ${Formato.fechaHora(DateTime.now())}.',
          style: pw.TextStyle(font: base, fontSize: 8, color: gris),
        ),
      ],
    ),
  );

  // `sharePdf` resuelve cada plataforma: en Android abre el menú de compartir,
  // en Windows y en la web lo baja.
  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'liquidacion-${rider.rider.toLowerCase().replaceAll(' ', '-')}-'
        '${Formato.fechaCorta(hasta).replaceAll('/', '-')}.pdf',
  );
}
