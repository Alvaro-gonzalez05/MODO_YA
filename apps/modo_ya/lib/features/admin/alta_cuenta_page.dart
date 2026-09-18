import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/credenciales.dart';

/// Alta de un local o de un rider por la administración.
///
/// El usuario y la contraseña los genera el servidor (Edge Function
/// admin-crear-usuario): pizzeria.don.luis@modoya.com y una contraseña al
/// azar, que se muestra una sola vez. Así el dueño del local o el rider
/// conserva su email personal para registrarse como cliente si quiere.
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
  final _calle = TextEditingController();
  final _referencia = TextEditingController();

  Rubro? _rubro;
  LatLng? _ubicacion;
  var _vehiculo = Vehiculo.moto;

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _calle, _referencia]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Vista previa del usuario. La definitiva la arma el servidor, que además
  /// le suma un número si ya existe.
  String get _usuarioPrevisto {
    const acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    var s = _nombre.text.toLowerCase();
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '.').replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (s.isEmpty) s = widget.esLocal ? 'nombre.del.local' : 'nombre.apellido';
    return '${widget.esLocal ? '' : 'rider.'}$s@modoya.com';
  }

  Future<void> _crear() async {
    if (!_form.currentState!.validate()) return;
    if (widget.esLocal && _ubicacion == null) {
      mostrarError(context, 'Marcá en el mapa dónde está el local: sin eso no puede pedir riders.');
      return;
    }

    final repo = ref.read(cuentasRepositoryProvider);
    try {
      final alta = widget.esLocal
          ? await repo.crearComercio(
              nombre: _nombre.text,
              telefono: _telefono.text,
              calle: _calle.text,
              referencia: _referencia.text,
              rubroId: _rubro?.id,
              lat: _ubicacion!.latitude,
              lng: _ubicacion!.longitude,
            )
          : await repo.crearRepartidor(
              nombre: _nombre.text,
              telefono: _telefono.text,
              vehiculo: _vehiculo,
            );

      ref.invalidate(todosLosComerciosProvider);
      ref.invalidate(todosLosRepartidoresProvider);
      if (!mounted) return;
      await mostrarCredenciales(
        context,
        titulo: widget.esLocal ? 'Local creado' : 'Rider creado',
        alta: alta,
        esRider: !widget.esLocal,
        telefono: _telefono.text,
      );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rubros = ref.watch(rubrosProvider).value ?? const <Rubro>[];
    final esLocal = widget.esLocal;

    final datos = MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(esLocal ? 'Datos del local' : 'Datos del rider', style: MyType.headlineSm),
          const SizedBox(height: MySpacing.md),
          MyCampo(
            controller: _nombre,
            label: esLocal ? 'Nombre del local' : 'Nombre y apellido',
            hint: esLocal ? 'Pizzería Don Luis' : 'Juan Pérez',
            icon: esLocal ? Symbols.storefront : Symbols.person,
            onChanged: (_) => setState(() {}),
          ),
          MyCampo(
            controller: _telefono,
            label: 'Teléfono / WhatsApp',
            hint: '260 4123456',
            icon: Symbols.call,
            keyboard: TextInputType.phone,
          ),
          if (esLocal) ...[
            const MyOverline('Rubro'),
            const SizedBox(height: MySpacing.xs),
            DropdownButtonFormField<Rubro>(
              initialValue: _rubro,
              items: [for (final r in rubros) DropdownMenuItem(value: r, child: Text(r.nombre))],
              onChanged: (r) => setState(() => _rubro = r),
              decoration: const InputDecoration(
                prefixIcon: Icon(Symbols.category, size: 20),
                hintText: 'Elegí un rubro',
              ),
              validator: (r) => r == null ? 'Elegí un rubro' : null,
            ),
          ] else ...[
            const MyOverline('Vehículo'),
            const SizedBox(height: MySpacing.xs),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (final v in Vehiculo.values)
                  MyChip(v.label, selected: v == _vehiculo, onTap: () => setState(() => _vehiculo = v)),
              ],
            ),
          ],
          const SizedBox(height: MySpacing.lg),
          Container(
            padding: const EdgeInsets.all(MySpacing.md),
            decoration: BoxDecoration(
              color: MyColors.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(MyRadius.lg),
            ),
            child: Row(
              children: [
                Icon(Symbols.key, color: MyColors.onSecondaryFixedVariant),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MyOverline('Usuario que se va a generar'),
                      const SizedBox(height: 2),
                      Text(_usuarioPrevisto, style: MyType.labelLg),
                      Text(
                        'La contraseña se genera sola y la ves al crear la cuenta.',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final Widget segundo = esLocal
        ? MyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Punto de retiro', style: MyType.headlineSm),
                const SizedBox(height: MySpacing.xxs),
                Text('Donde los riders pasan a buscar los pedidos.', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                const SizedBox(height: MySpacing.md),
                MyCampo(controller: _calle, label: 'Dirección', hint: 'Av. San Martín 420', icon: Symbols.location_on),
                MyCampo(
                  controller: _referencia,
                  label: 'Referencia (opcional)',
                  hint: 'Frente a la plaza',
                  icon: Symbols.pin_drop,
                  obligatorio: false,
                ),
                if (_ubicacion != null) ...[
                  MyMapaVista(alto: 200, radio: MyRadius.lg, marcadores: [MyMarcador(punto: _ubicacion!, icono: Symbols.storefront)]),
                  const SizedBox(height: MySpacing.sm),
                ],
                MyBoton(
                  label: _ubicacion == null ? 'Marcar en el mapa' : 'Cambiar ubicación',
                  icon: _ubicacion == null ? Symbols.add_location : Symbols.edit_location,
                  tipo: _ubicacion == null ? MyBotonTipo.oscuro : MyBotonTipo.secundario,
                  onPressed: () async {
                    final p = await MyMapa.elegirPunto(context, inicial: _ubicacion, titulo: 'Ubicación del local');
                    if (p != null) setState(() => _ubicacion = p);
                  },
                ),
              ],
            ),
          )
        : MyCard(
            color: MyColors.dock,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Symbols.install_mobile, color: MyColors.primary, size: 32),
                const SizedBox(height: MySpacing.sm),
                Text('App MODO YA Rider', style: MyType.headlineSm.copyWith(color: Colors.white)),
                const SizedBox(height: MySpacing.xs),
                Text(
                  'El rider entra con el usuario y la contraseña que se generan acá. '
                  'Desde su perfil puede cambiar la contraseña.',
                  style: MyType.bodyMd.copyWith(color: const Color(0xFFB8B8C0)),
                ),
              ],
            ),
          );

    final boton = MyBotonAccion(
      label: esLocal ? 'Crear local' : 'Crear rider',
      icon: Symbols.person_add,
      onPressed: _crear,
    );

    return Form(
      key: _form,
      child: MyPagina(
        volver: () => context.pop(),
        rotulo: esLocal ? 'Locales' : 'Riders',
        titulo: esLocal ? 'Nuevo local' : 'Nuevo rider',
        bajada: 'La cuenta queda aprobada y lista para usar',
        anchoMaximo: 1080,
        conDock: false,
        children: [
          if (context.esMovil) ...[
            datos,
            const SizedBox(height: MySpacing.md),
            segundo,
            const SizedBox(height: MySpacing.xl),
            boton,
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: datos),
                const SizedBox(width: MySpacing.lg),
                Expanded(child: segundo),
              ],
            ),
            const SizedBox(height: MySpacing.xl),
            Align(alignment: Alignment.centerRight, child: SizedBox(width: 320, child: boton)),
          ],
        ],
      ),
    );
  }
}
