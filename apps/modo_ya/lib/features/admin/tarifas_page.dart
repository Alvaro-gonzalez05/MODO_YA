import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Tarifas y reglas. Se aplican a los envíos nuevos, sin actualizar la app.
///
/// Guardar no modifica el tarifario vigente: lo cierra y abre uno nuevo, así
/// los envíos ya cobrados conservan su precio.
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

  Future<void> _guardar(Tarifario t) async {
    final ok = await confirmar(
      context,
      titulo: 'Aplicar nuevas tarifas',
      mensaje: 'Los envíos que se creen desde ahora se cobran con estos valores. Los que ya existen no cambian.',
      aceptar: 'Aplicar',
    );
    if (!ok) return;
    try {
      await ref.read(tarifasRepositoryProvider).reemplazar(t);
      ref.invalidate(tarifarioProvider);
      setState(() => _borrador = null);
      if (mounted) mostrarAviso(context, 'Tarifas actualizadas');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardado = ref.watch(tarifarioProvider);

    return MyAsync(
      valor: guardado,
      onReintentar: () => ref.invalidate(tarifarioProvider),
      datos: (g) {
        if (g == null) {
          return const MyEmptyState(title: 'No hay tarifario', message: 'La base no tiene un tarifario vigente.');
        }
        final t = _borrador ?? g;
        final hayCambios = _borrador != null && _cambio(t, g);

        final dinero = [
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
            titulo: 'Comisión MODO YA',
            detalle: 'Por cada servicio',
            valor: t.comisionModoYa,
            pesos: true,
            paso: 50,
            onChanged: (v) => setState(() => _borrador = t.copyWith(comisionModoYa: v)),
          ),
          _CampoNumero(
            icon: Symbols.add_road,
            titulo: 'Kilómetro adicional',
            detalle: 'Por cada km que pase la distancia base',
            valor: t.precioKmAdicional,
            pesos: true,
            paso: 100,
            onChanged: (v) => setState(() => _borrador = t.copyWith(precioKmAdicional: v)),
          ),
        ];

        final reglas = [
          _CampoNumero(
            icon: Symbols.route,
            titulo: 'Distancia base',
            detalle: 'Hasta acá se cobra la tarifa base',
            valor: t.kmIncluidos.round(),
            unidad: 'km',
            paso: 1,
            minimo: 1,
            onChanged: (v) => setState(() => _borrador = t.copyWith(kmIncluidos: v.toDouble())),
          ),
          _CampoNumero(
            icon: Symbols.my_location,
            titulo: 'Radio de búsqueda',
            detalle: 'Hasta qué distancia del local se le ofrece el envío a un rider',
            valor: t.radioBusquedaKm.round(),
            unidad: 'km',
            paso: 1,
            minimo: 1,
            onChanged: (v) => setState(() => _borrador = t.copyWith(radioBusquedaKm: v.toDouble())),
          ),
          _CampoNumero(
            icon: Symbols.timer,
            titulo: 'Tiempo para aceptar',
            detalle: 'Si no responde, pasa al siguiente rider',
            valor: t.segundosParaAceptar,
            unidad: 's',
            paso: 5,
            minimo: 10,
            onChanged: (v) => setState(() => _borrador = t.copyWith(segundosParaAceptar: v)),
          ),
        ];

        final resumen = MyHeroCard(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: MySpacing.lg,
            runSpacing: MySpacing.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ENVÍO HASTA ${Formato.km(t.kmIncluidos).toUpperCase()}', style: MyType.labelSm.copyWith(color: Colors.white70)),
                  Text(Formato.pesos(t.precioBase), style: MyType.displayLg.copyWith(color: Colors.white, fontSize: 44, height: 1.1)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Rider ${Formato.pesos(t.gananciaRepartidorBase)}', style: MyType.headlineSm.copyWith(color: Colors.white)),
                  Text('MODO YA ${Formato.pesos(t.comisionModoYa)}', style: MyType.labelLg.copyWith(color: Colors.white70)),
                  if (t.precioKmAdicional > 0)
                    Text('+ ${Formato.pesos(t.precioKmAdicional)} por km extra', style: MyType.labelLg.copyWith(color: Colors.white70)),
                ],
              ),
            ],
          ),
        );

        Widget grupo(String titulo, List<Widget> campos) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(titulo, style: MyType.headlineMd),
                const SizedBox(height: MySpacing.sm),
                for (final c in campos) ...[c, const SizedBox(height: MySpacing.sm)],
              ],
            );

        final acciones = [
          if (hayCambios) ...[
            MyBoton(label: 'Descartar', tipo: MyBotonTipo.secundario, onPressed: () => setState(() => _borrador = null)),
            MyBoton(label: 'Guardar cambios', icon: Symbols.save, onPressed: () => _guardar(t)),
          ],
        ];

        return MyPagina(
          rotulo: 'Configuración',
          titulo: 'Tarifas y reglas',
          bajada: 'Se aplican a los envíos nuevos al instante, sin actualizar la app',
          acciones: acciones,
          children: [
            resumen,
            if (hayCambios)
              Padding(
                padding: const EdgeInsets.only(top: MySpacing.md),
                child: MyCard(
                  color: MyColors.primaryFixed,
                  shadows: const [],
                  padding: const EdgeInsets.all(MySpacing.md),
                  child: Row(
                    children: [
                      Icon(Symbols.edit_note, color: MyColors.onPrimaryFixedVariant),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Text(
                          'Hay cambios sin guardar.',
                          style: MyType.labelLg.copyWith(color: MyColors.onPrimaryFixedVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: MySpacing.xl),
            if (context.esMovil) ...[
              grupo('Dinero', dinero),
              const SizedBox(height: MySpacing.md),
              grupo('Reglas de asignación', reglas),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: grupo('Dinero', dinero)),
                  const SizedBox(width: MySpacing.lg),
                  Expanded(child: grupo('Reglas de asignación', reglas)),
                ],
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
    this.unidad,
    this.minimo = 0,
  });

  final IconData icon;
  final String titulo;
  final String detalle;
  final int valor;
  final int paso;
  final int minimo;
  final bool pesos;
  final String? unidad;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final texto = pesos ? Formato.pesos(valor) : '$valor${unidad == null ? '' : ' $unidad'}';

    final stepper = Container(
      decoration: BoxDecoration(
        color: MyColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MyRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: valor - paso < minimo ? null : () => onChanged(valor - paso),
            icon: const Icon(Symbols.remove),
            color: MyColors.onSurface,
            tooltip: 'Bajar',
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 92),
            child: Text(texto, style: MyType.headlineSm.copyWith(color: MyColors.tertiary), textAlign: TextAlign.center),
          ),
          IconButton(
            onPressed: () => onChanged(valor + paso),
            icon: const Icon(Symbols.add),
            color: MyColors.primary,
            tooltip: 'Subir',
          ),
        ],
      ),
    );

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: MyResponsivo(
        builder: (context, _, ancho) {
          final encabezado = Row(
            children: [
              MyIconoCaja(icon, circular: true),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: MyType.labelLg.copyWith(fontSize: 15)),
                    Text(detalle, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                  ],
                ),
              ),
            ],
          );
          // Si no entra al lado, el control va abajo a lo ancho: nunca se
          // aprieta el texto.
          if (ancho < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                encabezado,
                const SizedBox(height: MySpacing.sm),
                Align(alignment: Alignment.centerRight, child: stepper),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: encabezado),
              const SizedBox(width: MySpacing.sm),
              stepper,
            ],
          );
        },
      ),
    );
  }
}
