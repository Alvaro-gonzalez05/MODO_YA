import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/cambiar_password.dart';
import '../../comun/formulario_emergente.dart';
import '../../comun/menu_usuario.dart';
import 'carrito.dart';

/// Cuenta del cliente: datos, direcciones y seguridad.
class CuentaClientePage extends ConsumerWidget {
  const CuentaClientePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sesionProvider);
    final direcciones = ref.watch(direccionesProvider).value ?? const <DireccionCliente>[];
    final elegida = ref.watch(direccionActualProvider);

    final datosPerfil = Row(
      children: [
        const MyIconoCaja(Symbols.person, tamano: 64, circular: true),
        const SizedBox(width: MySpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.nombre, style: MyType.headlineMd),
              if (s.email != null) Text(s.email!, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
              if (s.telefono != null) Text(s.telefono!, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
            ],
          ),
        ),
        if (!context.esMovil)
          MyBoton(
            label: 'Editar',
            icon: Symbols.edit,
            tipo: MyBotonTipo.secundario,
            onPressed: () => _editar(context, ref, s),
          ),
      ],
    );
    final perfil = MyCard(child: datosPerfil);
    final perfilConAccion = context.esMovil
        ? MyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                datosPerfil,
                const SizedBox(height: MySpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: MyBoton(
                    label: 'Editar mis datos',
                    icon: Symbols.edit,
                    tipo: MyBotonTipo.secundario,
                    onPressed: () => _editar(context, ref, s),
                  ),
                ),
              ],
            ),
          )
        : perfil;

    final misDirecciones = MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Direcciones', style: MyType.headlineSm)),
              MyBoton(
                label: 'Administrar',
                icon: Symbols.home_pin,
                tipo: MyBotonTipo.secundario,
                onPressed: () => context.go('/cliente/direcciones'),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          if (direcciones.isEmpty)
            Text('Todavía no guardaste ninguna.', style: MyType.bodyMd.copyWith(color: MyColors.secondary))
          else
            for (final d in direcciones)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MySpacing.xxs),
                child: Row(
                  children: [
                    Icon(
                      d.id == elegida?.id ? Symbols.radio_button_checked : Symbols.location_on,
                      size: 20,
                      color: MyColors.primary,
                    ),
                    const SizedBox(width: MySpacing.xs),
                    Expanded(
                      child: Text('${d.alias} · ${d.calle}', style: MyType.bodyMd, overflow: TextOverflow.ellipsis),
                    ),
                    if (d.predeterminada) const MyBadge('Principal', tone: MyBadgeTone.info),
                  ],
                ),
              ),
        ],
      ),
    );

    final seguridad = MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Seguridad', style: MyType.headlineSm),
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
    return MyPagina(
      rotulo: 'Configuración',
      titulo: 'Mi cuenta',
      anchoMaximo: 1080,
      children: context.esMovil
          ? [perfilConAccion, espacio, misDirecciones, espacio, seguridad]
          : [
              perfil,
              espacio,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: misDirecciones),
                  const SizedBox(width: MySpacing.md),
                  Expanded(child: seguridad),
                ],
              ),
            ],
    );
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, Sesion s) async {
    final nombre = TextEditingController(text: s.nombre);
    final telefono = TextEditingController(text: s.telefono);
    final form = GlobalKey<FormState>();

    await mostrarFormularioEmergente(
      context,
      titulo: 'Mis datos',
      builder: (h) => Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyCampo(controller: nombre, label: 'Nombre y apellido', icon: Symbols.person),
            MyCampo(controller: telefono, label: 'Teléfono', icon: Symbols.call, keyboard: TextInputType.phone),
            const SizedBox(height: MySpacing.xs),
            MyBotonAccion(
              label: 'Guardar',
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                try {
                  final db = Backend.db;
                  // Perfil y ficha de cliente: los locales ven el nombre del
                  // cliente copiado en cada pedido nuevo desde `clientes`.
                  await db
                      .from('perfiles')
                      .update({'nombre': nombre.text.trim(), 'telefono': telefono.text.trim()})
                      .eq('id', s.usuarioId);
                  await db
                      .from('clientes')
                      .update({'nombre': nombre.text.trim(), 'telefono': telefono.text.trim()})
                      .eq('perfil_id', s.usuarioId);
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
    );
    nombre.dispose();
    telefono.dispose();
  }
}
