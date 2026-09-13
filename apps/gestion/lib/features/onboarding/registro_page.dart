import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_ui/my_ui.dart';

/// A2 - Registro del comercio.
///
/// La cuenta queda sujeta a aprobacion de la administracion: al enviar no se
/// entra al panel sino a [CuentaEnRevisionPage].
class RegistroComercioPage extends StatefulWidget {
  const RegistroComercioPage({super.key});

  @override
  State<RegistroComercioPage> createState() => _RegistroComercioPageState();
}

class _RegistroComercioPageState extends State<RegistroComercioPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _rubro = TextEditingController();
  final _direccion = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();

  var _enviando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _rubro.dispose();
    _direccion.dispose();
    _telefono.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enviando = true);
    // TODO(supabase): crear el usuario y la fila en `comercios` con estado
    // pendiente. Por ahora solo avanzamos la pantalla.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.goNamed('revision');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          onPressed: () => context.goNamed('bienvenida'),
        ),
        title: const Text('Registrar comercio'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(MySpacing.screenEdge),
                children: [
                  Text(
                    'Contanos de tu negocio',
                    style: MyType.headlineLg,
                  ),
                  const SizedBox(height: MySpacing.xs),
                  Text(
                    'Revisamos los datos y activamos tu cuenta. Suele demorar '
                    'menos de 24 horas habiles.',
                    style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                  ),
                  const SizedBox(height: MySpacing.xl),

                  _Campo(
                    controller: _nombre,
                    label: 'Nombre del comercio',
                    hint: 'Pizzeria Don Luis',
                    icon: Symbols.storefront,
                  ),
                  _Campo(
                    controller: _rubro,
                    label: 'Rubro',
                    hint: 'Pizzeria, farmacia, kiosco...',
                    icon: Symbols.category,
                  ),
                  _Campo(
                    controller: _direccion,
                    label: 'Direccion de retiro',
                    hint: 'Av. Roca 420',
                    icon: Symbols.location_on,
                  ),
                  _Campo(
                    controller: _telefono,
                    label: 'Telefono',
                    hint: '+54 260 ...',
                    icon: Symbols.call,
                    keyboard: TextInputType.phone,
                  ),
                  _Campo(
                    controller: _email,
                    label: 'Email',
                    hint: 'contacto@micomercio.com',
                    icon: Symbols.mail,
                    keyboard: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: MySpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(MySpacing.md),
                    decoration: BoxDecoration(
                      color: MyColors.secondaryContainer,
                      borderRadius: BorderRadius.circular(MyRadius.lg),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Symbols.info, size: 20,
                            color: MyColors.secondary),
                        const SizedBox(width: MySpacing.sm),
                        Expanded(
                          child: Text(
                            'Despues del alta vas a poder marcar en el mapa el '
                            'punto exacto de retiro.',
                            style: MyType.bodySm
                                .copyWith(color: MyColors.onSecondaryFixed),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: MySpacing.xl),
                  FilledButton(
                    onPressed: _enviando ? null : _enviar,
                    child: _enviando
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: MyColors.onPrimary,
                            ),
                          )
                        : const Text('Enviar solicitud'),
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

class _Campo extends StatelessWidget {
  const _Campo({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboard,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboard;

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
            keyboardType: keyboard,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 20, color: MyColors.outline),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Completa este dato' : null,
          ),
        ],
      ),
    );
  }
}
