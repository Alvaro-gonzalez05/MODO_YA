import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import 'controls.dart';
import 'responsive.dart';
import 'surfaces.dart';

/// Pantalla de contenido con el encabezado del diseño: rótulo con punto,
/// título grande, bajada y acciones a la derecha (abajo en móvil).
///
/// Maneja los márgenes de cada formato y deja lugar para el dock en móvil.
class MyPagina extends StatelessWidget {
  const MyPagina({
    super.key,
    required this.titulo,
    required this.children,
    this.rotulo,
    this.bajada,
    this.acciones = const [],
    this.onRefresh,
    this.anchoMaximo = 1440,
    this.volver,
    this.conDock = true,
  });

  final String titulo;
  final String? rotulo;
  final String? bajada;
  final List<Widget> acciones;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double anchoMaximo;

  /// Si no es null, muestra la flecha para volver al lado del título.
  final VoidCallback? volver;

  /// En móvil deja espacio abajo para el dock flotante.
  final bool conDock;

  @override
  Widget build(BuildContext context) {
    final movil = context.esMovil;
    final margen = movil
        ? EdgeInsets.fromLTRB(
            MySpacing.screenEdge,
            MediaQuery.paddingOf(context).top + MySpacing.md,
            MySpacing.screenEdge,
            conDock ? MySpacing.dockClearance + MySpacing.md : MySpacing.xl,
          )
        : const EdgeInsets.fromLTRB(MySpacing.xxl, MySpacing.xl, MySpacing.xxl, MySpacing.xxxl);

    Widget lista = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: margen,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: anchoMaximo),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyEncabezado(
                  titulo: titulo,
                  rotulo: rotulo,
                  bajada: bajada,
                  acciones: acciones,
                  volver: volver,
                ),
                SizedBox(height: movil ? MySpacing.lg : MySpacing.xl),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );

    if (onRefresh != null) {
      lista = RefreshIndicator(onRefresh: onRefresh!, child: lista);
    }
    return lista;
  }
}

/// Encabezado de pantalla. Suelto para las pantallas que arman su propio scroll.
class MyEncabezado extends StatelessWidget {
  const MyEncabezado({
    super.key,
    required this.titulo,
    this.rotulo,
    this.bajada,
    this.acciones = const [],
    this.volver,
  });

  final String titulo;
  final String? rotulo;
  final String? bajada;
  final List<Widget> acciones;
  final VoidCallback? volver;

  @override
  Widget build(BuildContext context) {
    final movil = context.esMovil;

    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rotulo != null) ...[
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: MyColors.primaryContainer, shape: BoxShape.circle),
              ),
              const SizedBox(width: MySpacing.xs),
              Flexible(
                child: Text(
                  rotulo!.toUpperCase(),
                  style: MyType.labelSm.copyWith(color: MyColors.secondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.xxs),
        ],
        Text(
          titulo,
          style: movil ? MyType.headlineLg : MyType.headlineLg.copyWith(fontSize: 32, height: 40 / 32),
        ),
        if (bajada != null) ...[
          const SizedBox(height: MySpacing.xxs),
          Text(bajada!, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
        ],
      ],
    );

    final conVolver = volver == null
        ? textos
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: MySpacing.sm, top: 2),
                child: MyCircleIconButton(icon: Symbols.arrow_back, onTap: volver, size: 40),
              ),
              Expanded(child: textos),
            ],
          );

    if (acciones.isEmpty) return conVolver;

    if (movil) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          conVolver,
          const SizedBox(height: MySpacing.md),
          Wrap(spacing: MySpacing.xs, runSpacing: MySpacing.xs, children: acciones),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: conVolver),
        const SizedBox(width: MySpacing.lg),
        Wrap(spacing: MySpacing.sm, runSpacing: MySpacing.xs, children: acciones),
      ],
    );
  }
}

/// Botón de tamaño contenido (no ocupa todo el ancho como el CTA del tema).
/// Para encabezados, tablas y paneles.
class MyBoton extends StatelessWidget {
  const MyBoton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tipo = MyBotonTipo.principal,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final MyBotonTipo tipo;

  @override
  Widget build(BuildContext context) {
    final (fondo, texto) = switch (tipo) {
      MyBotonTipo.principal => (MyColors.primary, Colors.white),
      MyBotonTipo.secundario => (MyColors.secondaryContainer, MyColors.onSurface),
      MyBotonTipo.oscuro => (MyColors.dock, Colors.white),
      MyBotonTipo.peligro => (MyColors.errorContainer, MyColors.onErrorContainer),
      MyBotonTipo.texto => (Colors.transparent, MyColors.primary),
    };
    final style = FilledButton.styleFrom(
      backgroundColor: fondo,
      foregroundColor: texto,
      disabledBackgroundColor: MyColors.surfaceContainerHigh,
      minimumSize: const Size(0, 44),
      padding: EdgeInsets.symmetric(horizontal: icon == null ? MySpacing.lg : MySpacing.md),
      textStyle: MyType.labelLg,
      shape: const StadiumBorder(),
      elevation: 0,
    );
    final hijo = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: hijo)
        : FilledButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 19), label: hijo);
  }
}

enum MyBotonTipo { principal, secundario, oscuro, peligro, texto }

/// Grilla que acomoda la cantidad de columnas al ancho disponible.
/// Las tarjetas de una misma fila quedan de la misma altura.
class MyGrilla extends StatelessWidget {
  const MyGrilla({
    super.key,
    required this.children,
    this.anchoMinimo = 240,
    this.maxColumnas = 4,
    this.espacio = MySpacing.md,
  });

  final List<Widget> children;
  final double anchoMinimo;
  final int maxColumnas;
  final double espacio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columnas = ((c.maxWidth + espacio) / (anchoMinimo + espacio)).floor().clamp(1, maxColumnas);
        final filas = <Widget>[];
        for (var i = 0; i < children.length; i += columnas) {
          final fila = children.sublist(i, (i + columnas).clamp(0, children.length));
          filas.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columnas; j++) ...[
                    if (j > 0) SizedBox(width: espacio),
                    Expanded(child: j < fila.length ? fila[j] : const SizedBox()),
                  ],
                ],
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) SizedBox(height: espacio),
              filas[i],
            ],
          ],
        );
      },
    );
  }
}

/// Indicador del resumen: rótulo, icono, número grande, detalle y barra.
class MyKpi extends StatelessWidget {
  const MyKpi({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.icono,
    this.detalle,
    this.pastilla,
    this.progreso,
    this.destacado = false,
    this.onTap,
  });

  final String rotulo;
  final String valor;
  final IconData icono;
  final String? detalle;
  final String? pastilla;

  /// Entre 0 y 1. Null = sin barra.
  final double? progreso;

  /// Fondo ember: algo que requiere acción.
  final bool destacado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final texto = destacado ? Colors.white : MyColors.onSurface;
    final suave = destacado ? Colors.white70 : MyColors.secondary;

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: MySpacing.xxs),
                child: Text(rotulo.toUpperCase(), style: MyType.labelSm.copyWith(color: suave)),
              ),
            ),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: destacado ? Colors.white.withValues(alpha: 0.18) : MyColors.primaryFixed,
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 20, color: destacado ? Colors.white : MyColors.primary),
            ),
          ],
        ),
        const SizedBox(height: MySpacing.sm),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: MySpacing.xs,
          runSpacing: MySpacing.xxs,
          children: [
            Text(valor, style: MyType.displayLg.copyWith(color: texto)),
            if (pastilla != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: MySpacing.xs, vertical: 3),
                decoration: BoxDecoration(
                  color: destacado ? Colors.white.withValues(alpha: 0.2) : MyColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(MyRadius.full),
                ),
                child: Text(
                  pastilla!,
                  style: MyType.labelMd.copyWith(color: destacado ? Colors.white : MyColors.onSecondaryFixedVariant),
                ),
              ),
          ],
        ),
        if (detalle != null) ...[
          const SizedBox(height: MySpacing.xxs),
          Text(detalle!, style: MyType.bodySm.copyWith(color: suave)),
        ],
        const Spacer(),
        if (progreso != null) ...[
          const SizedBox(height: MySpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(MyRadius.full),
            child: LinearProgressIndicator(
              value: progreso!.clamp(0, 1),
              minHeight: 6,
              color: destacado ? Colors.white : MyColors.primary,
              backgroundColor: destacado ? Colors.white24 : MyColors.surfaceContainerHigh,
            ),
          ),
        ],
      ],
    );

    const padding = EdgeInsets.all(MySpacing.lg);
    final tarjeta = destacado
        ? MyHeroCard(padding: padding, child: contenido)
        : MyCard(padding: padding, child: contenido);
    if (onTap == null) return tarjeta;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: tarjeta),
    );
  }
}

/// Columna de [MyTabla].
class MyColumna {
  const MyColumna(this.label, {this.flex = 1, this.alDerecha = false});

  final String label;
  final int flex;
  final bool alDerecha;
}

/// Fila de [MyTabla].
class MyFila {
  const MyFila({required this.celdas, this.onTap, this.seleccionada = false});

  final List<Widget> celdas;
  final VoidCallback? onTap;
  final bool seleccionada;
}

/// Tabla del panel de escritorio: encabezado en mayúsculas sobre fondo
/// celeste, filas con hover y la seleccionada resaltada en ember.
class MyTabla extends StatelessWidget {
  const MyTabla({
    super.key,
    required this.columnas,
    required this.filas,
    this.titulo,
    this.acciones = const [],
    this.pie,
  });

  final List<MyColumna> columnas;
  final List<MyFila> filas;
  final String? titulo;
  final List<Widget> acciones;
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MyRadius.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (titulo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(MySpacing.xl, MySpacing.lg, MySpacing.lg, MySpacing.md),
                child: Row(
                  children: [
                    Expanded(child: Text(titulo!, style: MyType.headlineSm)),
                    ...acciones,
                  ],
                ),
              ),
            Container(
              color: MyColors.surfaceContainerLow,
              padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl, vertical: MySpacing.sm),
              child: Row(
                children: [
                  for (final c in columnas)
                    Expanded(
                      flex: c.flex,
                      child: Text(
                        c.label.toUpperCase(),
                        textAlign: c.alDerecha ? TextAlign.right : TextAlign.left,
                        style: MyType.labelSm.copyWith(color: MyColors.secondary),
                      ),
                    ),
                ],
              ),
            ),
            for (var i = 0; i < filas.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: MySpacing.xl, endIndent: MySpacing.xl),
              _FilaTabla(columnas: columnas, fila: filas[i]),
            ],
            if (pie != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl, vertical: MySpacing.md),
                child: pie,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaTabla extends StatefulWidget {
  const _FilaTabla({required this.columnas, required this.fila});

  final List<MyColumna> columnas;
  final MyFila fila;

  @override
  State<_FilaTabla> createState() => _FilaTablaState();
}

class _FilaTablaState extends State<_FilaTabla> {
  var _encima = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.fila;
    final fondo = f.seleccionada
        ? MyColors.primaryFixed.withValues(alpha: 0.55)
        : (_encima && f.onTap != null ? MyColors.surfaceContainerLow.withValues(alpha: 0.6) : Colors.transparent);

    return MouseRegion(
      cursor: f.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: f.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: fondo,
          padding: const EdgeInsets.symmetric(horizontal: MySpacing.xl, vertical: MySpacing.md),
          child: Row(
            children: [
              for (var i = 0; i < widget.columnas.length; i++)
                Expanded(
                  flex: widget.columnas[i].flex,
                  child: Align(
                    alignment: widget.columnas[i].alDerecha ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(right: MySpacing.sm),
                      child: i < f.celdas.length ? f.celdas[i] : const SizedBox(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Celda de tabla con título y bajada.
class MyCeldaDoble extends StatelessWidget {
  const MyCeldaDoble(this.titulo, {super.key, this.bajada, this.inicio});

  final String titulo;
  final String? bajada;

  /// Logo, avatar o icono a la izquierda.
  final Widget? inicio;

  @override
  Widget build(BuildContext context) {
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titulo, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (bajada != null)
          Text(
            bajada!,
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    if (inicio == null) return textos;
    return Row(
      children: [
        inicio!,
        const SizedBox(width: MySpacing.sm),
        Flexible(child: textos),
      ],
    );
  }
}

/// Icono dentro de un círculo o cuadrado suave. Para filas y paneles.
class MyIconoCaja extends StatelessWidget {
  const MyIconoCaja(
    this.icono, {
    super.key,
    this.tamano = 42,
    this.fondo = MyColors.primaryFixed,
    this.color = MyColors.primary,
    this.circular = false,
  });

  final IconData icono;
  final double tamano;
  final Color fondo;
  final Color color;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: fondo,
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(tamano * 0.3),
      ),
      child: Icon(icono, size: tamano * 0.5, color: color),
    );
  }
}

/// Dato rotulado para fichas: "TELÉFONO  2604 555-1290".
class MyDato extends StatelessWidget {
  const MyDato(this.rotulo, this.valor, {super.key, this.icono});

  final String rotulo;
  final String valor;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 18, color: MyColors.secondary),
            const SizedBox(width: MySpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MyOverline(rotulo),
                const SizedBox(height: 2),
                SelectableText(valor, style: MyType.labelLg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de búsqueda con icono.
class MyBuscador extends StatelessWidget {
  const MyBuscador({super.key, required this.onChanged, this.hint = 'Buscar', this.controller});

  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Symbols.search, size: 22, color: MyColors.secondary),
        fillColor: MyColors.surfaceContainerLowest,
      ),
    );
  }
}

/// Filtros en pastillas con contador: "Todos (34)  Suspendidos (2)".
class MyFiltros<T> extends StatelessWidget {
  const MyFiltros({
    super.key,
    required this.opciones,
    required this.seleccionado,
    required this.onChanged,
  });

  final List<(T valor, String label, int cantidad)> opciones;
  final T seleccionado;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (valor, label, cantidad) in opciones) ...[
            MyChip('$label ($cantidad)', selected: valor == seleccionado, onTap: () => onChanged(valor)),
            const SizedBox(width: MySpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// Pastilla de estado de la barra superior: "● Servicio operativo · 3 riders".
class MyPastillaEstado extends StatelessWidget {
  const MyPastillaEstado({
    super.key,
    required this.texto,
    this.detalle,
    this.color = MyColors.success,
  });

  final String texto;
  final String? detalle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.xs),
      decoration: BoxDecoration(
        color: MyColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(MyRadius.full),
        boxShadow: MyShadows.subtle,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: MySpacing.xs),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: texto, style: MyType.labelLg),
                  if (detalle != null)
                    TextSpan(
                      text: '  ·  $detalle',
                      style: MyType.labelMd.copyWith(color: MyColors.primary),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Divide la pantalla en contenido principal y panel de detalle a la derecha.
/// En pantallas angostas el panel no se muestra (se abre como hoja).
class MyConPanel extends StatelessWidget {
  const MyConPanel({super.key, required this.principal, this.panel, this.anchoPanel = 380});

  final Widget principal;
  final Widget? panel;
  final double anchoPanel;

  @override
  Widget build(BuildContext context) {
    if (panel == null || !context.esEscritorio) return principal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: principal),
        const SizedBox(width: MySpacing.lg),
        SizedBox(width: anchoPanel, child: panel),
      ],
    );
  }
}

/// Muestra un panel de detalle como hoja inferior (para móvil y tableta).
Future<void> mostrarPanelComoHoja(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: MyColors.surface,
    builder: (hoja) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(MySpacing.md, MySpacing.sm, MySpacing.md, MySpacing.xl),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: MySpacing.md),
              decoration: BoxDecoration(
                color: MyColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          builder(hoja),
        ],
      ),
    ),
  );
}
