import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/credenciales.dart';

/// Alta de un local o de un rider por la administración.
///
/// Se le pide su **email real**: con eso entra a la app y, si se olvida la
/// contraseña, la recupera solo por mail. Si no tiene (o ya lo usa como
/// cliente), el servidor (Edge Function admin-crear-usuario) le genera un
/// usuario `pizzeria.don.luis@modoya.app`, que no recibe mails: la contraseña
/// nueva se la da la administración desde su ficha. La contraseña siempre sale
/// al azar y se muestra una sola vez.
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
  final _email = TextEditingController();

  Rubro? _rubro;
  LatLng? _ubicacion;
  var _vehiculo = Vehiculo.moto;

  /// Se prende al intentar crear un local sin marcar el mapa, para mostrar el
  /// aviso al lado del botón del mapa.
  var _faltaUbicacion = false;

  String? get _emailReal => _email.text.trim().isEmpty ? null : _email.text.trim().toLowerCase();

  @override
  void dispose() {
    for (final c in [_nombre, _telefono, _calle, _referencia, _email]) {
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
    return '${widget.esLocal ? '' : 'rider.'}$s@modoya.app';
  }

  Future<void> _crear() async {
    // Se validan los dos a la vez: si falta el mapa y también un campo, que se
    // vean los dos avisos y no uno por vez.
    final camposBien = _form.currentState!.validate();
    final faltaUbicacion = widget.esLocal && _ubicacion == null;
    setState(() => _faltaUbicacion = faltaUbicacion);
    if (!camposBien) return;
    if (faltaUbicacion) {
      // En el celular el mapa queda abajo, fuera de la vista: el aviso de al
      // lado no alcanza para enterarse.
      mostrarError(context, 'Marcá en el mapa dónde está el local: sin eso no puede pedir riders.');
      return;
    }

    final repo = ref.read(cuentasRepositoryProvider);
    try {
      final alta = widget.esLocal
          ? await repo.crearComercio(
              email: _emailReal,
              nombre: _nombre.text,
              telefono: _telefono.text,
              calle: _calle.text,
              referencia: _referencia.text,
              rubroId: _rubro?.id,
              lat: _ubicacion!.latitude,
              lng: _ubicacion!.longitude,
            )
          : await repo.crearRepartidor(
              email: _emailReal,
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

    final datos = _Seccion(
      titulo: esLocal ? 'Datos del local' : 'Datos del rider',
      children: [
        MyCampo(
          controller: _nombre,
          label: esLocal ? 'Nombre del local' : 'Nombre y apellido',
          hint: esLocal ? 'Pizzería Don Luis' : 'Juan Pérez',
          icon: esLocal ? Symbols.storefront : Symbols.person,
          onChanged: (_) => setState(() {}),
        ),
        if (esLocal) ...[
          const MyOverline('Rubro'),
          const SizedBox(height: MySpacing.xs),
          DropdownButtonFormField<Rubro>(
            initialValue: _rubro,
            isExpanded: true,
            items: [for (final r in rubros) DropdownMenuItem(value: r, child: Text(r.nombre))],
            onChanged: (r) => setState(() => _rubro = r),
            decoration: const InputDecoration(
              prefixIcon: Icon(Symbols.category, size: 20),
              hintText: 'Elegí un rubro',
            ),
            validator: (r) => r == null ? 'Elegí un rubro' : null,
          ),
          const SizedBox(height: MySpacing.md),
        ],
        MyCampo(
          controller: _telefono,
          label: 'Teléfono / WhatsApp',
          hint: '260 4123456',
          icon: Symbols.call,
          keyboard: TextInputType.phone,
          // Con este número se le mandan los datos de acceso por WhatsApp: si
          // le falta la característica, el mensaje no le llega.
          validar: (t) => t.replaceAll(RegExp(r'\D'), '').length < 8 ? 'Escribilo con la característica: 260 4123456' : null,
        ),
        if (!esLocal) ...[
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
          const SizedBox(height: MySpacing.xs),
          Text(
            'Define qué documentación se le pide.',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
        ],
      ],
    );

    final acceso = _Seccion(
      titulo: 'Acceso',
      bajada: esLocal
          ? 'Con esto entra a MODO YA.'
          : 'Con esto entra a la app MODO YA Rider. Desde su perfil puede cambiar la contraseña.',
      children: [
        MyCampo(
          controller: _email,
          label: 'Email (recomendado)',
          hint: esLocal ? 'pizzeriadonluis@gmail.com' : 'juanperez@gmail.com',
          icon: Symbols.mail,
          keyboard: TextInputType.emailAddress,
          obligatorio: false,
          validar: (t) => t.trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t.trim())
              ? null
              : 'Ese email no es válido',
          onChanged: (_) => setState(() {}),
        ),
        Container(
          padding: const EdgeInsets.all(MySpacing.md),
          decoration: BoxDecoration(
            color: MyColors.secondaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(MyRadius.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Symbols.key, color: MyColors.onSecondaryFixedVariant),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MyOverline(_emailReal != null ? 'Va a entrar con' : 'Sin email: usuario que se va a generar'),
                    const SizedBox(height: 2),
                    Text(_emailReal ?? _usuarioPrevisto, style: MyType.labelLg),
                    Text(
                      _emailReal != null
                          ? 'La contraseña se genera sola y la ves al crear la cuenta. '
                              'Si se la olvida, la recupera sola por mail.'
                          : 'La contraseña se genera sola y la ves al crear la cuenta. '
                              'Este usuario no recibe mails: si se la olvida, se la generás vos desde su ficha.',
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final retiro = !esLocal
        ? null
        : _Seccion(
            titulo: 'Punto de retiro',
            bajada: 'Donde los riders pasan a buscar los pedidos.',
            children: [
              MyCampo(controller: _calle, label: 'Dirección', hint: 'Av. San Martín 420', icon: Symbols.location_on),
              MyCampo(
                controller: _referencia,
                label: 'Referencia (opcional)',
                hint: 'Frente a la plaza',
                icon: Symbols.pin_drop,
                obligatorio: false,
              ),
              const MyOverline('Ubicación en el mapa'),
              const SizedBox(height: MySpacing.xs),
              if (_ubicacion != null) ...[
                MyMapaVista(alto: 200, radio: MyRadius.lg, marcadores: [MyMarcador(punto: _ubicacion!, icono: Symbols.storefront)]),
                const SizedBox(height: MySpacing.sm),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: MyBoton(
                  label: _ubicacion == null ? 'Marcar en el mapa' : 'Cambiar ubicación',
                  icon: _ubicacion == null ? Symbols.add_location : Symbols.edit_location,
                  tipo: _ubicacion == null ? MyBotonTipo.oscuro : MyBotonTipo.secundario,
                  onPressed: () async {
                    final p = await MyMapa.elegirPunto(context, inicial: _ubicacion, titulo: 'Ubicación del local');
                    if (p != null) {
                      setState(() {
                        _ubicacion = p;
                        _faltaUbicacion = false;
                      });
                    }
                  },
                ),
              ),
              // Al lado del botón, como el resto de los campos: antes solo
              // salía un aviso flotante que se iba solo.
              if (_faltaUbicacion) ...[
                const SizedBox(height: MySpacing.xs),
                Text(
                  'Marcá dónde está el local: sin eso no puede pedir riders.',
                  style: MyType.bodySm.copyWith(color: MyColors.error),
                ),
              ],
            ],
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
            ?retiro,
            if (retiro != null) const SizedBox(height: MySpacing.md),
            acceso,
            const SizedBox(height: MySpacing.xl),
            boton,
          ] else ...[
            // A la izquierda quién es y cómo entra; a la derecha, si es un
            // local, dónde está: el mapa necesita el alto de una columna.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      datos,
                      if (retiro != null) ...[
                        const SizedBox(height: MySpacing.lg),
                        acceso,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: MySpacing.lg),
                Expanded(child: retiro ?? acceso),
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

/// Un grupo del formulario: tarjeta con título, bajada opcional y sus campos.
class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.children, this.bajada});

  final String titulo;
  final String? bajada;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: MyType.headlineSm),
          if (bajada != null) ...[
            const SizedBox(height: MySpacing.xxs),
            Text(bajada!, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
          ],
          const SizedBox(height: MySpacing.md),
          ...children,
        ],
      ),
    );
  }
}
