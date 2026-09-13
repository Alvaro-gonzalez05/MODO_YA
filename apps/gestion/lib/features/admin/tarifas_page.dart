import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// C7 - Tarifas y reglas del sistema.
///
/// La clienta pidio que todo esto se pueda cambiar sin publicar una version
/// nueva de la app, asi que son datos de la base y no constantes del codigo.
class AdminTarifasPage extends ConsumerStatefulWidget {
  const AdminTarifasPage({super.key});

  @override
  ConsumerState<AdminTarifasPage> createState() => _AdminTarifasPageState();
}

class _AdminTarifasPageState extends ConsumerState<AdminTarifasPage> {
  Tarifario? _borrador;

  @override
  Widget build(BuildContext context) {
    final tarifarioAsync = ref.watch(tarifarioProvider);

    return tarifarioAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (guardado) {
        final t = _borrador ?? guardado;
        final hayCambios = _borrador != null &&
            (t.gananciaRepartidorBase != guardado.gananciaRepartidorBase ||
                t.comisionModoYa != guardado.comisionModoYa ||
                t.kmIncluidos != guardado.kmIncluidos ||
                t.precioKmAdicional != guardado.precioKmAdicional ||
                t.radioBusquedaKm != guardado.radioBusquedaKm ||
                t.segundosParaAceptar != guardado.segundosParaAceptar);

        return ListView(
          padding: const EdgeInsets.all(MySpacing.xl),
          children: [
            AdminPageHeader(
              titulo: 'Tarifas y reglas',
              bajada: 'Se aplican a los envios nuevos, sin actualizar la app',
              acciones: [
                if (hayCambios)
                  FilledButton.icon(
                    onPressed: () async {
                      // Tomamos el messenger antes del await: despues del
                      // gap async el context puede no seguir montado.
                      final messenger = ScaffoldMessenger.of(context);
                      await ref
                          .read(tarifasRepositoryProvider)
                          .actualizar(t);
                      if (!mounted) return;
                      setState(() => _borrador = null);
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Tarifas actualizadas')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(150, 48),
                    ),
                    icon: const Icon(Symbols.save, size: 20),
                    label: const Text('Guardar'),
                  ),
              ],
            ),

            MyHeroCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Precio de un envio hasta ${Formato.km(t.kmIncluidos)}',
                          style: MyType.bodyMd.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: MySpacing.xxs),
                        Text(
                          Formato.pesos(t.precioBase),
                          style: MyType.displayLg.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Cadete ${Formato.pesos(t.gananciaRepartidorBase)}',
                        style: MyType.labelLg.copyWith(color: Colors.white),
                      ),
                      Text(
                        'MODO YA ${Formato.pesos(t.comisionModoYa)}',
                        style: MyType.labelLg.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: MySpacing.xl),
            Text('Dinero', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.sm),
            _CampoNumero(
              icon: Symbols.sports_motorsports,
              titulo: 'Ganancia del cadete',
              detalle: 'Lo que cobra por un viaje dentro de la distancia base',
              valor: t.gananciaRepartidorBase,
              sufijo: 'pesos',
              paso: 250,
              onChanged: (v) => setState(
                () => _borrador = t.copyWith(gananciaRepartidorBase: v),
              ),
            ),
            _CampoNumero(
              icon: Symbols.percent,
              titulo: 'Comision MODO YA',
              detalle: 'Lo que se queda la plataforma por servicio',
              valor: t.comisionModoYa,
              sufijo: 'pesos',
              paso: 50,
              onChanged: (v) =>
                  setState(() => _borrador = t.copyWith(comisionModoYa: v)),
            ),
            _CampoNumero(
              icon: Symbols.add_road,
              titulo: 'Kilometro adicional',
              detalle: 'Se cobra por cada km que exceda la distancia base',
              valor: t.precioKmAdicional,
              sufijo: 'pesos',
              paso: 100,
              onChanged: (v) =>
                  setState(() => _borrador = t.copyWith(precioKmAdicional: v)),
            ),

            const SizedBox(height: MySpacing.lg),
            Text('Reglas de asignacion', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.sm),
            _CampoNumero(
              icon: Symbols.route,
              titulo: 'Distancia base incluida',
              detalle: 'Hasta aca se cobra la tarifa base',
              valor: t.kmIncluidos.round(),
              sufijo: 'km',
              paso: 1,
              onChanged: (v) => setState(
                () => _borrador = t.copyWith(kmIncluidos: v.toDouble()),
              ),
            ),
            _CampoNumero(
              icon: Symbols.my_location,
              titulo: 'Radio de busqueda',
              detalle: 'Hasta que distancia se le ofrece el envio a un cadete',
              valor: t.radioBusquedaKm.round(),
              sufijo: 'km',
              paso: 1,
              onChanged: (v) => setState(
                () => _borrador = t.copyWith(radioBusquedaKm: v.toDouble()),
              ),
            ),
            _CampoNumero(
              icon: Symbols.timer,
              titulo: 'Tiempo para aceptar',
              detalle: 'Si no responde, el envio pasa al siguiente cadete',
              valor: t.segundosParaAceptar,
              sufijo: 'segundos',
              paso: 5,
              onChanged: (v) => setState(
                () => _borrador = t.copyWith(segundosParaAceptar: v),
              ),
            ),

            const SizedBox(height: MySpacing.lg),
            MyCard(
              color: MyColors.secondaryContainer,
              shadows: const [],
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Symbols.info, size: 22, color: MyColors.secondary),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Text(
                      'El valor del kilometro adicional y el tiempo para '
                      'aceptar siguen pendientes de definicion con la clienta. '
                      'Los dejamos configurables para ajustarlos durante el '
                      'piloto sin tocar codigo.',
                      style: MyType.bodySm
                          .copyWith(color: MyColors.onSecondaryFixed),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CampoNumero extends StatelessWidget {
  const _CampoNumero({
    required this.icon,
    required this.titulo,
    required this.detalle,
    required this.valor,
    required this.sufijo,
    required this.paso,
    required this.onChanged,
  });

  final IconData icon;
  final String titulo;
  final String detalle;
  final int valor;
  final String sufijo;
  final int paso;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MySpacing.xs),
      child: MyCard(
        padding: const EdgeInsets.all(MySpacing.md),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: MyColors.primaryFixed,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 21, color: MyColors.primary),
            ),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: MyType.headlineSm),
                  Text(
                    detalle,
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: valor - paso < 0 ? null : () => onChanged(valor - paso),
              icon: const Icon(Symbols.remove_circle),
              color: MyColors.secondary,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 92),
              child: Column(
                children: [
                  Text(
                    sufijo == 'pesos' ? Formato.pesos(valor) : '$valor',
                    style: MyType.headlineMd.copyWith(color: MyColors.primary),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    sufijo,
                    style: MyType.labelSm.copyWith(color: MyColors.secondary),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => onChanged(valor + paso),
              icon: const Icon(Symbols.add_circle),
              color: MyColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
