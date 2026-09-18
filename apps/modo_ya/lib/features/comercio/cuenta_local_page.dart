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

  Future<void> _cambiarImagen(BuildContext context, WidgetRef ref, {required bool portada}) async {
    try {
      // La portada se ve ancha (hasta ~800 px en la PC); el logo, chico.
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: portada ? 1600 : 600,
        maxHeight: portada ? 1000 : 600,
        imageQuality: 85,
      );
      if (f == null) return;
      final ext = f.name.split('.').last.toLowerCase() == 'png' ? 'png' : 'jpg';
      final repo = ref.read(comerciosRepositoryProvider);
      final bytes = await f.readAsBytes();
      if (portada) {
        await repo.subirPortada(comercio.id, bytes, extension: ext);
      } else {
        await repo.subirLogo(comercio.id, bytes, extension: ext);
      }
      ref.invalidate(comercioActualProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const altoPortada = 170.0;
    const ladoLogo = 84.0;

    Widget tocable(Widget hijo, VoidCallback onTap) => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: hijo),
    );

    Widget camara({String? texto}) => Container(
      padding: EdgeInsets.symmetric(horizontal: texto == null ? 5 : MySpacing.sm, vertical: 5),
      decoration: BoxDecoration(color: MyColors.primary, borderRadius: BorderRadius.circular(MyRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.photo_camera, size: 15, color: MyColors.onPrimary, fill: 1),
          if (texto != null) ...[
            const SizedBox(width: 4),
            Text(texto, style: MyType.labelMd.copyWith(color: MyColors.onPrimary)),
          ],
        ],
      ),
    );

    return MyCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Portada a todo el ancho y el logo montado sobre el borde de abajo,
          // igual que la ve el cliente.
          SizedBox(
            height: altoPortada + ladoLogo / 2,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: altoPortada,
                  child: tocable(
                    MyImagen(url: comercio.portadaUrl, alto: altoPortada, radio: MyRadius.card, icono: Symbols.image),
                    () => _cambiarImagen(context, ref, portada: true),
                  ),
                ),
                Positioned(
                  right: MySpacing.sm,
                  top: MySpacing.sm,
                  child: tocable(
                    camara(texto: comercio.portadaUrl == null ? 'Subir portada' : 'Cambiar portada'),
                    () => _cambiarImagen(context, ref, portada: true),
                  ),
                ),
                Positioned(
                  left: MySpacing.md,
                  bottom: 0,
                  child: tocable(
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: MyColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(MyRadius.lg + 3),
                          ),
                          child: MyImagen(
                            url: comercio.logoUrl,
                            ancho: ladoLogo,
                            alto: ladoLogo,
                            radio: MyRadius.lg,
                            icono: Symbols.storefront,
                          ),
                        ),
                        Positioned(right: 0, bottom: 0, child: camara()),
                      ],
                    ),
                    () => _cambiarImagen(context, ref, portada: false),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(MySpacing.md, MySpacing.sm, MySpacing.md, MySpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comercio.nombre, style: MyType.headlineMd),
                Text(comercio.rubro, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                if (usuario != null) ...[
                  const SizedBox(height: MySpacing.xs),
                  Row(
                    children: [
                      Icon(Symbols.alternate_email, size: 16, color: MyColors.secondary),
                      const SizedBox(width: MySpacing.xxs),
                      Flexible(
                        child: Text(usuario!, style: MyType.labelMd, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: MySpacing.xs),
                Text(
                  'La portada es la foto grande de tu tarjeta (tu comida o tu local, en horizontal). '
                  'El logo va al lado del nombre. Tocá cada una para cambiarla.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
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
