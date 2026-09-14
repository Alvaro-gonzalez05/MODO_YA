import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import 'controls.dart';
import 'surfaces.dart';

/// Campo de formulario con rotulo en mayusculas arriba, como en el diseno.
class MyCampo extends StatelessWidget {
  const MyCampo({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboard,
    this.obligatorio = true,
    this.lineas = 1,
    this.ocultar = false,
    this.validar,
    this.onChanged,
    this.soloNumeros = false,
    this.autofill,
    this.accion,
    this.onSubmit,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboard;
  final bool obligatorio;
  final int lineas;
  final bool ocultar;
  final String? Function(String)? validar;
  final ValueChanged<String>? onChanged;
  final bool soloNumeros;
  final Iterable<String>? autofill;
  final TextInputAction? accion;
  final ValueChanged<String>? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MyOverline(label),
          const SizedBox(height: MySpacing.xs),
          TextFormField(
            controller: controller,
            keyboardType: soloNumeros ? TextInputType.number : keyboard,
            inputFormatters: soloNumeros ? [FilteringTextInputFormatter.digitsOnly] : null,
            maxLines: ocultar ? 1 : lineas,
            obscureText: ocultar,
            onChanged: onChanged,
            autofillHints: autofill,
            textInputAction: accion,
            onFieldSubmitted: onSubmit,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon == null ? null : Icon(icon, size: 20, color: MyColors.outline),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (obligatorio && t.isEmpty) return 'Completa este dato';
              return validar?.call(t);
            },
          ),
        ],
      ),
    );
  }
}

/// Boton principal que muestra un spinner mientras la accion esta en curso y
/// se deshabilita para evitar dobles envios.
class MyBotonAccion extends StatefulWidget {
  const MyBotonAccion({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.secundario = false,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool secundario;

  @override
  State<MyBotonAccion> createState() => _MyBotonAccionState();
}

class _MyBotonAccionState extends State<MyBotonAccion> {
  var _cargando = false;

  Future<void> _tocar() async {
    if (_cargando || widget.onPressed == null) return;
    setState(() => _cargando = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final habilitado = widget.onPressed != null && !_cargando;
    final hijo = _cargando
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: widget.secundario ? MyColors.primary : MyColors.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 22),
                const SizedBox(width: MySpacing.xs),
              ],
              Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
            ],
          );

    return widget.secundario
        ? OutlinedButton(onPressed: habilitado ? _tocar : null, child: hijo)
        : FilledButton(onPressed: habilitado ? _tocar : null, child: hijo);
  }
}

/// Muestra un error del backend como snackbar.
void mostrarError(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text('$error'),
      backgroundColor: MyColors.onErrorContainer,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void mostrarAviso(BuildContext context, String texto) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating));
}

/// Dibuja un AsyncValue con cargando / error / datos de forma pareja en toda la
/// app. El error trae un boton de reintentar.
class MyAsync<T> extends StatelessWidget {
  const MyAsync({
    super.key,
    required this.valor,
    required this.datos,
    this.onReintentar,
    this.cargando,
  });

  final AsyncValue<T> valor;
  final Widget Function(T datos) datos;
  final VoidCallback? onReintentar;
  final Widget? cargando;

  @override
  Widget build(BuildContext context) {
    // Si ya habia datos y esta recargando, se siguen mostrando: parpadear a un
    // spinner en cada refresco es peor que mostrar lo de hace un segundo.
    if (valor.hasValue) return datos(valor.value as T);
    if (valor.hasError) {
      return MyEmptyState(
        icon: Symbols.cloud_off,
        title: 'No pudimos cargar esto',
        message: '${valor.error}',
        action: onReintentar == null
            ? null
            : OutlinedButton.icon(
                onPressed: onReintentar,
                icon: const Icon(Symbols.refresh, size: 20),
                label: const Text('Reintentar'),
              ),
      );
    }
    return cargando ??
        const Padding(
          padding: EdgeInsets.all(MySpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        );
  }
}

/// Imagen de red con placeholder e icono de respaldo si no carga.
class MyImagen extends StatelessWidget {
  const MyImagen({
    super.key,
    required this.url,
    this.ancho,
    this.alto,
    this.radio = MyRadius.md,
    this.icono = Symbols.image,
    this.fondo = MyColors.surfaceContainerHigh,
  });

  final String? url;
  final double? ancho;
  final double? alto;
  final double radio;
  final IconData icono;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    final respaldo = Container(
      width: ancho,
      height: alto,
      color: fondo,
      alignment: Alignment.center,
      child: Icon(icono, size: 28, color: MyColors.secondary),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radio),
      child: url == null
          ? respaldo
          : Image.network(
              url!,
              width: ancho,
              height: alto,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => respaldo,
              loadingBuilder: (_, hijo, progreso) => progreso == null ? hijo : respaldo,
            ),
    );
  }
}

/// Confirmacion simple. Devuelve true si acepta.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String aceptar = 'Confirmar',
  bool peligroso = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje, style: MyType.bodyMd),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Volver')),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          style: peligroso ? FilledButton.styleFrom(backgroundColor: MyColors.error) : null,
          child: Text(aceptar),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Pide un texto (por ejemplo, el motivo de un rechazo).
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String label,
  String aceptar = 'Confirmar',
  String? inicial,
}) async {
  final ctrl = TextEditingController(text: inicial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 2,
        decoration: InputDecoration(hintText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Volver')),
        FilledButton(
          onPressed: () {
            final t = ctrl.text.trim();
            if (t.isNotEmpty) Navigator.pop(c, t);
          },
          child: Text(aceptar),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return r;
}
