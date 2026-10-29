import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';

/// Control de cantidad: menos, el número y más, en una pastilla.
///
/// Antes cada pantalla armaba el suyo con dos `IconButton` y un `Text`, y cada
/// uno se veía distinto (uno con el "menos" gris, otro con el "más" negro). El
/// número tiene un ancho fijo para que los botones no se corran al pasar de 9
/// a 10.
class MyStepper extends StatelessWidget {
  const MyStepper({
    super.key,
    required this.valor,
    required this.onChanged,
    this.minimo = 1,
    this.maximo = 99,
    this.compacto = false,
    this.conQuitar = false,
  });

  final int valor;
  final ValueChanged<int> onChanged;
  final int minimo;
  final int maximo;

  /// Más bajito, para renglones de una lista (el carrito, el resumen).
  final bool compacto;

  /// En el mínimo, el "menos" se vuelve un tacho y saca el renglón: en el
  /// carrito bajar de 1 es quitar el producto, no quedarse trabado en 1.
  final bool conQuitar;

  @override
  Widget build(BuildContext context) {
    final lado = compacto ? 34.0 : 44.0;
    final icono = compacto ? 18.0 : 22.0;
    final quita = conQuitar && valor <= minimo;
    final puedeBajar = valor > minimo || conQuitar;
    final puedeSubir = valor < maximo;

    Widget boton({
      required IconData icon,
      required String tooltip,
      required bool habilitado,
      required int nuevo,
    }) {
      return SizedBox(
        width: lado,
        height: lado,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: tooltip,
          onPressed: habilitado ? () => onChanged(nuevo) : null,
          icon: Icon(icon, size: icono),
          color: MyColors.onSurface,
          disabledColor: MyColors.outlineVariant,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: MyColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MyRadius.full),
        border: Border.all(color: MyColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          boton(
            icon: quita ? Symbols.delete : Symbols.remove,
            tooltip: quita ? 'Quitar' : 'Uno menos',
            habilitado: puedeBajar,
            nuevo: valor - 1,
          ),
          SizedBox(
            width: compacto ? 24 : 32,
            child: Text(
              '$valor',
              textAlign: TextAlign.center,
              style: (compacto ? MyType.labelLg : MyType.headlineSm).copyWith(color: MyColors.onSurface),
            ),
          ),
          boton(
            icon: Symbols.add,
            tooltip: 'Uno más',
            habilitado: puedeSubir,
            nuevo: valor + 1,
          ),
        ],
      ),
    );
  }
}
