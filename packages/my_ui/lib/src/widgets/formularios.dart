import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import 'animaciones.dart';
import 'controls.dart';
import 'surfaces.dart';

/// Pone el punto de miles mientras se escribe ("15000" se ve "15.000"), para
/// no tener que contar ceros en un precio o un tope. Solo enteros: la app
/// maneja pesos sin centavos.
///
/// El texto del campo queda con puntos: para leerlo, [MilesFormatter.leer].
class MilesFormatter extends TextInputFormatter {
  const MilesFormatter({this.negativos = false});

  /// Deja escribir un "-" adelante (un ajuste que devuelve plata).
  final bool negativos;

  static final _noDigito = RegExp(r'[^0-9]');

  /// `9800` → `"9.800"`. Para cargar un valor guardado en el campo.
  static String formatear(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// `"-15.000"` → `-15000`; null si no hay ningún número.
  static int? leer(String texto) {
    final t = texto.trim();
    final digitos = t.replaceAll(_noDigito, '');
    if (digitos.isEmpty) return null;
    final n = int.tryParse(digitos);
    if (n == null) return null;
    return t.startsWith('-') ? -n : n;
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue viejo, TextEditingValue nuevo) {
    var texto = nuevo.text;
    var cursor = nuevo.selection.end.clamp(0, texto.length);

    // Borrar justo un punto no hace nada visible (se vuelve a poner). Se
    // entiende que quiso borrar el número de antes, como en cualquier
    // calculadora.
    if (viejo.text.length == texto.length + 1 &&
        cursor < viejo.text.length &&
        viejo.text[cursor] == '.' &&
        viejo.text.replaceRange(cursor, cursor + 1, '') == texto &&
        cursor > 0) {
      texto = texto.replaceRange(cursor - 1, cursor, '');
      cursor -= 1;
    }

    final negativo = negativos && texto.trimLeft().startsWith('-');
    final digitos = texto.replaceAll(_noDigito, '');
    final antes = texto.substring(0, cursor).replaceAll(_noDigito, '').length;
    if (digitos.isEmpty) {
      final t = negativo ? '-' : '';
      return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    }

    final limpio = digitos.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final n = int.tryParse(limpio);
    // Un número más largo que un int no es un precio: se deja como estaba.
    if (n == null) return viejo;
    final resultado = formatear(negativo ? -n : n);

    // El cursor queda después del mismo dígito en el que estaba.
    final objetivo = (antes - (digitos.length - limpio.length)).clamp(0, limpio.length);
    var pos = negativo ? 1 : 0;
    var vistos = 0;
    while (vistos < objetivo && pos < resultado.length) {
      if (resultado[pos] != '.' && resultado[pos] != '-') vistos++;
      pos++;
    }
    return TextEditingValue(text: resultado, selection: TextSelection.collapsed(offset: pos));
  }
}

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
    this.formatos,
    this.foco,
    this.mayusculas = false,
    this.miles = false,
    this.negativos = false,
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

  /// Para campos con formato propio (número de tarjeta, vencimiento).
  final List<TextInputFormatter>? formatos;
  final FocusNode? foco;

  /// Escribe en mayúsculas mientras se tipea (nombre del titular).
  final bool mayusculas;

  /// Número con punto de miles mientras se escribe (precios, topes, montos).
  /// El valor se lee con [MilesFormatter.leer].
  final bool miles;

  /// Con [miles], deja escribir un "-" adelante.
  final bool negativos;

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
            focusNode: foco,
            keyboardType: miles
                ? TextInputType.numberWithOptions(signed: negativos)
                : soloNumeros
                    ? TextInputType.number
                    : keyboard,
            textCapitalization: mayusculas ? TextCapitalization.characters : TextCapitalization.none,
            inputFormatters: formatos ??
                (miles
                    ? [MilesFormatter(negativos: negativos)]
                    : soloNumeros
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null),
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
              if (obligatorio && t.isEmpty) return 'Completá este dato';
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
    final hijo = MyCambio(
      child: _cargando
          ? SizedBox(
              key: const ValueKey('cargando'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: widget.secundario ? MyColors.onSurface : MyColors.onPrimary,
              ),
            )
          : Row(
              key: const ValueKey('texto'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 22),
                  const SizedBox(width: MySpacing.xs),
                ],
                Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.onPressed == null ? 0.6 : 1,
      child: widget.secundario
          ? OutlinedButton(onPressed: habilitado ? _tocar : null, child: hijo)
          : FilledButton(onPressed: habilitado ? _tocar : null, child: hijo),
    );
  }
}

/// Muestra un error del backend como aviso flotante rojo (entra desde arriba
/// con rebote y se va solo).
void mostrarError(BuildContext context, Object error) {
  mostrarAvisoFlotante(context, '$error', tipo: MyAvisoTipo.error, duracion: const Duration(milliseconds: 3600));
}

/// Aviso de "listo": amarillo de marca con tilde animado.
void mostrarAviso(BuildContext context, String texto, {String? accion, VoidCallback? onAccion}) {
  mostrarAvisoFlotante(context, texto, tipo: MyAvisoTipo.exito, accion: accion, onAccion: onAccion);
}

/// Aviso informativo (negro): algo paso pero no es ni exito ni error.
void mostrarInfo(BuildContext context, String texto, {String? accion, VoidCallback? onAccion}) {
  mostrarAvisoFlotante(context, texto, tipo: MyAvisoTipo.info, accion: accion, onAccion: onAccion);
}

/// Un interruptor que se mueve apenas se toca y guarda por detrás.
///
/// Los de "Hay / Sin stock" y "Recibiendo pedidos" esperaban la respuesta de
/// la base para moverse: en medio del servicio, con mala señal, el local lo
/// tocaba dos veces creyendo que no había agarrado. Si guardar falla, vuelve
/// solo a donde estaba y el error lo muestra quien llama.
class MyInterruptor extends StatefulWidget {
  const MyInterruptor({super.key, required this.valor, required this.onChanged});

  final bool valor;
  final Future<void> Function(bool) onChanged;

  @override
  State<MyInterruptor> createState() => _MyInterruptorState();
}

class _MyInterruptorState extends State<MyInterruptor> {
  bool? _local;
  var _guardando = false;

  @override
  void didUpdateWidget(MyInterruptor viejo) {
    super.didUpdateWidget(viejo);
    // Llegó el valor de la base: manda ella.
    if (!_guardando && widget.valor != viejo.valor) _local = null;
  }

  Future<void> _cambiar(bool v) async {
    if (_guardando) return;
    setState(() {
      _local = v;
      _guardando = true;
    });
    try {
      await widget.onChanged(v);
    } catch (_) {
      if (mounted) setState(() => _local = null);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Switch(value: _local ?? widget.valor, onChanged: _cambiar);
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
    if (valor.hasValue) return MyApareceEn(child: datos(valor.value as T));
    if (valor.hasError) {
      return MyApareceEn(
        child: MyEmptyState(
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
        ),
      );
    }
    return cargando ?? const MyCargando();
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
    this.fondo,
  });

  final String? url;
  final double? ancho;
  final double? alto;
  final double radio;
  final IconData icono;

  /// Color de fondo del respaldo. Si es null, toma `surfaceContainerHigh`
  /// del tema ambiente.
  final Color? fondo;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final respaldo = Container(
      width: ancho,
      height: alto,
      color: fondo ?? esquema.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(icono, size: 28, color: esquema.onSurfaceVariant),
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
  final r = await mostrarDialogoAnimado<bool>(
    context,
    builder: (c) => AlertDialog(
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: peligroso ? MyColors.errorContainer : MyColors.primaryFixed,
          shape: BoxShape.circle,
        ),
        child: Icon(
          peligroso ? Symbols.warning : Symbols.help,
          color: peligroso ? MyColors.error : MyColors.onPrimaryFixed,
          fill: 1,
        ),
      ),
      title: Text(titulo, textAlign: TextAlign.center),
      content: Text(mensaje, style: MyType.bodyMd, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(c, false),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: peligroso ? MyColors.error : null,
            foregroundColor: peligroso ? MyColors.onError : null,
          ),
          child: Text(aceptar),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Pide un texto (por ejemplo, el motivo de un rechazo).
///
/// [ayuda] va arriba del campo: sirve para avisar qué consecuencia tiene lo
/// que se está por confirmar.
Future<String?> pedirTexto(
  BuildContext context, {
  required String titulo,
  required String label,
  String aceptar = 'Confirmar',
  String? inicial,
  String? ayuda,
}) {
  return mostrarDialogoAnimado<String>(
    context,
    builder: (_) => _DialogoTexto(
      titulo: titulo,
      label: label,
      aceptar: aceptar,
      inicial: inicial,
      ayuda: ayuda,
    ),
  );
}

/// El contenido de [pedirTexto].
///
/// Es un widget con estado y no un `AlertDialog` armado al vuelo porque el
/// controlador del campo tiene que vivir hasta que el dialogo termine de
/// cerrarse: liberandolo en cuanto `showGeneralDialog` devuelve, el campo se
/// sigue dibujando durante la animacion de salida con el controlador ya
/// liberado y explota.
class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({
    required this.titulo,
    required this.label,
    required this.aceptar,
    this.inicial,
    this.ayuda,
  });

  final String titulo;
  final String label;
  final String aceptar;
  final String? inicial;
  final String? ayuda;

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  late final _ctrl = TextEditingController(text: widget.inicial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _texto => _ctrl.text.trim();

  void _aceptar() {
    if (_texto.isNotEmpty) Navigator.pop(context, _texto);
  }

  @override
  Widget build(BuildContext context) {
    final ayuda = widget.ayuda;
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ayuda != null) ...[
            Text(ayuda, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
            const SizedBox(height: MySpacing.sm),
          ],
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(hintText: widget.label),
            // Sin esto el boton no se enteraba de lo que se escribe: se veia
            // habilitado con el campo vacio y al tocarlo no pasaba nada.
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: _texto.isEmpty ? null : _aceptar,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(widget.aceptar),
        ),
      ],
    );
  }
}
