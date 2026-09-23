import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';

/// Marcas de tarjeta que reconocemos por el número, para pintarla y mostrar el
/// logo. Si no coincide ninguna, queda la genérica.
enum MyMarcaTarjeta {
  visa('visa', 'VISA', [Color(0xFF1A1F71), Color(0xFF3B4AA8)]),
  mastercard('master', 'mastercard', [Color(0xFF1A1A1A), Color(0xFF4A3B2A)]),
  amex('amex', 'AMEX', [Color(0xFF0B5D8F), Color(0xFF1C8ECC)]),
  cabal('cabal', 'Cabal', [Color(0xFF0E5C3A), Color(0xFF1B9459)]),
  naranja('naranja', 'Naranja', [Color(0xFF8A3A00), Color(0xFFE85D04)]),
  otra('tarjeta', 'Tarjeta', [Color(0xFF141416), Color(0xFF3A3A44)]);

  const MyMarcaTarjeta(this.wire, this.etiqueta, this.degrade);

  /// Como la llama Mercado Pago (`payment_method_id`).
  final String wire;
  final String etiqueta;
  final List<Color> degrade;

  /// Deduce la marca del número mientras se escribe.
  static MyMarcaTarjeta deNumero(String numero) {
    final n = numero.replaceAll(RegExp(r'\D'), '');
    if (n.startsWith('4')) return visa;
    // Naranja antes que Cabal: las dos empiezan con 58.
    if (n.startsWith('589562')) return naranja;
    // En Argentina las Mastercard de débito y prepagas empiezan con 50.
    if (RegExp(r'^(5[0-5]|2[2-7])').hasMatch(n)) return mastercard;
    if (RegExp(r'^3[47]').hasMatch(n)) return amex;
    if (RegExp(r'^(58|60|6042|6043)').hasMatch(n)) return cabal;
    return otra;
  }

  static MyMarcaTarjeta deWire(String? w) =>
      values.firstWhere((m) => m.wire == w, orElse: () => otra);
}

/// La tarjeta de crédito dibujada, que se va completando mientras la persona
/// escribe y se da vuelta al tocar el código de seguridad.
///
/// Es solo visual: no valida ni cobra nada.
class MyTarjetaVisual extends StatefulWidget {
  const MyTarjetaVisual({
    super.key,
    required this.numero,
    required this.titular,
    required this.vencimiento,
    required this.codigo,
    this.mostrarDorso = false,
    this.marca,
    this.ultimos4,
  });

  /// Con o sin espacios, como venga.
  final String numero;
  final String titular;

  /// "MM/AA".
  final String vencimiento;
  final String codigo;

  /// true mientras el foco está en el código de seguridad.
  final bool mostrarDorso;

  /// Si ya se conoce (tarjeta guardada), evita adivinarla del número.
  final MyMarcaTarjeta? marca;

  /// Tarjeta guardada: no hay número, solo los últimos cuatro.
  final String? ultimos4;

  @override
  State<MyTarjetaVisual> createState() => _MyTarjetaVisualState();
}

class _MyTarjetaVisualState extends State<MyTarjetaVisual> with SingleTickerProviderStateMixin {
  late final _giro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.mostrarDorso ? 1 : 0,
  );

  @override
  void didUpdateWidget(MyTarjetaVisual viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.mostrarDorso != widget.mostrarDorso) {
      widget.mostrarDorso ? _giro.forward() : _giro.reverse();
    }
  }

  @override
  void dispose() {
    _giro.dispose();
    super.dispose();
  }

  MyMarcaTarjeta get _marca => widget.marca ?? MyMarcaTarjeta.deNumero(widget.numero);

  /// "4509 9535 6623 3704", completando con • lo que falta. Con una tarjeta
  /// guardada, los cuatro números conocidos van al final: •••• •••• •••• 0604.
  String get _numeroFormateado {
    final guardada = widget.ultimos4;
    final n = guardada != null
        ? '••••••••••••$guardada'
        : widget.numero.replaceAll(RegExp(r'\D'), '').padRight(16, '•');
    return [for (var i = 0; i < 16; i += 4) n.substring(i, i + 4)].join('  ');
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.586, // proporción real de una tarjeta
      child: AnimatedBuilder(
        animation: _giro,
        builder: (context, _) {
          final angulo = _giro.value * math.pi;
          final dorso = angulo > math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012) // perspectiva: se ve el giro en 3D
              ..rotateY(angulo),
            child: dorso
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _Dorso(marca: _marca, codigo: widget.codigo),
                  )
                : _Frente(
                    marca: _marca,
                    numero: _numeroFormateado,
                    titular: widget.titular,
                    vencimiento: widget.vencimiento,
                  ),
          );
        },
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.marca, required this.child});

  final MyMarcaTarjeta marca;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: marca.degrade,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: child,
    );
  }
}

class _Frente extends StatelessWidget {
  const _Frente({required this.marca, required this.numero, required this.titular, required this.vencimiento});

  final MyMarcaTarjeta marca;
  final String numero;
  final String titular;
  final String vencimiento;

  @override
  Widget build(BuildContext context) {
    return _Caja(
      marca: marca,
      child: Stack(
        children: [
          // Brillo diagonal, para que no sea un rectángulo plano.
          Positioned(
            right: -60,
            top: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(color: Color(0x14FFFFFF), shape: BoxShape.circle),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(MySpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Chip dorado.
                    Container(
                      width: 44,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE6C36A), Color(0xFFB8922F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Container(width: 26, height: 18, decoration: BoxDecoration(
                          border: Border.all(color: const Color(0x55000000)),
                          borderRadius: BorderRadius.circular(3),
                        )),
                      ),
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Icon(Symbols.wifi, color: Colors.white70, size: 22, fill: 1),
                    const Spacer(),
                    Text(
                      marca.etiqueta,
                      style: MyType.headlineSm.copyWith(
                        color: Colors.white,
                        fontStyle: marca == MyMarcaTarjeta.visa ? FontStyle.italic : FontStyle.normal,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    numero,
                    style: MyType.headlineMd.copyWith(
                      color: Colors.white,
                      letterSpacing: 2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TITULAR', style: MyType.labelMd.copyWith(color: Colors.white54, fontSize: 9, letterSpacing: 1.2)),
                          Text(
                            titular.isEmpty ? 'NOMBRE Y APELLIDO' : titular.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MyType.labelLg.copyWith(color: Colors.white, letterSpacing: 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('VENCE', style: MyType.labelMd.copyWith(color: Colors.white54, fontSize: 9, letterSpacing: 1.2)),
                        Text(
                          vencimiento.isEmpty ? 'MM/AA' : vencimiento,
                          style: MyType.labelLg.copyWith(color: Colors.white, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dorso extends StatelessWidget {
  const _Dorso({required this.marca, required this.codigo});

  final MyMarcaTarjeta marca;
  final String codigo;

  @override
  Widget build(BuildContext context) {
    return _Caja(
      marca: marca,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: MySpacing.lg),
          Container(height: 44, color: const Color(0xFF111114)), // banda magnética
          const SizedBox(height: MySpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: MySpacing.xs),
                Container(
                  height: 34,
                  width: 64,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                  child: Center(
                    child: Text(
                      codigo.isEmpty ? '•••' : codigo,
                      style: MyType.labelLg.copyWith(color: Colors.black87, letterSpacing: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: MySpacing.lg, bottom: MySpacing.md),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                marca.etiqueta,
                style: MyType.labelLg.copyWith(color: Colors.white70, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
