import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';
import 'carrito.dart';

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
              MyCard(
                onTap: () {
                  ref.read(direccionElegidaProvider.notifier).elegir(d.id);
                  context.pop();
                },
                color: d.id == elegida ? MyColors.primaryFixed : null,
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
                            Text(d.referencia!, style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario)),
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
                            final ok = await confirmar(context, titulo: 'Borrar dirección', mensaje: d.calle, aceptar: 'Borrar', peligroso: true);
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

    final alias = TextEditingController(text: esPrimera ? 'Casa' : '');
    final calle = TextEditingController();
    final referencia = TextEditingController();
    final form = GlobalKey<FormState>();

    await mostrarFormularioEmergente(
      context,
      titulo: 'Datos de la dirección',
      builder: (s) => Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MyMapaVista(alto: 120, marcadores: [MyMarcador(punto: punto, icono: Symbols.home)]),
              const SizedBox(height: MySpacing.md),
              MyCampo(controller: calle, label: 'Calle y número', hint: 'Av. San Martín 1240', icon: Symbols.location_on),
              MyCampo(
                controller: referencia,
                label: 'Referencia (opcional)',
                hint: 'Portón negro, piso 2 dpto B',
                icon: Symbols.pin_drop,
                obligatorio: false,
              ),
              MyCampo(controller: alias, label: 'Nombre', hint: 'Casa, Trabajo...', icon: Symbols.label),
              MyBotonAccion(
                label: 'Guardar dirección',
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
    );
    for (final c in [alias, calle, referencia]) {
      c.dispose();
    }
  }
}
