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

/// Hoja inferior de "Mi cuenta" (celular): datos del usuario, accesos a lo
/// que antes era la pantalla completa, tema claro/oscuro y cerrar sesion.
Future<void> mostrarCuentaCliente(BuildContext context, WidgetRef ref) {
  final s = ref.read(sesionProvider);
  final direcciones = ref.read(direccionesProvider).value ?? const <DireccionCliente>[];
  final principal = ref.read(direccionActualProvider);
  return mostrarHojaSecciones(
    context,
    titulo: 'Mi cuenta',
    usuarioNombre: s.nombre,
    usuarioDetalle: s.email,
    usuarioExtra: s.telefono,
    onEditarUsuario: () => editarMisDatos(context, ref, s),
    extra: principal == null
        ? null
        : _DireccionActual(direccion: principal, cantidad: direcciones.length, onTap: () => context.go('/cliente/direcciones')),
    secciones: [
      MySeccionHoja(icon: Symbols.person, label: 'Mis datos', onTap: () => editarMisDatos(context, ref, s)),
      MySeccionHoja(icon: Symbols.home_pin, label: 'Direcciones', contador: 0, onTap: () => context.go('/cliente/direcciones')),
      MySeccionHoja(icon: Symbols.receipt_long, label: 'Mis pedidos', onTap: () => context.go('/cliente/pedidos')),
      MySeccionHoja(icon: Symbols.key, label: 'Contraseña', onTap: () => mostrarCambiarPassword(context, ref)),
    ],
    onSalir: () => cerrarSesion(context, ref),
  );
}

/// Fila con la direccion de entrega elegida, dentro de la hoja.
class _DireccionActual extends StatelessWidget {
  const _DireccionActual({required this.direccion, required this.cantidad, required this.onTap});

  final DireccionCliente direccion;
  final int cantidad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MyColors.primaryFixed,
      borderRadius: BorderRadius.circular(MyRadius.lg),
      child: InkWell(
        onTap: () {
          Navigator.of(context, rootNavigator: true).pop();
          Future.delayed(const Duration(milliseconds: 220), onTap);
        },
        borderRadius: BorderRadius.circular(MyRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(MySpacing.sm),
          child: Row(
            children: [
              MyIconoCaja(Symbols.location_on, tamano: 36, circular: true),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Entregar en', style: MyType.labelSm.copyWith(color: MyColors.onPrimaryFixedVariant)),
                    Text(
                      '${direccion.alias} · ${direccion.calle}',
                      style: MyType.labelLg.copyWith(color: MyColors.onPrimaryFixed),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (cantidad > 1) MyBadge('$cantidad guardadas', tone: MyBadgeTone.neutral),
              const SizedBox(width: MySpacing.xxs),
              Icon(Symbols.chevron_right, size: 20, color: MyColors.onPrimaryFixed),
            ],
          ),
        ),
      ),
    );
  }
}

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
            onPressed: () => editarMisDatos(context, ref, s),
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
                    onPressed: () => editarMisDatos(context, ref, s),
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

    final plus = ref.watch(miPlusProvider).value;
    final tarjetaPlus = MyCard(
      color: MyColors.dock,
      child: Row(
        children: [
          Icon(Symbols.local_shipping, color: MyColors.primary, fill: 1, size: 28),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MODO YA Plus', style: MyType.headlineSm.copyWith(color: Colors.white)),
                Text(
                  plus == null
                      ? 'Envío gratis en los locales adheridos'
                      : plus.activo
                          ? 'Activo hasta el ${Formato.fechaCorta(plus.hasta!)}'
                          : 'Envío gratis en los locales adheridos por ${Formato.pesos(plus.precio)} al mes',
                  style: MyType.bodySm.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          MyBoton(
            label: plus?.activo ?? false ? 'Ver' : 'Quiero',
            onPressed: () => context.go('/cliente/plus'),
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
          ? [perfilConAccion, espacio, tarjetaPlus, espacio, misDirecciones, espacio, seguridad]
          : [
              perfil,
              espacio,
              tarjetaPlus,
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

}

/// Formulario emergente para cambiar nombre y telefono.
Future<void> editarMisDatos(BuildContext context, WidgetRef ref, Sesion s) async {
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
