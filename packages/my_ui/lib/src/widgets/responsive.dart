import 'package:flutter/widgets.dart';

/// Formato de pantalla. Las apps tienen dos diseños, no uno estirado:
///
/// - **movil**: dock flotante abajo, tarjetas a lo ancho, una columna.
/// - **tableta**: barra lateral compacta (solo iconos) y contenido en grilla.
/// - **escritorio**: barra lateral completa, barra superior con el usuario,
///   tablas y paneles de detalle al costado (diseño C de Stitch).
enum MyFormato { movil, tableta, escritorio }

abstract final class MyBreakpoints {
  /// Desde acá entra la barra lateral.
  static const tableta = 720.0;

  /// Desde acá la barra lateral muestra los textos y hay paneles laterales.
  static const escritorio = 1100.0;

  static MyFormato de(double ancho) => ancho >= escritorio
      ? MyFormato.escritorio
      : ancho >= tableta
          ? MyFormato.tableta
          : MyFormato.movil;
}

extension MyFormatoContext on BuildContext {
  /// Se calcula con el ancho de la ventana, no del widget: así toda la
  /// pantalla decide lo mismo.
  MyFormato get formato => MyBreakpoints.de(MediaQuery.sizeOf(this).width);

  bool get esMovil => formato == MyFormato.movil;

  bool get esEscritorio => formato == MyFormato.escritorio;
}

/// Construye un hijo distinto según el ancho disponible del propio widget.
/// Para decidir columnas dentro de una tarjeta o un panel.
class MyResponsivo extends StatelessWidget {
  const MyResponsivo({super.key, required this.builder});

  final Widget Function(BuildContext context, MyFormato formato, double ancho) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => builder(context, MyBreakpoints.de(c.maxWidth), c.maxWidth),
    );
  }
}
