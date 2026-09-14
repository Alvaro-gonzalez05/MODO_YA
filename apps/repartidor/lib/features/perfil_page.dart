import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'ubicacion.dart';

/// Perfil del rider (B1).
class PerfilPage extends ConsumerWidget {
  const PerfilPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rider = ref.watch(repartidorActualProvider).value;
    final s = ref.watch(sesionProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Mi perfil'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance),
            children: [
              MyCard(
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(color: MyColors.primaryFixed, shape: BoxShape.circle),
                      child: const Icon(Symbols.sports_motorsports, size: 32, color: MyColors.primary),
                    ),
                    const SizedBox(width: MySpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rider?.nombre ?? s.nombre, style: MyType.headlineMd),
                          Text(s.email ?? '', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                          Text(rider?.telefono ?? '', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                          const SizedBox(height: MySpacing.xxs),
                          if (rider != null)
                            MyBadge(
                              rider.aprobacion.label,
                              tone: rider.aprobacion.puedeOperar ? MyBadgeTone.success : MyBadgeTone.danger,
                            ),
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
                    ListTile(
                      leading: const Icon(Symbols.two_wheeler, color: MyColors.primary),
                      title: Text('Vehículo', style: MyType.labelLg),
                      subtitle: Text(rider?.vehiculo.label ?? '-', style: MyType.bodySm),
                    ),
                    ListTile(
                      leading: const Icon(Symbols.lock, color: MyColors.primary),
                      title: Text('Cambiar contraseña', style: MyType.labelLg),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => _cambiarPassword(context, ref),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MySpacing.md),
              MyCard(
                color: MyColors.secondaryContainer,
                shadows: const [],
                child: Row(
                  children: [
                    const Icon(Symbols.shield, color: MyColors.secondary),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Text(
                        'Tu ubicación se comparte únicamente mientras estás conectado.',
                        style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MySpacing.lg),
              OutlinedButton.icon(
                onPressed: () async {
                  // Al salir se desconecta: un rider sin sesion no puede quedar
                  // recibiendo ofertas.
                  try {
                    if (rider?.conectado ?? false) {
                      await ref.read(repartidoresRepositoryProvider).setConectado(false);
                    }
                  } catch (_) {}
                  ref.read(ubicacionRiderProvider.notifier).parar();
                  await ref.read(authRepositoryProvider).salir();
                },
                icon: const Icon(Symbols.logout, size: 20),
                label: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _cambiarPassword(BuildContext context, WidgetRef ref) async {
    final nueva = TextEditingController();
    final form = GlobalKey<FormState>();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (h) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(h).bottom),
        child: Form(
          key: form,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(MySpacing.screenEdge),
            children: [
              Text('Cambiar contraseña', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.md),
              MyCampo(
                controller: nueva,
                label: 'Nueva contraseña',
                ocultar: true,
                validar: (t) => t.length < 8 ? 'Mínimo 8 caracteres' : null,
              ),
              MyBotonAccion(
                label: 'Guardar',
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    await ref.read(authRepositoryProvider).cambiarPassword(nueva.text);
                    if (h.mounted) Navigator.pop(h);
                  } catch (e) {
                    if (h.mounted) mostrarError(h, e);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    nueva.dispose();
  }
}
