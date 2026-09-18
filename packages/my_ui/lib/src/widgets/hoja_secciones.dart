import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'animaciones.dart';

/// Un acceso de la [mostrarHojaSecciones]: icono, nombre y que hacer al tocarlo.
class MySeccionHoja {
  const MySeccionHoja({
    required this.icon,
    required this.label,
    required this.onTap,
    this.activo = false,
    this.contador = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// La seccion en la que el usuario ya esta.
  final bool activo;

  /// Numero en rojo en la esquina (pedidos por cobrar, pedidos nuevos).
  final int contador;
}

/// Hoja inferior de "Mas secciones" / "Mi cuenta", igual en todas las apps.
///
/// Arriba el usuario (avatar amarillo con iniciales, nombre y detalle), en el
/// medio una grilla de accesos de tres por fila y al pie el selector de modo
/// claro / oscuro y, si se pasa [onSalir], el boton rojo de "Salir".
///
/// La hoja se cierra sola antes de ejecutar la accion tocada, asi la accion
/// puede navegar o abrir otro dialogo sin pisarse con la animacion de cierre.
Future<void> mostrarHojaSecciones(
  BuildContext context, {
  required String usuarioNombre,
  String? usuarioDetalle,
  String? usuarioExtra,
  String titulo = 'Más secciones',
  required List<MySeccionHoja> secciones,
  VoidCallback? onEditarUsuario,
  VoidCallback? onSalir,
  Widget? extra,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (hoja) => _HojaSecciones(
      usuarioNombre: usuarioNombre,
      usuarioDetalle: usuarioDetalle,
      usuarioExtra: usuarioExtra,
      titulo: titulo,
      secciones: secciones,
      onEditarUsuario: onEditarUsuario,
      onSalir: onSalir,
      extra: extra,
    ),
  );
}

class _HojaSecciones extends StatelessWidget {
  const _HojaSecciones({
    required this.usuarioNombre,
    required this.usuarioDetalle,
    required this.usuarioExtra,
    required this.titulo,
    required this.secciones,
    required this.onEditarUsuario,
    required this.onSalir,
    required this.extra,
  });

  final String usuarioNombre;
  final String? usuarioDetalle;
  final String? usuarioExtra;
  final String titulo;
  final List<MySeccionHoja> secciones;
  final VoidCallback? onEditarUsuario;
  final VoidCallback? onSalir;
  final Widget? extra;

  void _cerrarY(BuildContext hoja, VoidCallback accion) {
    Navigator.pop(hoja);
    // Despues de la animacion de cierre, para que un dialogo o una navegacion
    // no se superpongan con la hoja que se esta yendo.
    Future.delayed(const Duration(milliseconds: 220), accion);
  }

  @override
  Widget build(BuildContext context) {
    final abajo = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(MySpacing.md, MySpacing.sm, MySpacing.md, MySpacing.md + abajo),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: MyColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(MyRadius.full),
                ),
              ),
            ),
            const SizedBox(height: MySpacing.md),
            _Usuario(
              nombre: usuarioNombre,
              detalle: usuarioDetalle,
              extra: usuarioExtra,
              onEditar: onEditarUsuario == null ? null : () => _cerrarY(context, onEditarUsuario!),
            ),
            if (extra != null) ...[
              const SizedBox(height: MySpacing.md),
              extra!,
            ],
            const SizedBox(height: MySpacing.lg),
            Text(titulo, style: MyType.headlineSm),
            const SizedBox(height: MySpacing.sm),
            MyEntradaEscalonada(
              children: [
                for (var i = 0; i < secciones.length; i += 3)
                  Padding(
                    padding: EdgeInsets.only(bottom: i + 3 < secciones.length ? MySpacing.xs : 0),
                    child: Row(
                      children: [
                        for (var j = i; j < i + 3; j++) ...[
                          if (j > i) const SizedBox(width: MySpacing.xs),
                          Expanded(
                            child: j < secciones.length
                                ? _Acceso(seccion: secciones[j], onTap: () => _cerrarY(context, secciones[j].onTap))
                                : const SizedBox(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: MySpacing.md),
            Row(
              children: [
                Expanded(child: _SelectorTema()),
                if (onSalir != null) ...[
                  const SizedBox(width: MySpacing.xs),
                  _BotonSalir(onTap: () => _cerrarY(context, onSalir!)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Usuario extends StatelessWidget {
  const _Usuario({required this.nombre, required this.detalle, required this.extra, required this.onEditar});

  final String nombre;
  final String? detalle;
  final String? extra;
  final VoidCallback? onEditar;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MyAvatar(nombre: nombre, size: 52),
        const SizedBox(width: MySpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (detalle != null && detalle!.isNotEmpty)
                Text(detalle!, style: MyType.bodySm.copyWith(color: MyColors.secondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (extra != null && extra!.isNotEmpty)
                Text(extra!, style: MyType.bodySm.copyWith(color: MyColors.secondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (onEditar != null) ...[
          const SizedBox(width: MySpacing.xs),
          Material(
            color: MyColors.surfaceContainerLow,
            shape: const StadiumBorder(),
            child: InkWell(
              onTap: onEditar,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: MySpacing.sm, vertical: MySpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.edit, size: 16, color: MyColors.onSurface),
                    const SizedBox(width: MySpacing.xxs),
                    Text('Editar', style: MyType.labelMd),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Circulo amarillo con las iniciales del usuario.
class MyAvatar extends StatelessWidget {
  const MyAvatar({super.key, required this.nombre, this.size = 40});

  final String nombre;
  final double size;

  @override
  Widget build(BuildContext context) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final iniciales = partes.isEmpty ? '' : (partes.first[0] + (partes.length > 1 ? partes[1][0] : '')).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
      child: iniciales.isEmpty
          ? Icon(Symbols.person, size: size * 0.5, color: MyColors.onPrimary, fill: 1)
          : Text(iniciales, style: MyType.labelLg.copyWith(color: MyColors.onPrimary, fontSize: size * 0.34)),
    );
  }
}

class _Acceso extends StatelessWidget {
  const _Acceso({required this.seccion, required this.onTap});

  final MySeccionHoja seccion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activo = seccion.activo;
    return Material(
      color: activo ? MyColors.primaryFixed : MyColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(MyRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MySpacing.xs, vertical: MySpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Badge(
                isLabelVisible: seccion.contador > 0,
                label: Text('${seccion.contador}'),
                backgroundColor: MyColors.error,
                textColor: MyColors.onError,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: activo ? MyColors.primary : MyColors.surfaceContainerLowest,
                    shape: BoxShape.circle,
                    boxShadow: activo ? MyShadows.glow : MyShadows.subtle,
                  ),
                  child: Icon(
                    seccion.icon,
                    size: 22,
                    color: activo ? MyColors.onPrimary : MyColors.onSurface,
                    fill: activo ? 1 : 0,
                  ),
                ),
              ),
              const SizedBox(height: MySpacing.xs),
              Text(
                seccion.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MyType.labelMd.copyWith(
                  color: activo ? MyColors.onPrimaryFixed : MyColors.onSurface,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Tema" con las dos opciones (sol / luna). Cambia toda la app al instante.
class _SelectorTema extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oscuro = ref.watch(temaProvider) == ThemeMode.dark;
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(MySpacing.md, 4, 4, 4),
      decoration: BoxDecoration(
        color: MyColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MyRadius.lg),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Tema', style: MyType.labelLg)),
          _OpcionTema(
            icon: Symbols.light_mode,
            label: 'Claro',
            activo: !oscuro,
            onTap: () => ref.read(temaProvider.notifier).cambiar(ThemeMode.light),
          ),
          const SizedBox(width: 2),
          _OpcionTema(
            icon: Symbols.dark_mode,
            label: 'Oscuro',
            activo: oscuro,
            onTap: () => ref.read(temaProvider.notifier).cambiar(ThemeMode.dark),
          ),
        ],
      ),
    );
  }
}

class _OpcionTema extends StatelessWidget {
  const _OpcionTema({required this.icon, required this.label, required this.activo, required this.onTap});

  final IconData icon;
  final String label;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: activo ? MyColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(MyRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MyRadius.md),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: activo ? MyColors.onPrimary : MyColors.secondary, fill: activo ? 1 : 0),
          ),
        ),
      ),
    );
  }
}

class _BotonSalir extends StatelessWidget {
  const _BotonSalir({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MyColors.errorContainer,
      borderRadius: BorderRadius.circular(MyRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyRadius.lg),
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Symbols.logout, size: 20, color: MyColors.onErrorContainer),
                const SizedBox(width: MySpacing.xs),
                Text('Salir', style: MyType.labelLg.copyWith(color: MyColors.onErrorContainer)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
