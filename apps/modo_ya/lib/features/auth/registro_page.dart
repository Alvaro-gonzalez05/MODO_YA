import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';

/// Registro de clientes. Locales y riders no se registran solos: los da de
/// alta la administracion.
class RegistroPage extends ConsumerStatefulWidget {
  const RegistroPage({super.key});

  @override
  ConsumerState<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends ConsumerState<RegistroPage> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repetir = TextEditingController();

  /// Lo ultimo que salio mal, arriba del boton. El aviso flotante se iba solo
  /// a los tres segundos y aparecia en el borde de arriba de la pantalla:
  /// quien tocaba "Crear cuenta" al pie del formulario no llegaba a verlo y
  /// quedaba convencido de que el boton no hacia nada.
  String? _error;

  /// Hasta el primer intento no se marca nada en rojo: molesta que el campo se
  /// queje mientras todavia se esta escribiendo.
  var _autovalidar = AutovalidateMode.disabled;

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _email, _password, _repetir]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registrar() async {
    setState(() => _autovalidar = AutovalidateMode.onUserInteraction);
    final form = _form.currentState;
    if (form == null || !form.validate()) {
      // Los campos ya se marcan en rojo, pero el que tocó el botón mira el
      // botón: sin esta línea parece que no pasó nada.
      setState(() => _error = 'Revisá los datos marcados en rojo y volvé a intentar.');
      return;
    }
    setState(() => _error = null);
    try {
      final entro = await ref.read(authRepositoryProvider).registrarCliente(
            nombre: _nombre.text,
            telefono: _telefono.text,
            email: _email.text,
            password: _password.text,
          );
      if (!mounted || entro) return;

      // El proyecto pide confirmar el email antes de la primera entrada.
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Revisá tu email'),
          content: Text(
            'Te mandamos un mail a ${_email.text.trim()} para confirmar la cuenta. '
            'Después de confirmarla vas a poder entrar.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
        ),
      );
      if (mounted) context.go('/entrar');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => context.go('/entrar'),
        ),
      ),
      body: Form(
        key: _form,
        autovalidateMode: _autovalidar,
        child: AutofillGroup(
          child: FormularioCentrado(
            children: [
              const MarcaGrande(bajada: 'Crea tu cuenta y pedi lo que quieras'),
              const SizedBox(height: MySpacing.xl),
              MyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MyCampo(
                      controller: _nombre,
                      label: 'Nombre y apellido',
                      icon: Symbols.person,
                      autofill: const [AutofillHints.name],
                    ),
                    MyCampo(
                      controller: _telefono,
                      label: 'Teléfono',
                      hint: '260 ...',
                      icon: Symbols.call,
                      keyboard: TextInputType.phone,
                      autofill: const [AutofillHints.telephoneNumber],
                      validar: (t) => t.replaceAll(RegExp(r'\D'), '').length < 8
                          ? 'Pone un teléfono donde te puedan llamar'
                          : null,
                    ),
                    MyCampo(
                      controller: _email,
                      label: 'Email',
                      icon: Symbols.mail,
                      keyboard: TextInputType.emailAddress,
                      autofill: const [AutofillHints.email],
                      validar: (t) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t)
                          ? null
                          : 'Ese email no es válido',
                    ),
                    MyCampo(
                      controller: _password,
                      label: 'Contraseña',
                      icon: Symbols.lock,
                      ocultar: true,
                      autofill: const [AutofillHints.newPassword],
                      validar: (t) => t.length < 8 ? 'Mínimo 8 caracteres' : null,
                    ),
                    MyCampo(
                      controller: _repetir,
                      label: 'Repetí la contraseña',
                      icon: Symbols.lock,
                      ocultar: true,
                      validar: (t) => t != _password.text ? 'No coincide' : null,
                    ),
                    if (_error != null) ...[
                      MyCard(
                        color: MyColors.errorContainer,
                        shadows: const [],
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Symbols.error, color: MyColors.error),
                            const SizedBox(width: MySpacing.sm),
                            Expanded(
                              child: Text(
                                _error!,
                                style: MyType.bodyMd.copyWith(color: MyColors.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: MySpacing.md),
                    ],
                    const SizedBox(height: MySpacing.xs),
                    MyBotonAccion(label: 'Crear cuenta', onPressed: _registrar),
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
