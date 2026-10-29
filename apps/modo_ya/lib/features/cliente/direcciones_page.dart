import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';
import 'carrito.dart';

/// Los nombres que se ofrecen para guardar una dirección. Lo demás va en
/// "Otro", con el nombre que quiera.
const aliasSugeridos = ['Casa', 'Trabajo'];

/// Icono de una dirección según su nombre: la casa, el trabajo o un pin.
IconData iconoDeAlias(String alias) => switch (alias.trim().toLowerCase()) {
      'casa' => Symbols.home,
      'trabajo' => Symbols.work,
      _ => Symbols.location_on,
    };

/// Elegir a dónde se lleva el pedido sin salir de la pantalla: en la compu un
/// panel al costado, en el celular una hoja desde abajo.
///
/// Antes "Cambiar" llevaba a "Mis direcciones" y había que volver al carrito a
/// mano; para elegir entre las que ya están guardadas no hace falta el salto.
Future<void> mostrarElegirDireccion(BuildContext context) {
  return mostrarHojaLateral(
    context,
    titulo: 'Entregar en',
    builder: (_) => _ElegirDireccion(onAdministrar: () => context.go('/cliente/direcciones')),
  );
}

class _ElegirDireccion extends ConsumerWidget {
  const _ElegirDireccion({required this.onAdministrar});

  final VoidCallback onAdministrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(direccionesProvider).value ?? const <DireccionCliente>[];
    final elegida = ref.watch(direccionElegidaProvider);

    void cerrarY(VoidCallback accion) {
      Navigator.of(context).pop();
      accion();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿A dónde te lo llevamos?', style: MyType.headlineMd),
        const SizedBox(height: MySpacing.md),
        if (lista.isEmpty)
          Text('Todavía no guardaste ninguna dirección.', style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
        for (final d in lista) ...[
          _FilaDireccion(
            direccion: d,
            elegida: d.id == elegida,
            onTap: () => cerrarY(() => ref.read(direccionElegidaProvider.notifier).elegir(d.id)),
          ),
          const SizedBox(height: MySpacing.xs),
        ],
        const SizedBox(height: MySpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: MyBoton(
            label: lista.isEmpty ? 'Agregar dirección' : 'Agregar o editar direcciones',
            icon: Symbols.add_location,
            tipo: MyBotonTipo.secundario,
            onPressed: () => cerrarY(onAdministrar),
          ),
        ),
      ],
    );
  }
}

/// Una dirección guardada como opción tocable, marcada si es la elegida.
class _FilaDireccion extends StatelessWidget {
  const _FilaDireccion({required this.direccion, required this.elegida, required this.onTap, this.menu});

  final DireccionCliente direccion;
  final bool elegida;
  final VoidCallback onTap;

  /// El menú de "Hacer principal" y "Borrar", solo en "Mis direcciones".
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final d = direccion;
    return MyCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(MySpacing.md, MySpacing.sm, MySpacing.xs, MySpacing.sm),
      color: elegida ? MyColors.primaryFixed : null,
      child: Row(
        children: [
          MyIconoCaja(
            iconoDeAlias(d.alias),
            tamano: 40,
            circular: true,
            fondo: elegida ? MyColors.primary : MyColors.secondaryContainer,
            color: elegida ? MyColors.onPrimary : MyColors.onSurface,
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(d.alias, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (d.predeterminada) ...[
                      const SizedBox(width: MySpacing.xs),
                      const MyBadge('Principal', tone: MyBadgeTone.info),
                    ],
                  ],
                ),
                Text(d.calle, style: MyType.bodyMd, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (d.referencia != null)
                  Text(
                    d.referencia!,
                    style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (menu != null)
            menu!
          else
            Padding(
              padding: const EdgeInsets.only(right: MySpacing.xs),
              child: Icon(
                elegida ? Symbols.radio_button_checked : Symbols.radio_button_unchecked,
                color: elegida ? MyColors.onPrimaryFixed : MyColors.outline,
              ),
            ),
        ],
      ),
    );
  }
}

/// Direcciones del cliente. Se marca el pin en el mapa: en Malargüe la
/// numeración no siempre alcanza para encontrar una casa.
class DireccionesPage extends ConsumerWidget {
  const DireccionesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final direcciones = ref.watch(direccionesProvider);
    final elegida = ref.watch(direccionElegidaProvider);

    return MyPantallaClara(
      child: MyPagina(
        volver: () => context.canPop() ? context.pop() : context.go('/cliente'),
        rotulo: 'Entrega',
        titulo: 'Mis direcciones',
        bajada: 'Tocá una para usarla en tus pedidos',
        anchoMaximo: 760,
        conDock: false,
        children: [
          MyAsync(
            valor: direcciones,
            onReintentar: () => ref.invalidate(direccionesProvider),
            datos: (lista) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (lista.isEmpty)
                  const MyEmptyState(
                    icon: Symbols.home_pin,
                    title: 'Todavía no guardaste direcciones',
                    message: 'Agregá a dónde querés que te llevemos los pedidos.',
                  ),
                for (final d in lista) ...[
                  _FilaDireccion(
                    direccion: d,
                    elegida: d.id == elegida,
                    onTap: () {
                      ref.read(direccionElegidaProvider.notifier).elegir(d.id);
                      if (context.canPop()) context.pop();
                    },
                    menu: PopupMenuButton<int>(
                      icon: const Icon(Symbols.more_vert),
                      tooltip: 'Más opciones',
                      onSelected: (v) async {
                        try {
                          if (v == 0) {
                            await ref.read(direccionesRepositoryProvider).hacerPredeterminada(d.id);
                          } else {
                            final ok = await confirmar(
                              context,
                              titulo: 'Borrar dirección',
                              mensaje: d.calle,
                              aceptar: 'Borrar',
                              peligroso: true,
                            );
                            if (!ok) return;
                            await ref.read(direccionesRepositoryProvider).borrar(d.id);
                          }
                          ref.invalidate(direccionesProvider);
                        } catch (e) {
                          if (context.mounted) mostrarError(context, e);
                        }
                      },
                      itemBuilder: (_) => [
                        if (!d.predeterminada) const PopupMenuItem(value: 0, child: Text('Hacer principal')),
                        const PopupMenuItem(value: 1, child: Text('Borrar')),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.sm),
                ],
                const SizedBox(height: MySpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: MyBoton(
                    onPressed: () => _nueva(context, ref, esPrimera: lista.isEmpty),
                    icon: Symbols.add_location,
                    label: 'Agregar dirección',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _nueva(BuildContext context, WidgetRef ref, {required bool esPrimera}) async {
    final punto = await MyMapa.elegirPunto(
      context,
      titulo: 'Dónde te llevamos el pedido',
      ayuda: 'Mové el mapa hasta que el pin quede sobre tu puerta.',
    );
    if (punto == null || !context.mounted) return;

    await mostrarFormularioEmergente(
      context,
      titulo: 'Datos de la dirección',
      builder: (hoja) => FormularioDireccion(
        punto: punto,
        aliasInicial: esPrimera ? 'Casa' : null,
        onGuardar: (datos) async {
          try {
            final id = await ref.read(direccionesRepositoryProvider).agregar(
                  alias: datos.alias,
                  calle: datos.calle,
                  referencia: datos.referencia,
                  lat: punto.latitude,
                  lng: punto.longitude,
                );
            ref.invalidate(direccionesProvider);
            ref.read(direccionElegidaProvider.notifier).elegir(id);
            if (hoja.mounted) Navigator.pop(hoja);
          } catch (e) {
            if (hoja.mounted) mostrarError(hoja, e);
          }
        },
      ),
    );
  }
}

/// Lo que se carga de una dirección nueva.
typedef DatosDireccion = ({String alias, String calle, String referencia});

/// Calle, referencia y cómo guardarla, con el pin ya marcado.
///
/// Es un widget con estado (y no controladores sueltos en la función que lo
/// abre) para que los campos vivan hasta que la hoja termine de cerrarse:
/// liberarlos apenas vuelve `mostrarFormularioEmergente` rompe la animación
/// de salida.
class FormularioDireccion extends StatefulWidget {
  const FormularioDireccion({super.key, required this.punto, required this.onGuardar, this.aliasInicial});

  final LatLng punto;
  final Future<void> Function(DatosDireccion datos) onGuardar;

  /// "Casa" para la primera: casi siempre lo es y es un toque menos.
  final String? aliasInicial;

  @override
  State<FormularioDireccion> createState() => _FormularioDireccionState();
}

class _FormularioDireccionState extends State<FormularioDireccion> {
  final _form = GlobalKey<FormState>();
  final _calle = TextEditingController();
  final _referencia = TextEditingController();
  final _otro = TextEditingController();

  /// Casa, Trabajo u "Otro" (null: todavía no eligió).
  late String? _alias = widget.aliasInicial;
  var _faltaAlias = false;

  static const _otroAlias = 'Otro';

  @override
  void dispose() {
    _calle.dispose();
    _referencia.dispose();
    _otro.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final formOk = _form.currentState!.validate();
    setState(() => _faltaAlias = _alias == null);
    if (!formOk || _alias == null) return;
    await widget.onGuardar((
      alias: _alias == _otroAlias ? _otro.text.trim() : _alias!,
      calle: _calle.text,
      referencia: _referencia.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyMapaVista(alto: 120, marcadores: [MyMarcador(punto: widget.punto, icono: Symbols.home)]),
          const SizedBox(height: MySpacing.md),
          MyCampo(
            controller: _calle,
            label: 'Calle y número',
            hint: 'Ej.: Av. San Martín 1240',
            icon: Symbols.location_on,
            accion: TextInputAction.next,
          ),
          MyCampo(
            controller: _referencia,
            label: 'Referencia (opcional)',
            hint: 'Ej.: portón negro, piso 2 dpto B',
            icon: Symbols.pin_drop,
            obligatorio: false,
          ),
          const MyOverline('Guardala como'),
          const SizedBox(height: MySpacing.xs),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              for (final a in [...aliasSugeridos, _otroAlias])
                MyChip(
                  a,
                  selected: _alias == a,
                  onTap: () => setState(() {
                    _alias = a;
                    _faltaAlias = false;
                  }),
                ),
            ],
          ),
          if (_faltaAlias)
            Padding(
              padding: const EdgeInsets.only(top: MySpacing.xs),
              child: Text('Elegí cómo guardarla', style: MyType.bodySm.copyWith(color: MyColors.error)),
            ),
          const SizedBox(height: MySpacing.md),
          if (_alias == _otroAlias)
            MyCampo(
              controller: _otro,
              label: 'Nombre',
              hint: 'Ej.: Casa de mi mamá',
              icon: Symbols.label,
            ),
          MyBotonAccion(label: 'Guardar dirección', icon: Symbols.check, onPressed: _guardar),
        ],
      ),
    );
  }
}
