import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/estados_ui.dart';
import 'widgets/envio_tile.dart';

enum _Filtro { todos, enCurso, entregados, cancelados }

/// Envíos del local (A11): los de la cadetería y los de pedidos de la app,
/// con lo que pagó el local.
class HistorialPage extends ConsumerStatefulWidget {
  const HistorialPage({super.key});

  @override
  ConsumerState<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends ConsumerState<HistorialPage> {
  var _filtro = _Filtro.todos;

  bool _pasa(Envio e, _Filtro f) => switch (f) {
        _Filtro.todos => true,
        _Filtro.enCurso => e.estado.esActivo,
        _Filtro.entregados => e.estado == EstadoEnvio.entregado,
        _Filtro.cancelados => e.estado == EstadoEnvio.cancelado || e.estado == EstadoEnvio.sinRepartidor,
      };

  @override
  Widget build(BuildContext context) {
    final envios = ref.watch(enviosDelComercioProvider);
    final puede = ref.watch(comercioActualProvider).value?.puedePedirEnvios ?? false;

    return MyPagina(
      rotulo: 'Cadetería',
      titulo: 'Envíos',
      bajada: 'Tus últimos 100 envíos, con lo que pagaste',
      onRefresh: () => ref.refresh(enviosDelComercioProvider.future),
      acciones: [
        MyBoton(
          label: 'Pedir un rider',
          icon: Symbols.sports_motorsports,
          onPressed: puede ? () => context.go('/local/envios/nuevo') : null,
        ),
      ],
      children: [
        MyAsync(
          valor: envios,
          onReintentar: () => ref.invalidate(enviosDelComercioProvider),
          datos: (todos) {
            final entregados = todos.where((e) => e.estado == EstadoEnvio.entregado).toList();
            final pagueYo = entregados
                .where((e) => e.quienPaga == QuienPaga.comercio && e.pedidoId == null)
                .fold<int>(0, (s, e) => s + e.total);
            final lista = todos.where((e) => _pasa(e, _filtro)).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyGrilla(
                  anchoMinimo: context.esMovil ? 150 : 220,
                  maxColumnas: 3,
                  children: [
                    MyKpi(rotulo: 'Envíos', valor: '${todos.length}', icono: Symbols.sports_motorsports, detalle: 'Cadetería y app'),
                    MyKpi(
                      rotulo: 'Entregados',
                      valor: '${entregados.length}',
                      icono: Symbols.task_alt,
                      progreso: todos.isEmpty ? 0 : entregados.length / todos.length,
                    ),
                    MyKpi(rotulo: 'Pagaste vos', valor: Formato.pesos(pagueYo), icono: Symbols.payments, detalle: 'Envíos de cadetería'),
                  ],
                ),
                const SizedBox(height: MySpacing.lg),
                MyFiltros<_Filtro>(
                  seleccionado: _filtro,
                  onChanged: (f) => setState(() => _filtro = f),
                  opciones: [
                    (_Filtro.todos, 'Todos', todos.length),
                    (_Filtro.enCurso, 'En curso', todos.where((e) => _pasa(e, _Filtro.enCurso)).length),
                    (_Filtro.entregados, 'Entregados', entregados.length),
                    (_Filtro.cancelados, 'Cancelados', todos.where((e) => _pasa(e, _Filtro.cancelados)).length),
                  ],
                ),
                const SizedBox(height: MySpacing.md),
                if (lista.isEmpty)
                  const MyCard(
                    child: MyEmptyState(
                      icon: Symbols.receipt_long,
                      title: 'No hay envíos acá',
                      message: 'Se arma solo a medida que pedís riders o te llegan pedidos.',
                    ),
                  )
                else if (context.esMovil)
                  for (final e in lista) ...[
                    EnvioTile(envio: e, onTap: () => context.go('/local/envios/${e.id}')),
                    const SizedBox(height: MySpacing.sm),
                  ]
                else
                  MyTabla(
                    columnas: [
                      const MyColumna('Envío'),
                      const MyColumna('Fecha'),
                      const MyColumna('Destino', flex: 3),
                      if (context.esEscritorio) const MyColumna('Rider', flex: 2),
                      if (context.esEscritorio) const MyColumna('Paga'),
                      const MyColumna('Total', alDerecha: true),
                      const MyColumna('Estado', flex: 2, alDerecha: true),
                    ],
                    filas: [
                      for (final e in lista)
                        MyFila(
                          onTap: () => context.go('/local/envios/${e.id}'),
                          celdas: [
                            MyCeldaDoble(e.codigo, bajada: e.pedidoId != null ? 'App' : 'Cadetería'),
                            MyCeldaDoble(Formato.fechaCorta(e.creadoEn), bajada: Formato.hora(e.creadoEn)),
                            MyCeldaDoble(e.destino.calle, bajada: e.cliente.nombre),
                            if (context.esEscritorio)
                              Text(e.repartidorNombre ?? '—', style: MyType.bodyMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (context.esEscritorio)
                              Text(e.quienPaga == QuienPaga.comercio ? 'Vos' : 'Cliente', style: MyType.bodyMd),
                            Text(Formato.pesos(e.total), style: MyType.labelLg),
                            MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: e.estado.esActivo),
                          ],
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
