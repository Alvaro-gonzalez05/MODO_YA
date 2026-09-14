import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/cambiar_password.dart';

/// Cuenta del local (A12): datos de la vidriera, logo, ubicacion, horarios.
class CuentaLocalPage extends ConsumerWidget {
  const CuentaLocalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercioAsync = ref.watch(comercioActualProvider);
    final sesion = ref.watch(sesionProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Mi cuenta'),
        Expanded(
          child: MyAsync(
            valor: comercioAsync,
            onReintentar: () => ref.invalidate(comercioActualProvider),
            datos: (comercio) {
              if (comercio == null) return const SizedBox.shrink();
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance,
                ),
                children: [
                  MyCard(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _cambiarLogo(context, ref, comercio),
                          child: Stack(
                            children: [
                              MyImagen(url: comercio.logoUrl, ancho: 72, alto: 72, radio: MyRadius.lg, icono: Symbols.storefront),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
                                  child: const Icon(Symbols.photo_camera, size: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: MySpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(comercio.nombre, style: MyType.headlineMd),
                              Text(comercio.rubro, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                              Text(sesion.email ?? '', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.lg),
                  MyCard(
                    padding: const EdgeInsets.symmetric(vertical: MySpacing.xs),
                    child: Column(
                      children: [
                        _Opcion(
                          icon: Symbols.edit,
                          titulo: 'Datos del local',
                          detalle: '${comercio.telefono} - demora ${comercio.demoraEstimadaMin} min',
                          onTap: () => _editarDatos(context, ref, comercio),
                        ),
                        _Opcion(
                          icon: comercio.direccion.tieneCoordenadas ? Symbols.location_on : Symbols.location_off,
                          titulo: 'Punto de retiro',
                          detalle: comercio.direccion.tieneCoordenadas
                              ? comercio.direccion.calle
                              : 'Sin marcar: no podes pedir riders',
                          alerta: !comercio.direccion.tieneCoordenadas,
                          onTap: () async {
                            final d = comercio.direccion;
                            final p = await MyMapa.elegirPunto(
                              context,
                              inicial: d.tieneCoordenadas ? LatLng(d.lat!, d.lng!) : null,
                              titulo: 'Ubicacion del local',
                            );
                            if (p == null) return;
                            try {
                              await ref.read(comerciosRepositoryProvider).setUbicacion(p.latitude, p.longitude);
                              ref.invalidate(comercioActualProvider);
                            } catch (e) {
                              if (context.mounted) mostrarError(context, e);
                            }
                          },
                        ),
                        _Opcion(
                          icon: Symbols.schedule,
                          titulo: 'Horarios de atencion',
                          detalle: 'Cuando te pueden pedir los clientes',
                          onTap: () => context.push('/local/horarios'),
                        ),
                        _Opcion(
                          icon: Symbols.receipt_long,
                          titulo: 'Historial de envios',
                          detalle: 'Importes y comprobantes',
                          onTap: () => context.push('/local/historial'),
                        ),
                        _Opcion(
                          icon: Symbols.lock,
                          titulo: 'Cambiar contrasena',
                          detalle: 'Si todavia usas la temporal, cambiala',
                          onTap: () => mostrarCambiarPassword(context, ref),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MySpacing.lg),
                  OutlinedButton.icon(
                    onPressed: () => ref.read(authRepositoryProvider).salir(),
                    icon: const Icon(Symbols.logout, size: 20),
                    label: const Text('Cerrar sesion'),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _cambiarLogo(BuildContext context, WidgetRef ref, Comercio comercio) async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600, imageQuality: 85);
      if (f == null) return;
      final ext = f.name.split('.').last.toLowerCase() == 'png' ? 'png' : 'jpg';
      await ref.read(comerciosRepositoryProvider).subirLogo(comercio.id, await f.readAsBytes(), extension: ext);
      ref.invalidate(comercioActualProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  Future<void> _editarDatos(BuildContext context, WidgetRef ref, Comercio c) async {
    final nombre = TextEditingController(text: c.nombre);
    final telefono = TextEditingController(text: c.telefono);
    final calle = TextEditingController(text: c.direccion.calle);
    final referencia = TextEditingController(text: c.direccion.referencia);
    final demora = TextEditingController(text: '${c.demoraEstimadaMin}');
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
              Text('Datos del local', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.md),
              MyCampo(controller: nombre, label: 'Nombre'),
              MyCampo(controller: telefono, label: 'Telefono', keyboard: TextInputType.phone),
              MyCampo(controller: calle, label: 'Direccion'),
              MyCampo(controller: referencia, label: 'Referencia', obligatorio: false),
              MyCampo(
                controller: demora,
                label: 'Demora de preparacion (minutos)',
                soloNumeros: true,
                validar: (t) => (int.tryParse(t) ?? 0) <= 0 ? 'Pone los minutos' : null,
              ),
              MyBotonAccion(
                label: 'Guardar',
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    await ref.read(comerciosRepositoryProvider).actualizar(
                          c.id,
                          nombre: nombre.text,
                          telefono: telefono.text,
                          calle: calle.text,
                          referencia: referencia.text,
                          demoraEstimadaMin: int.parse(demora.text),
                        );
                    ref.invalidate(comercioActualProvider);
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
    for (final t in [nombre, telefono, calle, referencia, demora]) {
      t.dispose();
    }
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icon,
    required this.titulo,
    required this.detalle,
    required this.onTap,
    this.alerta = false,
  });

  final IconData icon;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: alerta ? MyColors.errorContainer : MyColors.secondaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: alerta ? MyColors.error : MyColors.primary),
      ),
      title: Text(titulo, style: MyType.labelLg),
      subtitle: Text(detalle, style: MyType.bodySm.copyWith(color: alerta ? MyColors.error : MyColors.secondary)),
      trailing: const Icon(Symbols.chevron_right, color: MyColors.outline),
      onTap: onTap,
    );
  }
}
