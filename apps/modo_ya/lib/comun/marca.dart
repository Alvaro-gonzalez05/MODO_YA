import 'package:flutter/material.dart';
import 'package:my_ui/my_ui.dart';

/// Logo grande de la marca (el archivo ya incluye el nombre "MODO YA") con la
/// bajada debajo, para las pantallas de acceso y el splash. Entra con un
/// fundido + escala suave.
class MarcaGrande extends StatelessWidget {
  const MarcaGrande({
    super.key,
    this.bajada = 'Delivery rápido, simple y local',
    this.tamano = 168,
    this.oscura = false,
  });

  final String bajada;
  final double tamano;

  /// Sobre fondo negro (splash): la bajada va en blanco.
  final bool oscura;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutBack,
      builder: (context, t, hijo) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: hijo),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MyLogoMark(size: tamano),
          const SizedBox(height: MySpacing.sm),
          Text(
            bajada.toUpperCase(),
            textAlign: TextAlign.center,
            style: MyType.labelMd.copyWith(
              color: oscura ? MyColors.inverseOnSurface.withValues(alpha: 0.85) : MyColors.onSurfaceVariant,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Contenedor centrado de ancho maximo para formularios: en Windows la ventana
/// es ancha y un formulario de 1200 px de ancho no se lee.
class FormularioCentrado extends StatelessWidget {
  const FormularioCentrado({super.key, required this.children, this.ancho = 460});

  final List<Widget> children;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ancho),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            children: [MyEntradaEscalonada(paso: const Duration(milliseconds: 60), children: children)],
          ),
        ),
      ),
    );
  }
}
