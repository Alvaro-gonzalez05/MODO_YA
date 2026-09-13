import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// A3 - Cuenta en revision.
class CuentaEnRevisionPage extends StatelessWidget {
  const CuentaEnRevisionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(MySpacing.screenEdge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: MyColors.primaryFixed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Symbols.hourglass_top,
                        size: 44,
                        color: MyColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: MySpacing.lg),
                  Text(
                    'Tu cuenta esta en revision',
                    style: MyType.headlineLg,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MySpacing.xs),
                  Text(
                    'Estamos validando los datos de tu comercio. Te avisamos '
                    'por notificacion apenas quede activa.',
                    style: MyType.bodyLg.copyWith(color: MyColors.secondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MySpacing.xl),

                  MyCard(
                    child: Column(
                      children: const [
                        _Paso(
                          icon: Symbols.check_circle,
                          titulo: 'Solicitud recibida',
                          detalle: 'Cargaste los datos del comercio',
                          hecho: true,
                        ),
                        Divider(height: MySpacing.xl),
                        _Paso(
                          icon: Symbols.person_search,
                          titulo: 'Validacion administrativa',
                          detalle: 'Revisamos direccion y datos de contacto',
                          hecho: false,
                        ),
                        Divider(height: MySpacing.xl),
                        _Paso(
                          icon: Symbols.rocket_launch,
                          titulo: 'Cuenta activa',
                          detalle: 'Vas a poder pedir cadetes',
                          hecho: false,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: MySpacing.xl),
                  OutlinedButton(
                    onPressed: () => context.goNamed('bienvenida'),
                    child: const Text('Volver al inicio'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({
    required this.icon,
    required this.titulo,
    required this.detalle,
    required this.hecho,
  });

  final IconData icon;
  final String titulo;
  final String detalle;
  final bool hecho;

  @override
  Widget build(BuildContext context) {
    final color = hecho ? MyColors.primary : MyColors.secondary;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: hecho
                ? MyColors.primaryFixed
                : MyColors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 21, color: color, fill: hecho ? 1 : 0),
        ),
        const SizedBox(width: MySpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: MyType.labelLg.copyWith(
                  color: hecho ? MyColors.onSurface : MyColors.secondary,
                ),
              ),
              Text(
                detalle,
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
