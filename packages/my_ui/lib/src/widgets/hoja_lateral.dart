import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import 'escritorio.dart';
import 'responsive.dart';

/// Un panel que entra desde la derecha con aspecto de hoja impresa.
///
/// Para los detalles que son un documento y no una pantalla: la liquidación de
/// un rider, el resumen de un período. Ocupa la mitad del ancho porque lo que
/// importa es poder seguir viendo la lista de atrás: se compara el renglón con
/// el detalle sin ir y volver.
///
/// En el celular no hay "mitad" que valga, así que cae en la hoja de abajo que
/// ya se usa en el resto de la app.
Future<void> mostrarHojaLateral(
  BuildContext context, {
  required WidgetBuilder builder,
  String? titulo,
}) {
  if (!context.esEscritorio) {
    return mostrarPanelComoHoja(context, builder);
  }

  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: titulo ?? 'Detalle',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (contexto, _, _) => _HojaLateral(titulo: titulo, builder: builder),
    transitionBuilder: (contexto, anim, _, child) {
      // Entra deslizándose, no apareciendo: que se entienda que es una capa
      // encima y no otra pantalla.
      final curva = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curva),
        child: child,
      );
    },
  );
}

class _HojaLateral extends StatelessWidget {
  const _HojaLateral({required this.builder, this.titulo});

  final WidgetBuilder builder;
  final String? titulo;

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    // La mitad, pero con límites: en una pantalla ancha una hoja de 1200 px no
    // se lee, y en una angosta media pantalla no alcanza.
    final anchoHoja = (ancho / 2).clamp(460.0, 760.0);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: anchoHoja,
          height: double.infinity,
          decoration: BoxDecoration(
            color: MyColors.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 32,
                offset: const Offset(-8, 0),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(MySpacing.lg, MySpacing.md, MySpacing.sm, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(titulo ?? '', style: MyType.labelLg.copyWith(color: MyColors.secondary)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Symbols.close),
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      MySpacing.lg, MySpacing.sm, MySpacing.lg, MySpacing.xl),
                    child: builder(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La hoja en sí: fondo blanco, margen generoso y tipografía de documento.
///
/// Se separa del panel porque es lo que después se imprime o se guarda: lo de
/// afuera (el deslizamiento, la cruz) no va al papel.
class MyHojaImpresa extends StatelessWidget {
  const MyHojaImpresa({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MySpacing.xl),
      decoration: BoxDecoration(
        color: MyColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(MyRadius.card),
        border: Border.all(color: MyColors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// Una fila de la hoja: concepto a la izquierda, número a la derecha.
class MyRenglon extends StatelessWidget {
  const MyRenglon(
    this.concepto,
    this.valor, {
    super.key,
    this.detalle,
    this.fuerte = false,
    this.color,
  });

  final String concepto;
  final String valor;
  final String? detalle;
  final bool fuerte;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final estilo = fuerte ? MyType.labelLg : MyType.bodyMd;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(concepto, style: estilo),
                if (detalle != null)
                  Text(detalle!, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.md),
          Text(valor, style: estilo.copyWith(color: color)),
        ],
      ),
    );
  }
}
