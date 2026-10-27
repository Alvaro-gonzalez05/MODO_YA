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

  Future<void> _olvide() async {
    final email = await pedirTexto(
      context,
      titulo: '¿Olvidaste tu contraseña?',
      label: 'Tu email',
      aceptar: 'Mandarme el link',
      inicial: _email.text.trim(),
      ayuda: 'Te mandamos un link para elegir una contraseña nueva. '
          'Si tenés un local o sos rider, pedile una nueva a la administración.',
    );
    if (email == null || email.trim().isEmpty || !mounted) return;
    if (AuthRepository.esUsuarioGenerado(email)) {
      // Ese usuario no tiene casilla: el mail no le llegaría a nadie.
      mostrarError(context, 'Ese usuario es de un local o un rider: pedile una contraseña nueva a la administración.');
      return;
    }
    try {
      await ref.read(authRepositoryProvider).recuperarPassword(email);
      if (!mounted) return;
      // Mismo mensaje exista o no la cuenta: decir "no hay ninguna cuenta con
      // ese email" le serviría a cualquiera para averiguar quién usa MODO YA.
      await mostrarExito(
        context,
        titulo: 'Revisá tu email',
        mensaje: 'Si hay una cuenta con ${email.trim()}, te llega un link para elegir una '
            'contraseña nueva. Mirá también en spam.',
        icono: Symbols.mark_email_read,
      );
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
                      label: 'Contraseña',
                      icon: Symbols.lock,
                      ocultar: true,
                      autofill: const [AutofillHints.password],
                      accion: TextInputAction.done,
                      onSubmit: (_) => _entrar(),
                    ),
                    const SizedBox(height: MySpacing.xs),
                    MyBotonAccion(label: 'Entrar', onPressed: _entrar),
                    if (Entorno.correoActivo)
                      TextButton(
                        onPressed: _olvide,
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
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
                  color: MyColors.primaryFixed,
                  borderRadius: BorderRadius.circular(MyRadius.lg),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Symbols.storefront, size: 20, color: MyColors.onPrimaryFixed),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Text(
                        'Tenés un local o sos rider? Tu cuenta te la da la administración '
                        'de MODO YA. Los riders usan la app MODO YA Rider.',
                        style: MyType.bodySm.copyWith(color: MyColors.onPrimaryFixed),
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
