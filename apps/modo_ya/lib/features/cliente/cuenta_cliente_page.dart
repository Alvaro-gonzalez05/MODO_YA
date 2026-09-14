import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/cambiar_password.dart';

class CuentaClientePage extends ConsumerWidget {
  const CuentaClientePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sesionProvider);

    return Column(
      children: [
        const MyTopBar(zona: 'Mi cuenta'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance,
            ),
            children: [
              MyCard(
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(color: MyColors.primaryFixed, shape: BoxShape.circle),
                      child: const Icon(Symbols.person, size: 30, color: MyColors.primary, fill: 1),
                    ),
                    const SizedBox(width: MySpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.nombre, style: MyType.headlineMd),
                          Text(s.email ?? '', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                          if (s.telefono != null)
                            Text(s.telefono!, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
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
                      leading: const Icon(Symbols.edit, color: MyColors.primary),
                      title: Text('Mis datos', style: MyType.labelLg),
                      subtitle: Text('Nombre y telefono', style: MyType.bodySm),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => _editar(context, ref, s),
                    ),
                    ListTile(
                      leading: const Icon(Symbols.home_pin, color: MyColors.primary),
                      title: Text('Mis direcciones', style: MyType.labelLg),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => context.push('/cliente/direcciones'),
                    ),
                    ListTile(
                      leading: const Icon(Symbols.lock, color: MyColors.primary),
                      title: Text('Cambiar contrasena', style: MyType.labelLg),
                      trailing: const Icon(Symbols.chevron_right),
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
          ),
        ),
      ],
    );
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, Sesion s) async {
    final nombre = TextEditingController(text: s.nombre);
    final telefono = TextEditingController(text: s.telefono);
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
              Text('Mis datos', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.md),
              MyCampo(controller: nombre, label: 'Nombre y apellido'),
              MyCampo(controller: telefono, label: 'Telefono', keyboard: TextInputType.phone),
              MyBotonAccion(
                label: 'Guardar',
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    final db = Backend.db;
                    // Perfil y ficha de cliente: los locales ven el nombre del
                    // cliente copiado en cada pedido nuevo desde `clientes`.
                    await db.from('perfiles').update({'nombre': nombre.text.trim(), 'telefono': telefono.text.trim()}).eq('id', s.usuarioId);
                    await db.from('clientes').update({'nombre': nombre.text.trim(), 'telefono': telefono.text.trim()}).eq('perfil_id', s.usuarioId);
                    ref.invalidate(sesionActualProvider);
                    if (h.mounted) Navigator.pop(h);
                  } catch (e) {
                    if (h.mounted) mostrarError(h, traducirError(e));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    nombre.dispose();
    telefono.dispose();
  }
}
