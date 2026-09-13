import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// A1 - Bienvenida.
///
/// Ademas del acceso del comercio, en esta etapa expone un atajo al panel de
/// administracion. Cuando entre Supabase Auth el destino lo va a decidir el
/// rol del JWT y este selector se elimina.
class BienvenidaPage extends StatelessWidget {
  const BienvenidaPage({super.key});

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
                  const SizedBox(height: MySpacing.xxl),
                  Center(
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            MyColors.primaryContainer,
                            MyColors.primary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: MyShadows.hero,
                      ),
                      child: const Icon(
                        Symbols.bolt,
                        size: 42,
                        color: MyColors.onPrimary,
                        fill: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: MySpacing.lg),
                  Text(
                    'MODO YA',
                    style: MyType.displayLg,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MySpacing.xs),
                  Text(
                    'Tu ciudad en movimiento',
                    style: MyType.bodyLg.copyWith(color: MyColors.secondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MySpacing.xxl),

                  MyCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedi un cadete cuando lo necesites',
                          style: MyType.headlineSm,
                        ),
                        const SizedBox(height: MySpacing.xs),
                        Text(
                          'Conectamos tu comercio con los cadetes disponibles '
                          'mas cercanos de Malargue. Sin personal propio de '
                          'delivery.',
                          style: MyType.bodyMd
                              .copyWith(color: MyColors.secondary),
                        ),
                        const SizedBox(height: MySpacing.md),
                        const _Punto(
                          icon: Symbols.near_me,
                          texto: 'Buscamos por cercania y disponibilidad',
                        ),
                        const _Punto(
                          icon: Symbols.timer,
                          texto: 'Seguimiento en vivo hasta la entrega',
                        ),
                        const _Punto(
                          icon: Symbols.verified_user,
                          texto: 'Entrega confirmada con codigo',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: MySpacing.xl),
                  FilledButton(
                    onPressed: () => context.goNamed('comercioInicio'),
                    child: const Text('Entrar como comercio'),
                  ),
                  const SizedBox(height: MySpacing.sm),
                  OutlinedButton(
                    onPressed: () => context.goNamed('registro'),
                    child: const Text('Registrar mi comercio'),
                  ),
                  const SizedBox(height: MySpacing.lg),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => context.goNamed('adminDashboard'),
                      icon: const Icon(Symbols.admin_panel_settings, size: 18),
                      label: const Text('Panel de administracion'),
                    ),
                  ),
                  const SizedBox(height: MySpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.icon, required this.texto});

  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: MySpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: MyColors.secondaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: MyColors.primary),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(child: Text(texto, style: MyType.bodyMd)),
        ],
      ),
    );
  }
}
