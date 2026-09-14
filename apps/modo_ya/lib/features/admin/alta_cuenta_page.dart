import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';

/// Alta de un local o de un rider por la administracion.
///
/// La cuenta se crea en el servidor (Edge Function admin-crear-usuario) con una
/// contrasena temporal que se muestra UNA sola vez para pasarsela al local o al
/// rider. No queda guardada en ningun lado.
class AltaCuentaPage extends ConsumerStatefulWidget {
  const AltaCuentaPage({super.key, required this.esLocal});

  final bool esLocal;

  @override
  ConsumerState<AltaCuentaPage> createState() => _AltaCuentaPageState();
}

class _AltaCuentaPageState extends ConsumerState<AltaCuentaPage> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _email = TextEditingController();
  final _calle = TextEditingController();
  final _referencia = TextEditingController();

  Rubro? _rubro;
  LatLng? _ubicacion;
  var _vehiculo = Vehiculo.moto;

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _email, _calle, _referencia]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_form.currentState!.validate()) return;
    if (widget.esLocal && _ubicacion == null) {
      mostrarError(context, 'Marca en el mapa donde esta el local: sin eso no puede pedir riders.');
      return;
    }

    final repo = ref.read(cuentasRepositoryProvider);
    try {
      final alta = widget.esLocal
          ? await repo.crearComercio(
              email: _email.text,
              nombre: _nombre.text,
              telefono: _telefono.text,
              calle: _calle.text,
              referencia: _referencia.text,
              rubroId: _rubro?.id,
              lat: _ubicacion!.latitude,
              lng: _ubicacion!.longitude,
            )
          : await repo.crearRepartidor(
              email: _email.text,
              nombre: _nombre.text,
              telefono: _telefono.text,
              vehiculo: _vehiculo,
            );

      ref.invalidate(todosLosComerciosProvider);
      if (!mounted) return;
      await _mostrarCredenciales(alta);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _mostrarCredenciales(AltaCuenta alta) {
    final texto = 'MODO YA${widget.esLocal ? '' : ' Rider'}\n'
        'Usuario: ${alta.email}\n'
        'Contrasena: ${alta.passwordTemporal}';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Symbols.check_circle, color: MyColors.success, size: 40),
        title: Text(widget.esLocal ? 'Local creado' : 'Rider creado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pasale estos datos. La contrasena se muestra una sola vez: '
              'anotala o copiala ahora.',
              style: MyType.bodyMd,
            ),
            const SizedBox(height: MySpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MySpacing.md),
              decoration: BoxDecoration(
                color: MyColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(MyRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MyOverline('Usuario'),
                  SelectableText(alta.email, style: MyType.labelLg),
                  const SizedBox(height: MySpacing.sm),
                  const MyOverline('Contrasena temporal'),
                  SelectableText(
                    alta.passwordTemporal ?? '(la que cargaste)',
                    style: MyType.headlineMd.copyWith(color: MyColors.primary, letterSpacing: 1),
                  ),
                ],
              ),
            ),
            if (!widget.esLocal) ...[
              const SizedBox(height: MySpacing.sm),
              Text(
                'El rider entra con estos datos en la app MODO YA Rider.',
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texto));
              if (c.mounted) mostrarAviso(c, 'Copiado');
            },
            icon: const Icon(Symbols.content_copy, size: 18),
            label: const Text('Copiar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Listo')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rubros = ref.watch(rubrosProvider).value ?? const <Rubro>[];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Symbols.arrow_back), onPressed: () => context.pop()),
        title: Text(widget.esLocal ? 'Nuevo local' : 'Nuevo rider'),
      ),
      body: Form(
        key: _form,
        child: FormularioCentrado(
          ancho: 560,
          children: [
            MyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.esLocal ? 'Datos del local' : 'Datos del rider', style: MyType.headlineSm),
                  const SizedBox(height: MySpacing.md),
                  MyCampo(
                    controller: _nombre,
                    label: widget.esLocal ? 'Nombre del local' : 'Nombre y apellido',
                    icon: widget.esLocal ? Symbols.storefront : Symbols.person,
                  ),
                  MyCampo(
                    controller: _telefono,
                    label: 'Telefono',
                    icon: Symbols.call,
                    keyboard: TextInputType.phone,
                  ),
                  MyCampo(
                    controller: _email,
                    label: 'Email (va a ser su usuario)',
                    icon: Symbols.mail,
                    keyboard: TextInputType.emailAddress,
                    validar: (t) =>
                        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t) ? null : 'Ese email no es valido',
                  ),
                  if (widget.esLocal) ...[
                    const MyOverline('Rubro'),
                    const SizedBox(height: MySpacing.xs),
                    DropdownButtonFormField<Rubro>(
                      initialValue: _rubro,
                      items: [
                        for (final r in rubros) DropdownMenuItem(value: r, child: Text(r.nombre)),
                      ],
                      onChanged: (r) => setState(() => _rubro = r),
                      decoration: const InputDecoration(prefixIcon: Icon(Symbols.category, size: 20)),
                      validator: (r) => r == null ? 'Elegi un rubro' : null,
                    ),
                    const SizedBox(height: MySpacing.md),
                  ] else ...[
                    const MyOverline('Vehiculo'),
                    const SizedBox(height: MySpacing.xs),
                    Wrap(
                      spacing: MySpacing.xs,
                      children: [
                        for (final v in Vehiculo.values)
                          MyChip(v.label, selected: v == _vehiculo, onTap: () => setState(() => _vehiculo = v)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (widget.esLocal) ...[
              const SizedBox(height: MySpacing.md),
              MyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Punto de retiro', style: MyType.headlineSm),
                    const SizedBox(height: MySpacing.xxs),
                    Text(
                      'Donde los riders pasan a buscar los pedidos.',
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                    const SizedBox(height: MySpacing.md),
                    MyCampo(controller: _calle, label: 'Direccion', hint: 'Av. Roca 420', icon: Symbols.location_on),
                    MyCampo(
                      controller: _referencia,
                      label: 'Referencia (opcional)',
                      hint: 'Frente a la plaza',
                      icon: Symbols.pin_drop,
                      obligatorio: false,
                    ),
                    if (_ubicacion != null) ...[
                      MyMapaVista(
                        alto: 160,
                        marcadores: [MyMarcador(punto: _ubicacion!, icono: Symbols.storefront)],
                      ),
                      const SizedBox(height: MySpacing.sm),
                    ],
                    OutlinedButton.icon(
                      onPressed: () async {
                        final p = await MyMapa.elegirPunto(
                          context,
                          inicial: _ubicacion,
                          titulo: 'Ubicacion del local',
                        );
                        if (p != null) setState(() => _ubicacion = p);
                      },
                      icon: Icon(_ubicacion == null ? Symbols.add_location : Symbols.edit_location, size: 20),
                      label: Text(_ubicacion == null ? 'Marcar en el mapa' : 'Cambiar ubicacion'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: MySpacing.xl),
            MyBotonAccion(
              label: widget.esLocal ? 'Crear local' : 'Crear rider',
              icon: Symbols.person_add,
              onPressed: _crear,
            ),
            const SizedBox(height: MySpacing.md),
            Text(
              'La cuenta queda aprobada y lista para usar. Se genera una contrasena '
              'temporal; conviene pedirle que la cambie la primera vez que entre.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
