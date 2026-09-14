import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';

/// Entrada unica para clientes, locales y administracion. A donde lleva cada
/// uno lo decide el router segun el rol de la cuenta.
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
      // No hace falta navegar: el router escucha la sesion y redirige.
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(
        key: _form,
        child: AutofillGroup(
          child: FormularioCentrado(
            children: [
              const SizedBox(height: MySpacing.xl),
              const MarcaGrande(),
              const SizedBox(height: MySpacing.xxl),
              MyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Entrar', style: MyType.headlineMd),
                    const SizedBox(height: MySpacing.lg),
                    MyCampo(
                      controller: _email,
                      label: 'Email',
                      hint: 'tu@email.com',
                      icon: Symbols.mail,
                      keyboard: TextInputType.emailAddress,
                      autofill: const [AutofillHints.email],
                      accion: TextInputAction.next,
                    ),
                    MyCampo(
                      controller: _password,
                      label: 'Contrasena',
                      icon: Symbols.lock,
                      ocultar: true,
                      autofill: const [AutofillHints.password],
                      accion: TextInputAction.done,
                      onSubmit: (_) => _entrar(),
                    ),
                    const SizedBox(height: MySpacing.xs),
                    MyBotonAccion(label: 'Entrar', onPressed: _entrar),
                  ],
                ),
              ),
              const SizedBox(height: MySpacing.lg),
              OutlinedButton(
                onPressed: () => context.go('/registro'),
                child: const Text('Crear una cuenta para pedir'),
              ),
              const SizedBox(height: MySpacing.lg),
              Container(
                padding: const EdgeInsets.all(MySpacing.md),
                decoration: BoxDecoration(
                  color: MyColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(MyRadius.lg),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Symbols.storefront, size: 20, color: MyColors.secondary),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Text(
                        'Tenes un local o sos rider? Tu cuenta te la da la administracion '
                        'de MODO YA. Los riders usan la app MODO YA Rider.',
                        style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
