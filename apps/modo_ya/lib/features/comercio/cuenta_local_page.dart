import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/cambiar_password.dart';
import '../../comun/formulario_emergente.dart';
import '../../comun/menu_usuario.dart';

/// Mi local (A12): vidriera, datos, punto de retiro, horarios y seguridad.
class CuentaLocalPage extends ConsumerWidget {
  const CuentaLocalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercioAsync = ref.watch(comercioActualProvider);
    final sesion = ref.watch(sesionProvider);

    return MyPagina(
      rotulo: 'Configuración',
      titulo: 'Mi local',
      bajada: 'Cómo te ven los clientes y dónde te buscan los riders',
      onRefresh: () => ref.refresh(comercioActualProvider.future),
      children: [
        MyAsync(
          valor: comercioAsync,
          onReintentar: () => ref.invalidate(comercioActualProvider),
          datos: (comercio) {
            if (comercio == null) return const SizedBox.shrink();

            final perfil = _Perfil(comercio: comercio, usuario: sesion.email);
            final datos = _Datos(comercio: comercio);
            final ubicacion = _Ubicacion(comercio: comercio);
            final horarios = _ResumenHorarios(comercioId: comercio.id);
            final seguridad = MyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Seguridad', style: MyType.headlineSm),
                  const SizedBox(height: MySpacing.xxs),
                  Text(
                    'Si todavía usás la contraseña que te dio MODO YA, cambiala.',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  ),
                  const SizedBox(height: MySpacing.md),
                  Wrap(
                    spacing: MySpacing.xs,
                    runSpacing: MySpacing.xs,
                    children: [
                      MyBoton(
                        label: 'Cambiar contraseña',
                        icon: Symbols.key,
                        tipo: MyBotonTipo.oscuro,
                        onPressed: () => mostrarCambiarPassword(context, ref),
                      ),
                      MyBoton(
                        label: 'Cerrar sesión',
                        icon: Symbols.logout,
                        tipo: MyBotonTipo.peligro,
                        onPressed: () => cerrarSesion(context, ref),
                      ),
                    ],
                  ),
                ],
              ),
            );

            const espacio = SizedBox(height: MySpacing.md);
            if (context.esMovil) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [perfil, espacio, datos, espacio, ubicacion, espacio, horarios, espacio, seguridad],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [perfil, espacio, datos, espacio, seguridad],
                  ),
                ),
                const SizedBox(width: MySpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [ubicacion, espacio, horarios],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Perfil extends ConsumerWidget {
  const _Perfil({required this.comercio, required this.usuario});

  final Comercio comercio;
  final String? usuario;

  Future<void> _cambiarLogo(BuildContext context, WidgetRef ref) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyCard(
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _cambiarLogo(context, ref),
              child: Stack(
                children: [
                  MyImagen(url: comercio.logoUrl, ancho: 84, alto: 84, radio: MyRadius.lg, icono: Symbols.storefront),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
                      child: const Icon(Symbols.photo_camera, size: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: MySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comercio.nombre, style: MyType.headlineMd),
                Text(comercio.rubro, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                if (usuario != null) ...[
                  const SizedBox(height: MySpacing.xs),
                  Row(
                    children: [
                      const Icon(Symbols.alternate_email, size: 16, color: MyColors.secondary),
                      const SizedBox(width: MySpacing.xxs),
                      Flexible(child: Text(usuario!, style: MyType.labelMd, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ],
                const SizedBox(height: MySpacing.xs),
                Text('Tocá el logo para cambiarlo.', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Datos extends ConsumerWidget {
  const _Datos({required this.comercio});

  final Comercio comercio;

  Future<void> _editar(BuildContext context, WidgetRef ref) async {
    final c = comercio;
    final nombre = TextEditingController(text: c.nombre);
    final telefono = TextEditingController(text: c.telefono);
    final calle = TextEditingController(text: c.direccion.calle);
    final referencia = TextEditingController(text: c.direccion.referencia);
    final demora = TextEditingController(text: '${c.demoraEstimadaMin}');
    final form = GlobalKey<FormState>();

    await mostrarFormularioEmergente(
      context,
      titulo: 'Datos del local',
      builder: (hoja) => Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyCampo(controller: nombre, label: 'Nombre', icon: Symbols.storefront),
            MyCampo(controller: telefono, label: 'Teléfono', icon: Symbols.call, keyboard: TextInputType.phone),
            MyCampo(controller: calle, label: 'Dirección', icon: Symbols.location_on),
            MyCampo(controller: referencia, label: 'Referencia', icon: Symbols.pin_drop, obligatorio: false),
            MyCampo(
              controller: demora,
              label: 'Demora de preparación (minutos)',
              icon: Symbols.timer,
              soloNumeros: true,
              validar: (t) => (int.tryParse(t) ?? 0) <= 0 ? 'Poné los minutos' : null,
            ),
            const SizedBox(height: MySpacing.xs),
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
                  if (hoja.mounted) Navigator.pop(hoja);
                } catch (e) {
                  if (hoja.mounted) mostrarError(hoja, e);
                }
              },
            ),
          ],
        ),
      ),
    );
    for (final t in [nombre, telefono, calle, referencia, demora]) {
      t.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = comercio;
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Datos del local', style: MyType.headlineSm)),
              MyBoton(label: 'Editar', icon: Symbols.edit, tipo: MyBotonTipo.secundario, onPressed: () => _editar(context, ref)),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          MyDato('Teléfono', c.telefono, icono: Symbols.call),
          MyDato('Dirección', c.direccion.calle, icono: Symbols.location_on),
          if ((c.direccion.referencia ?? '').isNotEmpty) MyDato('Referencia', c.direccion.referencia!, icono: Symbols.pin_drop),
          MyDato('Demora de preparación', '${c.demoraEstimadaMin} minutos', icono: Symbols.timer),
        ],
      ),
    );
  }
}

class _Ubicacion extends ConsumerWidget {
  const _Ubicacion({required this.comercio});

  final Comercio comercio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = comercio.direccion;
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Punto de retiro', style: MyType.headlineSm),
          Text(
            d.tieneCoordenadas ? 'Donde los riders pasan a buscar los pedidos.' : 'Sin marcar: no podés pedir riders.',
            style: MyType.bodySm.copyWith(color: d.tieneCoordenadas ? MyColors.secondary : MyColors.error),
          ),
          const SizedBox(height: MySpacing.md),
          if (d.tieneCoordenadas) ...[
            MyMapaVista(
              alto: context.esMovil ? 180 : 240,
              radio: MyRadius.lg,
              marcadores: [MyMarcador(punto: LatLng(d.lat!, d.lng!), icono: Symbols.storefront)],
            ),
            const SizedBox(height: MySpacing.sm),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: MyBoton(
              label: d.tieneCoordenadas ? 'Mover el punto' : 'Marcar en el mapa',
              icon: d.tieneCoordenadas ? Symbols.edit_location : Symbols.add_location,
              tipo: d.tieneCoordenadas ? MyBotonTipo.secundario : MyBotonTipo.principal,
              onPressed: () async {
                final p = await MyMapa.elegirPunto(
                  context,
                  inicial: d.tieneCoordenadas ? LatLng(d.lat!, d.lng!) : null,
                  titulo: 'Ubicación del local',
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
          ),
        ],
      ),
    );
  }
}

class _ResumenHorarios extends ConsumerWidget {
  const _ResumenHorarios({required this.comercioId});

  final String comercioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final horarios = ref.watch(horariosProvider(comercioId)).value ?? const <Horario>[];

    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Horarios de atención', style: MyType.headlineSm)),
              MyBoton(
                label: 'Editar',
                icon: Symbols.schedule,
                tipo: MyBotonTipo.secundario,
                onPressed: () => context.go('/local/cuenta/horarios'),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          if (horarios.isEmpty)
            Text(
              'Sin horarios cargados: los clientes te ven abierto mientras el interruptor del inicio esté prendido.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            )
          else
            for (final d in [1, 2, 3, 4, 5, 6, 0])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 96, child: Text(Horario.nombresDias[d], style: MyType.labelLg)),
                    Expanded(
                      child: Text(
                        horarios.where((h) => h.dia == d).map((h) => '${h.abre} a ${h.cierra}').join('  ·  ').ifEmpty('Cerrado'),
                        style: MyType.bodyMd.copyWith(
                          color: horarios.any((h) => h.dia == d) ? MyColors.onSurface : MyColors.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String otro) => isEmpty ? otro : this;
}
