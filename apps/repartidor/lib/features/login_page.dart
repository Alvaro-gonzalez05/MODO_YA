import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Entrada de riders. Las cuentas las crea la administracion: no hay registro.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    try {
      await ref.read(authRepositoryProvider).entrar(_email.text, _password.text);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    final noEsRider = sesion.rol != null && sesion.rol != RolUsuario.repartidor;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(MySpacing.screenEdge),
                children: [
                  const Center(child: MyLogoMark(size: 96, variant: MyLogoVariant.riders)),
                  const SizedBox(height: MySpacing.md),
                  Text('MODO YA Rider', style: MyType.displayLg, textAlign: TextAlign.center),
                  Text('Conectate y empeza a ganar',
                      style: MyType.bodyLg.copyWith(color: MyColors.secondary), textAlign: TextAlign.center),
                  const SizedBox(height: MySpacing.xl),
                  if (noEsRider) ...[
                    MyCard(
                      color: MyColors.errorContainer,
                      shadows: const [],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Esta app es solo para riders', style: MyType.headlineSm),
                          const SizedBox(height: MySpacing.xxs),
                          Text(
                            'Entraste con una cuenta de ${sesion.rol == RolUsuario.comercio ? 'local' : sesion.rol == RolUsuario.admin ? 'administracion' : 'cliente'}. '
                            'Usa la app MODO YA.',
                            style: MyType.bodySm,
                          ),
                          const SizedBox(height: MySpacing.sm),
                          OutlinedButton(
                            onPressed: () => ref.read(authRepositoryProvider).salir(),
                            child: const Text('Cerrar sesión'),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    MyCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          MyCampo(
                            controller: _email,
                            label: 'Email',
                            icon: Symbols.mail,
                            keyboard: TextInputType.emailAddress,
                          ),
                          MyCampo(
                            controller: _password,
                            label: 'Contraseña',
                            icon: Symbols.lock,
                            ocultar: true,
                            onSubmit: (_) => _entrar(),
                          ),
                          MyBotonAccion(label: 'Entrar', onPressed: _entrar),
                        ],
                      ),
                    ),
                  const SizedBox(height: MySpacing.lg),
                  Text(
                    'Querés ser rider? Tu cuenta te la da la administración de MODO YA.',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    textAlign: TextAlign.center,
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
