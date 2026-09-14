import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Tarifas y reglas. Se aplican a los envios nuevos, sin actualizar la app.
///
/// Guardar no modifica el tarifario vigente: lo cierra y abre uno nuevo, asi
/// los envios ya cobrados conservan su precio.
class AdminTarifasPage extends ConsumerStatefulWidget {
  const AdminTarifasPage({super.key});

  @override
  ConsumerState<AdminTarifasPage> createState() => _AdminTarifasPageState();
}

class _AdminTarifasPageState extends ConsumerState<AdminTarifasPage> {
  Tarifario? _borrador;

  bool _cambio(Tarifario t, Tarifario g) =>
      t.gananciaRepartidorBase != g.gananciaRepartidorBase ||
      t.comisionModoYa != g.comisionModoYa ||
      t.kmIncluidos != g.kmIncluidos ||
      t.precioKmAdicional != g.precioKmAdicional ||
      t.radioBusquedaKm != g.radioBusquedaKm ||
      t.segundosParaAceptar != g.segundosParaAceptar;

  @override
  Widget build(BuildContext context) {
    return MyAsync(
      valor: ref.watch(tarifarioProvider),
      onReintentar: () => ref.invalidate(tarifarioProvider),
      datos: (guardado) {
        if (guardado == null) {
          return const MyEmptyState(title: 'No hay tarifario', message: 'La base no tiene un tarifario vigente.');
        }
        final t = _borrador ?? guardado;
        final hayCambios = _borrador != null && _cambio(t, guardado);

        return ListView(
          padding: const EdgeInsets.all(MySpacing.xl),
          children: [
            AdminPageHeader(
              titulo: 'Tarifas y reglas',
              bajada: 'Se aplican a los envios nuevos, sin actualizar la app',
              acciones: [
                if (hayCambios) ...[
                  TextButton(onPressed: () => setState(() => _borrador = null), child: const Text('Descartar')),
                  SizedBox(
                    width: 160,
                    child: MyBotonAccion(
                      label: 'Guardar',
                      icon: Symbols.save,
                      onPressed: () async {
                        final ok = await confirmar(
                          context,
                          titulo: 'Aplicar nuevas tarifas',
                          mensaje: 'Los envios que se creen desde ahora van a cobrarse con estos valores. '
                              'Los que ya existen no cambian.',
                          aceptar: 'Aplicar',
                        );
                        if (!ok) return;
                        try {
                          await ref.read(tarifasRepositoryProvider).reemplazar(t);
                          ref.invalidate(tarifarioProvider);
                          setState(() => _borrador = null);
                          if (context.mounted) mostrarAviso(context, 'Tarifas actualizadas');
                        } catch (e) {
                          if (context.mounted) mostrarError(context, e);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
            MyHeroCard(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: MySpacing.sm,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Envio hasta ${Formato.km(t.kmIncluidos)}',
                        style: MyType.bodyMd.copyWith(color: Colors.white70),
                      ),
                      Text(Formato.pesos(t.precioBase), style: MyType.displayLg.copyWith(color: Colors.white)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Rider ${Formato.pesos(t.gananciaRepartidorBase)}',
                          style: MyType.labelLg.copyWith(color: Colors.white)),
                      Text('MODO YA ${Formato.pesos(t.comisionModoYa)}',
                          style: MyType.labelLg.copyWith(color: Colors.white70)),
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
              titulo: 'Ganancia del rider',
              detalle: 'Por un viaje dentro de la distancia base',
              valor: t.gananciaRepartidorBase,
              pesos: true,
              paso: 250,
              onChanged: (v) => setState(() => _borrador = t.copyWith(gananciaRepartidorBase: v)),
            ),
            _CampoNumero(
              icon: Symbols.percent,
              titulo: 'Comision MODO YA',
              detalle: 'Por servicio',
              valor: t.comisionModoYa,
              pesos: true,
              paso: 50,
              onChanged: (v) => setState(() => _borrador = t.copyWith(comisionModoYa: v)),
            ),
            _CampoNumero(
              icon: Symbols.add_road,
              titulo: 'Kilometro adicional',
              detalle: 'Por cada km que pase la distancia base. Pendiente de definir.',
              valor: t.precioKmAdicional,
              pesos: true,
              paso: 100,
              onChanged: (v) => setState(() => _borrador = t.copyWith(precioKmAdicional: v)),
            ),
            const SizedBox(height: MySpacing.lg),
            Text('Reglas de asignacion', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.sm),
            _CampoNumero(
              icon: Symbols.route,
              titulo: 'Distancia base',
              detalle: 'Hasta aca se cobra la tarifa base (km)',
              valor: t.kmIncluidos.round(),
              paso: 1,
              minimo: 1,
              onChanged: (v) => setState(() => _borrador = t.copyWith(kmIncluidos: v.toDouble())),
            ),
            _CampoNumero(
              icon: Symbols.my_location,
              titulo: 'Radio de busqueda',
              detalle: 'Hasta que distancia se le ofrece un envio a un rider (km)',
              valor: t.radioBusquedaKm.round(),
              paso: 1,
              minimo: 1,
              onChanged: (v) => setState(() => _borrador = t.copyWith(radioBusquedaKm: v.toDouble())),
            ),
            _CampoNumero(
              icon: Symbols.timer,
              titulo: 'Tiempo para aceptar',
              detalle: 'Si no responde, pasa al siguiente rider (segundos)',
              valor: t.segundosParaAceptar,
              paso: 5,
              minimo: 10,
              onChanged: (v) => setState(() => _borrador = t.copyWith(segundosParaAceptar: v)),
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
    required this.paso,
    required this.onChanged,
    this.pesos = false,
    this.minimo = 0,
  });

  final IconData icon;
  final String titulo;
  final String detalle;
  final int valor;
  final int paso;
  final int minimo;
  final bool pesos;
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
              decoration: const BoxDecoration(color: MyColors.primaryFixed, shape: BoxShape.circle),
              child: Icon(icon, size: 21, color: MyColors.primary),
            ),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: MyType.headlineSm),
                  Text(detalle, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                ],
              ),
            ),
            IconButton(
              onPressed: valor - paso < minimo ? null : () => onChanged(valor - paso),
              icon: const Icon(Symbols.remove_circle),
              color: MyColors.secondary,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 84),
              child: Text(
                pesos ? Formato.pesos(valor) : '$valor',
                style: MyType.headlineMd.copyWith(color: MyColors.primary),
                textAlign: TextAlign.center,
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
