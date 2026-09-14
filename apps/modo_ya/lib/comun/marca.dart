import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// Logo + nombre, para las pantallas de acceso.
class MarcaGrande extends StatelessWidget {
  const MarcaGrande({super.key, this.bajada = 'Tu ciudad en movimiento'});

  final String bajada;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [MyColors.primaryContainer, MyColors.primary],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: MyShadows.hero,
          ),
          child: const Icon(Symbols.bolt, size: 40, color: MyColors.onPrimary, fill: 1),
        ),
        const SizedBox(height: MySpacing.md),
        Text('MODO YA', style: MyType.displayLg),
        const SizedBox(height: MySpacing.xxs),
        Text(bajada, style: MyType.bodyLg.copyWith(color: MyColors.secondary)),
      ],
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
            children: children,
          ),
        ),
      ),
    );
  }
}
