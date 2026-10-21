import 'package:my_core/my_core.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// La liquidación en papel: la misma [HojaDeLiquidacion] que se ve en pantalla.
///
/// Se arma aparte del widget a propósito: en el PDF no van los botones ni el
/// panel, y el papel tiene reglas propias (márgenes, una tipografía que exista
/// en el documento, el pie que se repite). Lo que sí comparte es de dónde salen
/// los números — son los mismos renglones, ya formateados, así que la hoja y el
/// archivo no pueden discrepar.
///
/// Vive en `my_ui` y no en la app de administración porque el rider y el local
/// bajan su propio comprobante con este mismo código.
Future<void> guardarHojaEnPdf(HojaDeLiquidacion hoja) async {
  final doc = pw.Document(title: 'Liquidación ${hoja.titular}');

  // Las fuentes se empaquetan desde Google Fonts: el PDF no puede depender de
  // lo que tenga instalado quien lo abre.
  final base = await PdfGoogleFonts.interRegular();
  final negrita = await PdfGoogleFonts.interSemiBold();

  final amarillo = PdfColor.fromInt(0xFFFFC107);
  final gris = PdfColor.fromInt(0xFF6B7280);
  final rojo = PdfColor.fromInt(0xFFB3261E);

  // En papel el gris claro no se distingue del negro, así que solo se pinta lo
  // que resta: el resto queda en negro con su signo.
  PdfColor? color(TonoDeRenglon tono) => switch (tono) {
        TonoDeRenglon.contra => rojo,
        _ => null,
      };

  pw.Widget renglon(RenglonDeHoja r) {
    final fuente = r.fuerte ? negrita : base;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(r.concepto, style: pw.TextStyle(font: fuente, fontSize: 10)),
                if (r.detalle != null)
                  pw.Text(r.detalle!, style: pw.TextStyle(font: base, fontSize: 8, color: gris)),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            r.valor,
            style: pw.TextStyle(font: fuente, fontSize: r.fuerte ? 12 : 10, color: color(r.tono)),
          ),
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
                  pw.Text(hoja.titular, style: pw.TextStyle(font: negrita, fontSize: 18)),
                  pw.Text(
                    'Liquidación ${hoja.periodo.toLowerCase()}',
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
              child: pw.Text(hoja.etiqueta, style: pw.TextStyle(font: negrita, fontSize: 9)),
            ),
          ],
        ),

        // ---- Los bloques ------------------------------------------------------
        for (final b in hoja.bloques) ...[
          pw.Divider(height: 24),
          pw.Text(b.titulo, style: pw.TextStyle(font: negrita, fontSize: 11)),
          pw.SizedBox(height: 4),
          if (b.renglones.isEmpty)
            pw.Text(b.vacio, style: pw.TextStyle(font: base, fontSize: 9, color: gris))
          else
            for (final r in b.renglones) renglon(r),
        ],

        // ---- El cierre ---------------------------------------------------------
        pw.Divider(height: 24),
        for (final r in hoja.cierre) renglon(r),
        pw.Divider(height: 16),
        renglon(hoja.total),

        if (hoja.pie != null) ...[
          pw.SizedBox(height: 28),
          pw.Text(hoja.pie!, style: pw.TextStyle(font: base, fontSize: 8, color: gris)),
        ],
      ],
    ),
  );

  // `sharePdf` resuelve cada plataforma: en Android abre el menú de compartir,
  // en Windows y en la web lo baja.
  await Printing.sharePdf(bytes: await doc.save(), filename: '${hoja.archivo}.pdf');
}
