import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// Un bloque de formulario con su título: "Lo básico", "Precio", "Opciones".
///
/// Los formularios del local eran una sola tarjeta con todos los campos uno
/// abajo del otro: con títulos se entiende qué se está completando y qué es
/// opcional sin leer cada rótulo.
class SeccionFormulario extends StatelessWidget {
  const SeccionFormulario({
    super.key,
    required this.titulo,
    required this.children,
    this.bajada,
    this.enTarjeta = true,
  });

  final String titulo;
  final String? bajada;
  final List<Widget> children;

  /// Sin tarjeta cuando lo de adentro ya son tarjetas (los grupos de
  /// opciones): una tarjeta dentro de otra come ancho que en 360 px no hay.
  final bool enTarjeta;

  @override
  Widget build(BuildContext context) {
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(titulo, style: MyType.headlineSm),
        if (bajada != null) ...[
          const SizedBox(height: MySpacing.xxs),
          Text(bajada!, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
        ],
        const SizedBox(height: MySpacing.md),
        ...children,
      ],
    );
    return enTarjeta ? MyCard(child: contenido) : contenido;
  }
}

/// Un número chico con menos y más: minutos de demora, porcentaje de una
/// promo. Escribirlo con el teclado numérico para cambiarlo de a cinco era más
/// lento y dejaba poner cualquier cosa.
class Contador extends StatelessWidget {
  const Contador({
    super.key,
    required this.valor,
    required this.onChanged,
    this.minimo = 0,
    this.maximo = 999,
    this.paso = 1,
    this.formato,
  });

  final int valor;
  final ValueChanged<int> onChanged;
  final int minimo;
  final int maximo;
  final int paso;

  /// Cómo se escribe el número ("25 min", "20%").
  final String Function(int)? formato;

  @override
  Widget build(BuildContext context) {
    final texto = formato?.call(valor) ?? '$valor';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Boton(
          icono: Symbols.remove,
          tooltip: 'Menos',
          onTap: valor - paso >= minimo ? () => onChanged(valor - paso) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88),
          child: Text(texto, textAlign: TextAlign.center, style: MyType.headlineSm),
        ),
        _Boton(
          icono: Symbols.add,
          tooltip: 'Más',
          onTap: valor + paso <= maximo ? () => onChanged(valor + paso) : null,
        ),
      ],
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({required this.icono, required this.tooltip, required this.onTap});

  final IconData icono;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: MyCircleIconButton(icon: icono, size: 40, onTap: onTap),
      ),
    );
  }
}

/// Un formulario largo con el botón de guardar siempre a mano.
///
/// En el celular el botón va en una barra fija abajo: al final de un
/// formulario de diez campos nadie lo encontraba sin bajar hasta el fondo. En
/// la compu entra todo en pantalla y el botón va al final de la columna, así
/// que acá solo se devuelve la página.
class ConBarraDeGuardado extends StatelessWidget {
  const ConBarraDeGuardado({super.key, required this.pagina, required this.boton, this.resumen});

  final Widget pagina;
  final Widget boton;

  /// Algo corto arriba del botón, como el total de un envío.
  final Widget? resumen;

  @override
  Widget build(BuildContext context) {
    if (!context.esMovil) return pagina;
    return Column(
      children: [
        Expanded(child: pagina),
        DecoratedBox(
          decoration: BoxDecoration(
            color: MyColors.surfaceContainerLowest,
            border: Border(top: BorderSide(color: MyColors.outlineVariant)),
            boxShadow: MyShadows.subtle,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.sm, MySpacing.screenEdge, MySpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (resumen != null) ...[resumen!, const SizedBox(height: MySpacing.xs)],
                  boton,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un sí/no con su explicación: "Lo pueden pedir", "Tiene que elegir".
///
/// No es un `SwitchListTile` porque adentro de una tarjeta Flutter avisa que
/// el ripple queda tapado por el fondo, y en el celular el renglón entero
/// tiene que poder tocarse.
class InterruptorFormulario extends StatelessWidget {
  const InterruptorFormulario({
    super.key,
    required this.titulo,
    required this.valor,
    required this.onChanged,
    this.bajada,
  });

  final String titulo;
  final String? bajada;
  final bool valor;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => onChanged(!valor),
        borderRadius: BorderRadius.circular(MyRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: MyType.labelLg),
                    if (bajada != null) Text(bajada!, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                  ],
                ),
              ),
              const SizedBox(width: MySpacing.sm),
              Switch(value: valor, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
