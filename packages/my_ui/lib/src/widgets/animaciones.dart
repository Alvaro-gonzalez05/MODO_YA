import 'package:flutter/material.dart';

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
///
/// Se usa en listas cortas y visibles de entrada (rubros del home, pasos de
/// un pedido) para que la app se sienta viva sin animar todo el arbol.
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

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.retraso, () {
      if (mounted) _controlador.forward();
    });
  }

  @override
  void dispose() {
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
      duration: const Duration(milliseconds: 320),
      curve: Curves.elasticOut,
      builder: (context, t, _) {
        return Transform.scale(
          scale: activo ? (0.9 + 0.1 * t) : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Color.lerp(colorInactivo, colorActivo, t),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: iconSize, color: Color.lerp(iconoInactivo, iconoActivo, t)),
          ),
        );
      },
    );
  }
}
