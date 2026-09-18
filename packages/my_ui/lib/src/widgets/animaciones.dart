import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';

/// Envuelve cualquier boton/tarjeta tocable y lo achica un poco al presionar,
/// como feedback tactil. Pensado para elementos que ya manejan su propio
/// `onTap` (rubros, tarjetas de local, chips) y no tienen el ripple de
/// Material porque van sobre imagenes o fondos de color.
class MyPressable extends StatefulWidget {
  const MyPressable({
    super.key,
    required this.child,
    this.onTap,
    this.escala = 0.94,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double escala;

  @override
  State<MyPressable> createState() => _MyPressableState();
}

class _MyPressableState extends State<MyPressable> {
  var _presionado = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _presionado = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _presionado ? widget.escala : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Hace aparecer a [child] con un fundido + deslizamiento hacia arriba,
/// opcionalmente con [retraso] para escalonar una lista (chip 0, 1, 2, ...).
class MyApareceEn extends StatefulWidget {
  const MyApareceEn({
    super.key,
    required this.child,
    this.retraso = Duration.zero,
    this.duracion = const Duration(milliseconds: 380),
    this.desplazamiento = 14,
  });

  final Widget child;
  final Duration retraso;
  final Duration duracion;
  final double desplazamiento;

  @override
  State<MyApareceEn> createState() => _MyApareceEnState();
}

class _MyApareceEnState extends State<MyApareceEn> with SingleTickerProviderStateMixin {
  late final _controlador = AnimationController(vsync: this, duration: widget.duracion);
  late final _curva = CurvedAnimation(parent: _controlador, curve: Curves.easeOutCubic);
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    if (widget.retraso == Duration.zero) {
      _controlador.forward();
    } else {
      _espera = Timer(widget.retraso, () {
        if (mounted) _controlador.forward();
      });
    }
  }

  @override
  void dispose() {
    _espera?.cancel();
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curva,
      builder: (context, child) => Opacity(
        opacity: _curva.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _curva.value) * widget.desplazamiento),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Lista/columna cuyos hijos entran escalonados (cada uno un poco despues del
/// anterior). Para tarjetas de un listado, filas de un resumen, pasos.
class MyEntradaEscalonada extends StatelessWidget {
  const MyEntradaEscalonada({
    super.key,
    required this.children,
    this.paso = const Duration(milliseconds: 45),
    this.desde = 0,
  });

  final List<Widget> children;
  final Duration paso;

  /// Indice del primer hijo (para seguir la cuenta de una lista anterior).
  final int desde;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, hijo) in children.indexed)
          MyApareceEn(retraso: paso * (desde + i), child: hijo),
      ],
    );
  }
}

/// Circulo de paso (rubro, estado de pedido) que anima color, tamano e icono
/// cuando cambia de inactivo a activo/hecho, con un pequeno "pop" al llegar.
class MyPasoCirculo extends StatelessWidget {
  const MyPasoCirculo({
    super.key,
    required this.activo,
    required this.icon,
    required this.colorActivo,
    required this.colorInactivo,
    required this.iconoActivo,
    required this.iconoInactivo,
    this.size = 32,
    this.iconSize = 16,
  });

  final bool activo;
  final IconData icon;
  final Color colorActivo;
  final Color colorInactivo;
  final Color iconoActivo;
  final Color iconoInactivo;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: activo ? 1 : 0),
      duration: const Duration(milliseconds: 420),
      curve: Curves.elasticOut,
      builder: (context, t, _) {
        return Transform.scale(
          scale: activo ? (0.85 + 0.15 * t) : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Color.lerp(colorInactivo, colorActivo, t.clamp(0, 1)),
              shape: BoxShape.circle,
              boxShadow: activo ? MyShadows.glow : null,
            ),
            child: Icon(icon, size: iconSize, color: Color.lerp(iconoInactivo, iconoActivo, t.clamp(0, 1))),
          ),
        );
      },
    );
  }
}

/// Punto que "respira" (crece y se atenua en bucle): estado en vivo, rider
/// buscando, pedido en curso.
class MyPulso extends StatefulWidget {
  const MyPulso({super.key, this._color, this.size = 10});

  final Color? _color;

  Color get color => _color ?? MyColors.primary;
  final double size;

  @override
  State<MyPulso> createState() => _MyPulsoState();
}

class _MyPulsoState extends State<MyPulso> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lado = widget.size * 2.6;
    return SizedBox(
      width: lado,
      height: lado,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size + (lado - widget.size) * t,
                height: widget.size + (lado - widget.size) * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: (1 - t) * 0.45),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Indicador de carga de marca: anillo amarillo con el punto negro adentro,
/// que aparece con un fundido corto (evita el parpadeo en cargas rapidas).
class MyCargando extends StatelessWidget {
  const MyCargando({
    super.key,
    this.size = 40,
    this.padding = const EdgeInsets.all(MySpacing.xxl),
    this._colorPunto,
  });

  final double size;
  final EdgeInsetsGeometry padding;

  /// Color del punto del centro (blanco sobre el splash negro).
  final Color? _colorPunto;
  Color get colorPunto => _colorPunto ?? MyColors.onSurface;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: MyApareceEn(
          retraso: const Duration(milliseconds: 120),
          desplazamiento: 0,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(strokeWidth: size * 0.1, color: MyColors.primary, strokeCap: StrokeCap.round),
                MyPulso(color: colorPunto, size: size * 0.16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cambia de un hijo a otro con fundido + escala (badges de estado, montos,
/// contadores del carrito). Usa la `key` de cada hijo para saber que cambio.
class MyCambio extends StatelessWidget {
  const MyCambio({super.key, required this.child, this.duracion = const Duration(milliseconds: 260)});

  final Widget child;
  final Duration duracion;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duracion,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (hijo, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(anim), child: hijo),
      ),
      child: child,
    );
  }
}

/// Numero que "cuenta" hasta el nuevo valor cuando cambia (subtotal del
/// carrito, cantidad de productos, ganancia del dia).
class MyNumeroAnimado extends StatelessWidget {
  const MyNumeroAnimado({
    super.key,
    required this.valor,
    required this.formato,
    this.style,
    this.duracion = const Duration(milliseconds: 520),
  });

  final num valor;
  final String Function(num) formato;
  final TextStyle? style;
  final Duration duracion;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: valor.toDouble(), end: valor.toDouble()),
      duration: duracion,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(formato(v.round()), style: style),
    );
  }
}

/// Icono que hace un "pop" (crece con rebote) cada vez que cambia [disparador]:
/// la bolsita del carrito cuando se agrega un producto, el corazon de favorito.
class MyPop extends StatefulWidget {
  const MyPop({super.key, required this.child, required this.disparador});

  final Widget child;
  final Object? disparador;

  @override
  State<MyPop> createState() => _MyPopState();
}

class _MyPopState extends State<MyPop> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final _escala = TweenSequence<double>([
    TweenSequenceItem(tween: Tween<double>(begin: 1, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween<double>(begin: 1.35, end: 1).chain(CurveTween(curve: Curves.elasticOut)), weight: 60),
  ]).animate(_c);

  @override
  void didUpdateWidget(covariant MyPop old) {
    super.didUpdateWidget(old);
    if (old.disparador != widget.disparador) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _escala, child: widget.child);
}

// ---------------------------------------------------------------------------
// Avisos flotantes
// ---------------------------------------------------------------------------

/// Tipo de aviso flotante.
enum MyAvisoTipo { exito, info, error }

/// Muestra un aviso flotante arriba de todo: entra deslizandose desde el
/// borde superior con rebote, el icono hace "pop" y se va solo a los
/// [duracion]. Reemplaza al snackbar de Material en toda la app.
///
/// - [MyAvisoTipo.exito]: amarillo de marca con texto negro.
/// - [MyAvisoTipo.info]: negro con texto blanco.
/// - [MyAvisoTipo.error]: rojo con texto blanco.
void mostrarAvisoFlotante(
  BuildContext context,
  String texto, {
  MyAvisoTipo tipo = MyAvisoTipo.info,
  Duration duracion = const Duration(milliseconds: 2800),
  String? accion,
  VoidCallback? onAccion,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _AvisoFlotante.mostrar(overlay, texto: texto, tipo: tipo, duracion: duracion, accion: accion, onAccion: onAccion);
}

class _AvisoFlotante extends StatefulWidget {
  const _AvisoFlotante({
    required this.texto,
    required this.tipo,
    required this.duracion,
    required this.cerrar,
    this.accion,
    this.onAccion,
  });

  final String texto;
  final MyAvisoTipo tipo;
  final Duration duracion;
  final VoidCallback cerrar;
  final String? accion;
  final VoidCallback? onAccion;

  /// Solo un aviso a la vez: el nuevo saca al anterior.
  static OverlayEntry? _actual;

  static void mostrar(
    OverlayState overlay, {
    required String texto,
    required MyAvisoTipo tipo,
    required Duration duracion,
    String? accion,
    VoidCallback? onAccion,
  }) {
    _actual?.remove();
    _actual = null;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _AvisoFlotante(
        texto: texto,
        tipo: tipo,
        duracion: duracion,
        accion: accion,
        onAccion: onAccion,
        cerrar: () {
          if (_actual == entry) _actual = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _actual = entry;
    overlay.insert(entry);
  }

  @override
  State<_AvisoFlotante> createState() => _AvisoFlotanteState();
}

class _AvisoFlotanteState extends State<_AvisoFlotante> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 460), reverseDuration: const Duration(milliseconds: 260));
  late final _entrada = CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duracion, _salir);
  }

  Future<void> _salir() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.reverse();
    widget.cerrar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (fondo, frente, icono) = switch (widget.tipo) {
      MyAvisoTipo.exito => (MyColors.primary, MyColors.onPrimary, Symbols.check_circle),
      MyAvisoTipo.info => (MyColors.inverseSurface, MyColors.inverseOnSurface, Symbols.info),
      MyAvisoTipo.error => (MyColors.error, MyColors.onError, Symbols.error),
    };
    final arriba = MediaQuery.paddingOf(context).top + MySpacing.sm;
    final ancho = MediaQuery.sizeOf(context).width;

    return Positioned(
      top: arriba,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: AnimatedBuilder(
            animation: _entrada,
            builder: (context, child) => Opacity(
              opacity: _entrada.value.clamp(0, 1),
              child: Transform.translate(
                offset: Offset(0, (1 - _entrada.value) * -40),
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: math.min(ancho - MySpacing.screenEdge * 2, 520)),
              child: Material(
                color: fondo,
                borderRadius: BorderRadius.circular(MyRadius.lg),
                elevation: 10,
                shadowColor: Colors.black.withValues(alpha: 0.35),
                child: Dismissible(
                  key: UniqueKey(),
                  direction: DismissDirection.up,
                  onDismissed: (_) => widget.cerrar(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.elasticOut,
                          builder: (context, t, hijo) => Transform.scale(scale: 0.6 + 0.4 * t, child: hijo),
                          child: Icon(icono, color: frente, size: 22, fill: 1),
                        ),
                        const SizedBox(width: MySpacing.sm),
                        Flexible(
                          child: Text(
                            widget.texto,
                            style: MyType.labelLg.copyWith(color: frente),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.accion != null) ...[
                          const SizedBox(width: MySpacing.xs),
                          TextButton(
                            onPressed: () {
                              widget.onAccion?.call();
                              _salir();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: frente,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(horizontal: MySpacing.sm, vertical: MySpacing.xs),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              backgroundColor: frente.withValues(alpha: 0.12),
                            ),
                            child: Text(widget.accion!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogos
// ---------------------------------------------------------------------------

/// `showDialog` con la transicion de MODO YA: el dialogo entra con escala y
/// fundido (con un rebote corto) sobre un fondo oscurecido.
Future<T?> mostrarDialogoAnimado<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool cerrable = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: cerrable,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, anim, _, child) {
      final curva = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween<double>(begin: 0.88, end: 1).animate(curva), child: child),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Pantalla de exito
// ---------------------------------------------------------------------------

/// Pantalla completa negra de "listo": el tilde entra con rebote dentro de
/// un circulo amarillo, salen rayitas alrededor y despues aparece el texto.
/// Se cierra sola a los [duracion] (o al tocar). Para pedidos confirmados,
/// envios creados, entregas completadas.
Future<void> mostrarExito(
  BuildContext context, {
  required String titulo,
  String? mensaje,
  IconData icono = Symbols.check,
  Duration duracion = const Duration(milliseconds: 2200),
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: titulo,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, _) => _PantallaExito(titulo: titulo, mensaje: mensaje, icono: icono, duracion: duracion),
    transitionBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

class _PantallaExito extends StatefulWidget {
  const _PantallaExito({required this.titulo, required this.mensaje, required this.icono, required this.duracion});

  final String titulo;
  final String? mensaje;
  final IconData icono;
  final Duration duracion;

  @override
  State<_PantallaExito> createState() => _PantallaExitoState();
}

class _PantallaExitoState extends State<_PantallaExito> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duracion, _cerrar);
  }

  void _cerrar() {
    _timer?.cancel();
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final circulo = CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.elasticOut));
    final tilde = CurvedAnimation(parent: _c, curve: const Interval(0.25, 0.6, curve: Curves.easeOutBack));
    final rayos = CurvedAnimation(parent: _c, curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic));
    final texto = CurvedAnimation(parent: _c, curve: const Interval(0.5, 1, curve: Curves.easeOutCubic));

    return GestureDetector(
      onTap: _cerrar,
      child: Material(
        color: MyColors.dock,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(size: const Size(200, 200), painter: _RayosPainter(rayos.value)),
                        Transform.scale(
                          scale: circulo.value,
                          child: Container(
                            width: 118,
                            height: 118,
                            decoration: BoxDecoration(color: MyColors.primary, shape: BoxShape.circle, boxShadow: MyShadows.glow),
                            child: Transform.scale(
                              scale: tilde.value.clamp(0, 1.2),
                              child: Icon(widget.icono, size: 64, color: MyColors.onPrimary, weight: 700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: MySpacing.lg),
                AnimatedBuilder(
                  animation: texto,
                  builder: (context, child) => Opacity(
                    opacity: texto.value.clamp(0, 1),
                    child: Transform.translate(offset: Offset(0, (1 - texto.value) * 16), child: child),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.titulo,
                        textAlign: TextAlign.center,
                        style: MyType.headlineLg.copyWith(color: MyColors.inverseOnSurface),
                      ),
                      if (widget.mensaje != null) ...[
                        const SizedBox(height: MySpacing.xs),
                        Text(
                          widget.mensaje!,
                          textAlign: TextAlign.center,
                          style: MyType.bodyLg.copyWith(color: MyColors.inverseOnSurface.withValues(alpha: 0.72)),
                        ),
                      ],
                    ],
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

/// Rayitas que salen del circulo hacia afuera y se desvanecen (como el
/// confeti de la pantalla de confirmacion de la referencia).
class _RayosPainter extends CustomPainter {
  _RayosPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final centro = size.center(Offset.zero);
    final pintura = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    const n = 12;
    for (var i = 0; i < n; i++) {
      final ang = (i / n) * math.pi * 2 - math.pi / 2;
      final color = i.isEven ? MyColors.primary : MyColors.inverseOnSurface;
      pintura.color = color.withValues(alpha: (1 - t).clamp(0, 1));
      final desde = 68 + 30 * t;
      final hasta = desde + 14 + 10 * (1 - t);
      canvas.drawLine(
        centro + Offset(math.cos(ang), math.sin(ang)) * desde,
        centro + Offset(math.cos(ang), math.sin(ang)) * hasta,
        pintura,
      );
    }
  }

  @override
  bool shouldRepaint(_RayosPainter old) => old.t != t;
}
