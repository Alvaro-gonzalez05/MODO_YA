import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/marca.dart';

/// Horarios de atencion. Un turno puede cruzar la medianoche (20:00 a 01:00).
///
/// Sin ningun horario cargado, el local se guia solo por el interruptor de
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Symbols.arrow_back), onPressed: () => context.pop()),
        title: const Text('Horarios de atencion'),
      ),
      body: MyAsync(
        valor: horarios,
        datos: (h) {
          if (_dias == null) _cargar(h);
          final dias = _dias!;
          return FormularioCentrado(
            ancho: 560,
            children: [
              Text(
                'Los clientes solo pueden pedirte dentro de estos horarios. Si un turno '
                'termina despues de medianoche (ej: 20:00 a 01:00) cargalo en el dia que empieza.',
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
              const SizedBox(height: MySpacing.md),
              // Lunes primero, que es como se piensa la semana.
              for (final d in [1, 2, 3, 4, 5, 6, 0]) ...[
                MyCard(
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
                            icon: const Icon(Symbols.add_circle, color: MyColors.primary),
                            onPressed: () => setState(() => dias[d].add(
                                  dias[d].isEmpty
                                      ? _Turno(const TimeOfDay(hour: 11, minute: 0), const TimeOfDay(hour: 15, minute: 0))
                                      : _Turno(const TimeOfDay(hour: 20, minute: 0), const TimeOfDay(hour: 0, minute: 30)),
                                )),
                          ),
                        ],
                      ),
                      for (final t in dias[d])
                        Row(
                          children: [
                            _Hora(
                              texto: _fmt(t.abre),
                              onTap: () async {
                                final n = await _elegir(t.abre);
                                if (n != null) setState(() => t.abre = n);
                              },
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: MySpacing.xs),
                              child: Text('a'),
                            ),
                            _Hora(
                              texto: _fmt(t.cierra),
                              onTap: () async {
                                final n = await _elegir(t.cierra);
                                if (n != null) setState(() => t.cierra = n);
                              },
                            ),
                            const SizedBox(width: MySpacing.xs),
                            if (_fmt(t.cierra).compareTo(_fmt(t.abre)) < 0)
                              const MyBadge('cruza medianoche', tone: MyBadgeTone.info),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Symbols.close, size: 20, color: MyColors.secondary),
                              onPressed: () => setState(() => dias[d].remove(t)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: MySpacing.xs),
              ],
              const SizedBox(height: MySpacing.md),
              TextButton(
                onPressed: () => setState(() {
                  for (final d in [1, 2, 3, 4, 5]) {
                    dias[d] = [for (final t in dias[1]) _Turno(t.abre, t.cierra)];
                  }
                }),
                child: const Text('Copiar el lunes a toda la semana (lunes a viernes)'),
              ),
              const SizedBox(height: MySpacing.sm),
              MyBotonAccion(label: 'Guardar horarios', icon: Symbols.save, onPressed: _guardar),
              const SizedBox(height: MySpacing.xl),
            ],
          );
        },
      ),
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
