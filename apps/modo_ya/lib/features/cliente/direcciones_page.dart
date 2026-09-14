import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';
import 'carrito.dart';

/// Direcciones del cliente. Se marca el pin en el mapa: en Malargue la
/// numeracion no siempre alcanza para encontrar una casa.
class DireccionesPage extends ConsumerWidget {
  const DireccionesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final direcciones = ref.watch(direccionesProvider);
    final elegida = ref.watch(direccionElegidaProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Symbols.arrow_back), onPressed: () => context.pop()),
        title: const Text('Mis direcciones'),
      ),
      body: MyAsync(
        valor: direcciones,
        onReintentar: () => ref.invalidate(direccionesProvider),
        datos: (lista) => FormularioCentrado(
          ancho: 560,
          children: [
            if (lista.isEmpty)
              const MyEmptyState(
                icon: Symbols.home_pin,
                title: 'Todavia no guardaste direcciones',
                message: 'Agrega a donde queres que te llevemos los pedidos.',
              ),
            for (final d in lista) ...[
              MyCard(
                onTap: () {
                  ref.read(direccionElegidaProvider.notifier).elegir(d.id);
                  context.pop();
                },
                color: d.id == elegida ? MyColors.primaryFixed : MyColors.surfaceContainerLowest,
                child: Row(
                  children: [
                    Icon(
                      d.id == elegida ? Symbols.radio_button_checked : Symbols.radio_button_unchecked,
                      color: MyColors.primary,
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(child: Text(d.alias, style: MyType.headlineSm)),
                              if (d.predeterminada) ...[
                                const SizedBox(width: MySpacing.xs),
                                const MyBadge('Principal', tone: MyBadgeTone.info),
                              ],
                            ],
                          ),
                          Text(d.calle, style: MyType.bodyMd),
                          if (d.referencia != null)
                            Text(d.referencia!, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                        ],
                      ),
                    ),
                    PopupMenuButton<int>(
                      icon: const Icon(Symbols.more_vert),
                      onSelected: (v) async {
                        try {
                          if (v == 0) {
                            await ref.read(direccionesRepositoryProvider).hacerPredeterminada(d.id);
                          } else {
                            final ok = await confirmar(context, titulo: 'Borrar direccion', mensaje: d.calle, aceptar: 'Borrar', peligroso: true);
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
                  ],
                ),
              ),
              const SizedBox(height: MySpacing.sm),
            ],
            const SizedBox(height: MySpacing.md),
            FilledButton.icon(
              onPressed: () => _nueva(context, ref, esPrimera: lista.isEmpty),
              icon: const Icon(Symbols.add_location, size: 20),
              label: const Text('Agregar direccion'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _nueva(BuildContext context, WidgetRef ref, {required bool esPrimera}) async {
    final punto = await MyMapa.elegirPunto(
      context,
      titulo: 'Donde te llevamos el pedido',
      ayuda: 'Mueve el mapa hasta que el pin quede sobre tu puerta.',
    );
    if (punto == null || !context.mounted) return;

    final alias = TextEditingController(text: esPrimera ? 'Casa' : '');
    final calle = TextEditingController();
    final referencia = TextEditingController();
    final form = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(s).bottom),
        child: Form(
          key: form,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            children: [
              Text('Datos de la direccion', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.md),
              MyMapaVista(alto: 120, marcadores: [MyMarcador(punto: punto, icono: Symbols.home)]),
              const SizedBox(height: MySpacing.md),
              MyCampo(controller: calle, label: 'Calle y numero', hint: 'Av. San Martin 1240', icon: Symbols.location_on),
              MyCampo(
                controller: referencia,
                label: 'Referencia (opcional)',
                hint: 'Porton negro, piso 2 dpto B',
                icon: Symbols.pin_drop,
                obligatorio: false,
              ),
              MyCampo(controller: alias, label: 'Nombre', hint: 'Casa, Trabajo...', icon: Symbols.label),
              MyBotonAccion(
                label: 'Guardar direccion',
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    final id = await ref.read(direccionesRepositoryProvider).agregar(
                          alias: alias.text,
                          calle: calle.text,
                          referencia: referencia.text,
                          lat: punto.latitude,
                          lng: punto.longitude,
                        );
                    ref.invalidate(direccionesProvider);
                    ref.read(direccionElegidaProvider.notifier).elegir(id);
                    if (s.mounted) Navigator.pop(s);
                  } catch (e) {
                    if (s.mounted) mostrarError(s, e);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    for (final c in [alias, calle, referencia]) {
      c.dispose();
    }
  }
}
