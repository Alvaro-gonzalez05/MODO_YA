import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';

/// Para quien entro pero no puede usar esta app: un local suspendido o un
/// rider (que tiene su propia app).
class CuentaNoHabilitadaPage extends ConsumerWidget {
  const CuentaNoHabilitadaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sesionProvider);
    final esRider = s.rol == RolUsuario.repartidor;

    final (icono, titulo, mensaje) = esRider
        ? (
            Symbols.sports_motorsports,
            'Esta app es para clientes y locales',
            'Tu cuenta es de rider. Entra con el mismo email y contraseña en la app MODO YA Rider.',
          )
        : (
            Symbols.block,
            'Tu local no esta habilitado',
            'La cuenta figura como "${s.aprobacion?.label.toLowerCase() ?? 'sin aprobar'}". '
                'Comunicate con la administración de MODO YA para reactivarla.',
          );

    return Scaffold(
      body: FormularioCentrado(
        children: [
          const MarcaGrande(),
          const SizedBox(height: MySpacing.xl),
          MyEmptyState(icon: icono, title: titulo, message: mensaje),
          OutlinedButton.icon(
            onPressed: () => ref.read(authRepositoryProvider).salir(),
            icon: const Icon(Symbols.logout, size: 20),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
