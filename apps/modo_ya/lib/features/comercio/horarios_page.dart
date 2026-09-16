import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';


/// Horarios de atención. Un turno puede cruzar la medianoche (20:00 a 01:00).
///
/// Sin ningún horario cargado, el local se guía solo por el interruptor de
/// pausa del inicio.
class HorariosPage extends ConsumerStatefulWidget {
  const HorariosPage({super.key});

  @override
  ConsumerState<HorariosPage> createState() => _HorariosPageState();
}

class _Turno {
  _Turno(this.abre, this.cierra);
  TimeOfDay abre;
  TimeOfDay cierra;
}

class _HorariosPageState extends ConsumerState<HorariosPage> {
  /// Turnos por dia (0 = domingo). Null hasta cargar.
  List<List<_Turno>>? _dias;

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parse(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  void _cargar(List<Horario> horarios) {
    _dias = List.generate(7, (d) => [
          for (final h in horarios.where((h) => h.dia == d)) _Turno(_parse(h.abre), _parse(h.cierra)),
        ]);
  }

  Future<void> _guardar() async {
    final lista = <Horario>[];
    for (var d = 0; d < 7; d++) {
      for (final t in _dias![d]) {
        if (_fmt(t.abre) == _fmt(t.cierra)) {
          mostrarError(context, '${Horario.nombresDias[d]}: la apertura y el cierre no pueden ser iguales.');
          return;
        }
        lista.add(Horario(dia: d, abre: _fmt(t.abre), cierra: _fmt(t.cierra)));
      }
    }
    try {
      await ref.read(comerciosRepositoryProvider).guardarHorarios(lista);
      final id = ref.read(sesionProvider).comercioId!;
      ref.invalidate(horariosProvider(id));
      ref.invalidate(comercioActualProvider);
      if (mounted) {
        mostrarAviso(context, 'Horarios guardados');
        context.pop();
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<TimeOfDay?> _elegir(TimeOfDay inicial) => showTimePicker(
        context: context,
        initialTime: inicial,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(sesionProvider).comercioId;
    final horarios = id == null ? const AsyncValue<List<Horario>>.data([]) : ref.watch(horariosProvider(id));

    return MyAsync(
      valor: horarios,
      datos: (h) {
        if (_dias == null) _cargar(h);
        final dias = _dias!;

        Widget dia(int d) => MyCard(
              padding: const EdgeInsets.all(MySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(Horario.nombresDias[d], style: MyType.headlineSm)),
                      if (dias[d].isEmpty) Text('Cerrado', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                      IconButton(
                        tooltip: 'Agregar turno',
                        icon: const Icon(Symbols.add_circle, color: MyColors.onSurface, fill: 1),
                        onPressed: () => setState(() => dias[d].add(
                              dias[d].isEmpty
                                  ? _Turno(const TimeOfDay(hour: 11, minute: 0), const TimeOfDay(hour: 15, minute: 0))
                                  : _Turno(const TimeOfDay(hour: 20, minute: 0), const TimeOfDay(hour: 0, minute: 30)),
                            )),
                      ),
                    ],
                  ),
                  for (final t in dias[d])
                    Padding(
                      padding: const EdgeInsets.only(top: MySpacing.xxs),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: MySpacing.xs,
                        runSpacing: MySpacing.xxs,
                        children: [
                          _Hora(
                            texto: _fmt(t.abre),
                            onTap: () async {
                              final n = await _elegir(t.abre);
                              if (n != null) setState(() => t.abre = n);
                            },
                          ),
                          const Text('a'),
                          _Hora(
                            texto: _fmt(t.cierra),
                            onTap: () async {
                              final n = await _elegir(t.cierra);
                              if (n != null) setState(() => t.cierra = n);
                            },
                          ),
                          if (_fmt(t.cierra).compareTo(_fmt(t.abre)) < 0) const MyBadge('cruza medianoche', tone: MyBadgeTone.info),
                          IconButton(
                            tooltip: 'Quitar turno',
                            icon: const Icon(Symbols.close, size: 20, color: MyColors.secondary),
                            onPressed: () => setState(() => dias[d].remove(t)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );

        // Lunes primero, que es como se piensa la semana.
        const orden = [1, 2, 3, 4, 5, 6, 0];
        return MyPagina(
          volver: () => context.canPop() ? context.pop() : context.go('/local/cuenta'),
          rotulo: 'Mi local',
          titulo: 'Horarios de atención',
          bajada: 'Los clientes solo pueden pedirte dentro de estos horarios',
          anchoMaximo: 1080,
          conDock: false,
          acciones: [
            MyBoton(
              label: 'Copiar lunes a viernes',
              icon: Symbols.content_copy,
              tipo: MyBotonTipo.secundario,
              onPressed: () => setState(() {
                for (final d in [2, 3, 4, 5]) {
                  dias[d] = [for (final t in dias[1]) _Turno(t.abre, t.cierra)];
                }
              }),
            ),
            if (!context.esMovil) MyBoton(label: 'Guardar horarios', icon: Symbols.save, onPressed: _guardar),
          ],
          children: [
            MyCard(
              color: MyColors.secondaryContainer.withValues(alpha: 0.5),
              shadows: const [],
              padding: const EdgeInsets.all(MySpacing.md),
              child: Row(
                children: [
                  const Icon(Symbols.nightlight, color: MyColors.onSecondaryFixedVariant),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Text(
                      'Si un turno termina después de medianoche (ej: 20:00 a 01:00), cargalo en el día que empieza.',
                      style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixedVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MySpacing.md),
            if (context.esMovil) ...[
              for (final d in orden) ...[dia(d), const SizedBox(height: MySpacing.xs)],
              const SizedBox(height: MySpacing.md),
              MyBotonAccion(label: 'Guardar horarios', icon: Symbols.save, onPressed: _guardar),
            ] else
              MyGrilla(anchoMinimo: 380, maxColumnas: 2, espacio: MySpacing.sm, children: [for (final d in orden) dia(d)]),
          ],
        );
      },
    );
  }
}

class _Hora extends StatelessWidget {
  const _Hora({required this.texto, required this.onTap});

  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MyColors.secondaryContainer,
      borderRadius: BorderRadius.circular(MyRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MyRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.xs),
          child: Text(texto, style: MyType.headlineSm),
        ),
      ),
    );
  }
}
