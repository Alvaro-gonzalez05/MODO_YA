import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'hoja_secciones.dart';
import 'marca.dart';
import 'navigation.dart';
import 'responsive.dart';

/// Un destino de la navegación principal.
class MyDestino {
  const MyDestino({required this.icon, required this.label, this.contador = 0});

  final IconData icon;
  final String label;

  /// Número en rojo al lado (pedidos por cobrar, pedidos nuevos). 0 = nada.
  final int contador;
}

/// Acción del menú del usuario ("Cambiar contraseña", "Salir").
class MyAccionUsuario {
  const MyAccionUsuario({
    required this.icon,
    required this.label,
    required this.onTap,
    this.peligrosa = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool peligrosa;
}

/// Contenedor principal de las apps, con un diseño para cada formato.
///
/// - **Escritorio / tableta**: barra lateral navy con la marca, barra superior
///   con el estado de la operación y el menú del usuario (siempre con "Salir").
/// - **Móvil**: el dock flotante de la app del rider. Si hay más destinos de los
///   que entran, el último botón es "Más" y abre una hoja con el resto y las
///   acciones del usuario.
class MyAppShell extends StatelessWidget {
  const MyAppShell({
    super.key,
    required this.destinos,
    required this.indice,
    required this.onSelect,
    required this.body,
    required this.seccion,
    required this.usuarioNombre,
    this.usuarioDetalle,
    this.accionesUsuario = const [],
    this.subtitulo = 'Malargüe · Mendoza',
    this.estado,
    this.version,
    this.mostrarDock = true,
    this.maxEnDock = 5,
  });

  final List<MyDestino> destinos;
  final int indice;
  final ValueChanged<int> onSelect;
  final Widget body;

  /// Rótulo al lado de la marca: "ADMIN", "LOCAL".
  final String seccion;
  final String subtitulo;

  final String usuarioNombre;
  final String? usuarioDetalle;
  final List<MyAccionUsuario> accionesUsuario;

  /// Pastilla de la barra superior en escritorio ("Recibiendo pedidos").
  final Widget? estado;

  /// Se muestra al pie de la barra lateral.
  final String? version;

  /// En móvil, false esconde el dock (pantallas de detalle con su propia barra).
  final bool mostrarDock;
  final int maxEnDock;

  @override
  Widget build(BuildContext context) {
    final formato = context.formato;
    if (formato == MyFormato.movil) return _movil(context);

    return Scaffold(
      backgroundColor: MyColors.surface,
      body: Row(
        children: [
          _BarraLateral(
            compacta: formato == MyFormato.tableta,
            destinos: destinos,
            indice: indice,
            onSelect: onSelect,
            seccion: seccion,
            subtitulo: subtitulo,
            version: version,
          ),
          Expanded(
            child: Column(
              children: [
                _BarraSuperior(
                  estado: estado,
                  usuarioNombre: usuarioNombre,
                  usuarioDetalle: usuarioDetalle,
                  acciones: accionesUsuario,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _movil(BuildContext context) {
    final desborda = destinos.length > maxEnDock;
    final enDock = desborda ? destinos.sublist(0, maxEnDock - 1) : destinos;
    final activoEnDock = indice < enDock.length ? indice : enDock.length;

    return Scaffold(
      backgroundColor: MyColors.surface,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          if (mostrarDock)
            Align(
              alignment: Alignment.bottomCenter,
              child: MyDock(
                items: [
                  for (final d in enDock) MyDockItem(icon: d.icon, label: d.label, contador: d.contador),
                  if (desborda)
                    MyDockItem(
                      icon: Symbols.menu,
                      label: 'Más',
                      contador: destinos.sublist(maxEnDock - 1).fold(0, (s, d) => s + d.contador),
                    ),
                ],
                currentIndex: activoEnDock,
                onSelect: (i) {
                  if (desborda && i == enDock.length) {
                    _hojaMas(context, destinos.sublist(maxEnDock - 1), maxEnDock - 1);
                  } else {
                    onSelect(i);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _hojaMas(BuildContext context, List<MyDestino> resto, int desde) {
    // Las acciones peligrosas ("Cerrar sesion") van al boton rojo del pie; el
    // resto, como accesos en la grilla junto a las secciones que no entraron.
    final salir = accionesUsuario.where((a) => a.peligrosa).firstOrNull;
    return mostrarHojaSecciones(
      context,
      usuarioNombre: usuarioNombre,
      usuarioDetalle: usuarioDetalle,
      secciones: [
        for (var i = 0; i < resto.length; i++)
          MySeccionHoja(
            icon: resto[i].icon,
            label: resto[i].label,
            activo: indice == desde + i,
            contador: resto[i].contador,
            onTap: () => onSelect(desde + i),
          ),
        for (final a in accionesUsuario)
          if (!a.peligrosa) MySeccionHoja(icon: a.icon, label: a.label, onTap: a.onTap),
      ],
      onSalir: salir?.onTap,
    );
  }
}

class _BarraLateral extends StatelessWidget {
  const _BarraLateral({
    required this.compacta,
    required this.destinos,
    required this.indice,
    required this.onSelect,
    required this.seccion,
    required this.subtitulo,
    required this.version,
  });

  final bool compacta;
  final List<MyDestino> destinos;
  final int indice;
  final ValueChanged<int> onSelect;
  final String seccion;
  final String subtitulo;
  final String? version;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compacta ? 88 : 264,
      color: MyColors.dock,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compacta ? 0 : MySpacing.lg, MySpacing.lg, MySpacing.md, MySpacing.xl),
              child: Row(
                mainAxisAlignment: compacta ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  const _LogoMarca(),
                  if (!compacta) ...[
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                'MODO YA',
                                style: MyType.headlineSm.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: MySpacing.xs),
                              Flexible(
                                child: Text(
                                  seccion.toUpperCase(),
                                  style: MyType.labelSm.copyWith(color: MyColors.primary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            subtitulo,
                            style: MyType.bodySm.copyWith(color: const Color(0xFFB8B8C0)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: compacta ? MySpacing.sm : MySpacing.md),
                children: [
                  for (var i = 0; i < destinos.length; i++)
                    _ItemLateral(
                      destino: destinos[i],
                      activo: i == indice,
                      compacta: compacta,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
            if (version != null)
              Padding(
                padding: const EdgeInsets.all(MySpacing.md),
                child: compacta
                    ? Text(
                        'v$version',
                        textAlign: TextAlign.center,
                        style: MyType.labelSm.copyWith(color: const Color(0xFF7A7A85)),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: MySpacing.sm, vertical: MySpacing.sm),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(MyRadius.md),
                        ),
                        child: Row(
                          children: [
                            Icon(Symbols.verified, size: 18, color: MyColors.primary),
                            const SizedBox(width: MySpacing.xs),
                            Expanded(
                              child: Text(
                                'Versión $version',
                                style: MyType.labelMd.copyWith(color: const Color(0xFFB8B8C0)),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogoMarca extends StatelessWidget {
  const _LogoMarca();

  @override
  Widget build(BuildContext context) {
    return const MyLogoMark(size: 44);
  }
}

class _ItemLateral extends StatefulWidget {
  const _ItemLateral({
    required this.destino,
    required this.activo,
    required this.compacta,
    required this.onTap,
  });

  final MyDestino destino;
  final bool activo;
  final bool compacta;
  final VoidCallback onTap;

  @override
  State<_ItemLateral> createState() => _ItemLateralState();
}

class _ItemLateralState extends State<_ItemLateral> {
  var _encima = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.destino;
    final activo = widget.activo;
    final colorTexto = activo ? MyColors.onPrimary : const Color(0xFFD0D0D6);

    final contenido = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: widget.compacta ? 0 : MySpacing.md),
      decoration: BoxDecoration(
        color: activo
            ? MyColors.primary
            : (_encima ? Colors.white.withValues(alpha: 0.07) : Colors.transparent),
        borderRadius: BorderRadius.circular(MyRadius.md),
        boxShadow: activo
            ? MyShadows.glow
            : null,
      ),
      child: Row(
        mainAxisAlignment: widget.compacta ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Badge(
            isLabelVisible: widget.compacta && d.contador > 0,
            label: Text('${d.contador}'),
            child: Icon(d.icon, size: 22, color: activo ? MyColors.onPrimary : const Color(0xFF9A9AA3), fill: activo ? 1 : 0),
          ),
          if (!widget.compacta) ...[
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Text(
                d.label,
                style: MyType.labelLg.copyWith(color: colorTexto, fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (d.contador > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: activo ? MyColors.onPrimary : MyColors.primary,
                  borderRadius: BorderRadius.circular(MyRadius.full),
                ),
                child: Text(
                  '${d.contador}',
                  textAlign: TextAlign.center,
                  style: MyType.labelMd.copyWith(color: activo ? MyColors.primary : MyColors.onPrimary),
                ),
              ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.xxs),
      child: Tooltip(
        message: widget.compacta ? d.label : '',
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _encima = true),
          onExit: (_) => setState(() => _encima = false),
          child: Semantics(
            button: true,
            selected: activo,
            label: d.label,
            child: GestureDetector(onTap: widget.onTap, child: contenido),
          ),
        ),
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior({
    required this.estado,
    required this.usuarioNombre,
    required this.usuarioDetalle,
    required this.acciones,
  });

  final Widget? estado;
  final String usuarioNombre;
  final String? usuarioDetalle;
  final List<MyAccionUsuario> acciones;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: MySpacing.xxl),
      decoration: BoxDecoration(
        color: MyColors.surface,
        border: Border(bottom: BorderSide(color: MyColors.surfaceContainer)),
      ),
      child: SafeArea(
        left: false,
        bottom: false,
        child: Row(
          children: [
            // Expanded y no Flexible + Spacer: con un Flexible suelto el espacio
            // que no usa la pastilla se pierde y el menu no llega al borde.
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: estado ?? const SizedBox()),
            ),
            const _BotonTema(),
            const SizedBox(width: MySpacing.md),
            MenuAnchor(
              alignmentOffset: const Offset(0, 8),
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(MyColors.surfaceContainerLowest),
                surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
                elevation: const WidgetStatePropertyAll(8),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyRadius.lg)),
                ),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: MySpacing.xs)),
              ),
              menuChildren: [
                for (final a in acciones)
                  MenuItemButton(
                    leadingIcon: Icon(a.icon, size: 20, color: a.peligrosa ? MyColors.error : MyColors.secondary),
                    onPressed: a.onTap,
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(220, 44)),
                      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: MySpacing.md)),
                    ),
                    child: Text(
                      a.label,
                      style: MyType.labelLg.copyWith(color: a.peligrosa ? MyColors.error : MyColors.onSurface),
                    ),
                  ),
              ],
              builder: (context, menu, _) => InkWell(
                onTap: () => menu.isOpen ? menu.close() : menu.open(),
                borderRadius: BorderRadius.circular(MyRadius.full),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MySpacing.xs, vertical: MySpacing.xxs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(usuarioNombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (usuarioDetalle != null)
                              Text(
                                usuarioDetalle!,
                                style: MyType.bodySm.copyWith(color: MyColors.secondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: MySpacing.sm),
                      _Avatar(nombre: usuarioNombre),
                      const SizedBox(width: MySpacing.xxs),
                      Icon(Symbols.keyboard_arrow_down, size: 20, color: MyColors.secondary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sol / luna: alterna el modo claro y oscuro de toda la app.
class _BotonTema extends ConsumerWidget {
  const _BotonTema();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oscuro = ref.watch(temaProvider) == ThemeMode.dark;
    return Tooltip(
      message: oscuro ? 'Modo claro' : 'Modo oscuro',
      child: Material(
        color: MyColors.surfaceContainerLow,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () => ref.read(temaProvider.notifier).alternar(),
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(oscuro ? Symbols.light_mode : Symbols.dark_mode, size: 20, color: MyColors.onSurface),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final iniciales = partes.isEmpty
        ? ''
        : (partes.first[0] + (partes.length > 1 ? partes[1][0] : '')).toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
      child: iniciales.isEmpty
          ? Icon(Symbols.person, size: 20, color: MyColors.onPrimary, fill: 1)
          : Text(iniciales, style: MyType.labelLg.copyWith(color: MyColors.onPrimary)),
    );
  }
}
