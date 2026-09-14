import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Envíos en la calle, en vivo, con su recorrido y el reparto del dinero.
class AdminEnviosPage extends ConsumerStatefulWidget {
  const AdminEnviosPage({super.key});

  @override
  ConsumerState<AdminEnviosPage> createState() => _AdminEnviosPageState();
}

class _AdminEnviosPageState extends ConsumerState<AdminEnviosPage> {
  String? _seleccionado;

  void _abrir(Envio e) {
    if (context.esEscritorio) {
      setState(() => _seleccionado = e.id);
    } else {
      mostrarPanelComoHoja(context, (_) => _FichaEnvio(envioId: e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final activos = ref.watch(enviosActivosProvider);

    return MyPagina(
      rotulo: 'Trazabilidad',
      titulo: 'Envíos',
      bajada: 'Todo lo que está en la calle, en vivo',
      children: [
        MyAsync(
          valor: activos,
          onReintentar: () => ref.invalidate(enviosActivosProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return const MyCard(
                child: MyEmptyState(
                  icon: Symbols.route,
                  title: 'No hay envíos activos',
                  message: 'Se actualiza solo cuando un local pide un rider o acepta un pedido.',
                ),
              );
            }
            final seleccionado = lista.where((e) => e.id == _seleccionado).firstOrNull;

            if (context.esMovil) {
              return Column(
                children: [
                  for (final e in lista) ...[
                    MyCard(
                      padding: const EdgeInsets.all(MySpacing.md),
                      onTap: () => _abrir(e),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(e.codigo, style: MyType.labelLg.copyWith(color: MyColors.primary)),
                              const SizedBox(width: MySpacing.xs),
                              Text(Formato.haceCuanto(e.creadoEn), style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                              const Spacer(),
                              Text(Formato.pesos(e.total), style: MyType.labelLg),
                            ],
                          ),
                          const SizedBox(height: MySpacing.xs),
                          Text(e.comercioNombre, style: MyType.headlineSm),
                          Text('→ ${e.destino.calle}', style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                          const SizedBox(height: MySpacing.xs),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.repartidorNombre ?? 'Sin rider',
                                  style: MyType.bodySm,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: MySpacing.sm),
                  ],
                ],
              );
            }

            final compacta = seleccionado != null || !context.esEscritorio;
            return MyConPanel(
              principal: MyTabla(
                columnas: [
                  const MyColumna('Envío'),
                  const MyColumna('Local', flex: 2),
                  if (!compacta) const MyColumna('Destino', flex: 2),
                  const MyColumna('Rider', flex: 2),
                  if (!compacta) const MyColumna('Total', alDerecha: true),
                  const MyColumna('Estado', flex: 2, alDerecha: true),
                ],
                filas: [
                  for (final e in lista)
                    MyFila(
                      seleccionada: e.id == _seleccionado,
                      onTap: () => _abrir(e),
                      celdas: [
                        MyCeldaDoble(e.codigo, bajada: Formato.hora(e.creadoEn)),
                        Text(e.comercioNombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (!compacta) Text(e.destino.calle, style: MyType.bodyMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          e.repartidorNombre ?? 'Buscando…',
                          style: MyType.bodyMd.copyWith(color: e.repartidorNombre == null ? MyColors.secondary : null),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!compacta) Text(Formato.pesos(e.total), style: MyType.labelLg),
                        MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: true),
                      ],
                    ),
                ],
              ),
              panel: seleccionado == null
                  ? null
                  : MyCard(
                      child: _FichaEnvio(envioId: seleccionado.id, onCerrar: () => setState(() => _seleccionado = null)),
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _FichaEnvio extends ConsumerWidget {
  const _FichaEnvio({required this.envioId, this.onCerrar});

  final String envioId;
  final VoidCallback? onCerrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(enviosActivosProvider).value?.where((x) => x.id == envioId).firstOrNull;
    if (e == null) {
      return const MyEmptyState(icon: Symbols.task_alt, title: 'Este envío terminó', message: 'Ya no está en la calle.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.codigo, style: MyType.headlineMd),
                  Text(
                    'Creado ${Formato.haceCuanto(e.creadoEn)}${e.pedidoId != null ? ' · pedido de la app' : ' · cadetería'}',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  ),
                ],
              ),
            ),
            if (onCerrar != null) IconButton(onPressed: onCerrar, icon: const Icon(Symbols.close), tooltip: 'Cerrar'),
          ],
        ),
        const SizedBox(height: MySpacing.sm),
        Align(alignment: Alignment.centerLeft, child: MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: true)),
        const SizedBox(height: MySpacing.lg),
        MyRouteTimeline(
          stops: [
            MyRouteStop(
              overline: 'Retiro',
              title: e.comercioNombre,
              subtitle: e.origen.calle,
              icon: Symbols.storefront,
            ),
            MyRouteStop(
              overline: 'Entrega',
              title: e.destino.calle,
              subtitle: '${e.cliente.nombre} · ${e.cliente.telefono}',
              icon: Symbols.home,
              iconBackground: MyColors.dock,
            ),
          ],
        ),
        const SizedBox(height: MySpacing.md),
        MyDato('Rider', e.repartidorNombre ?? 'Todavía sin asignar', icono: Symbols.sports_motorsports),
        MyDato('Distancia', Formato.km(e.cotizacion.distanciaKm), icono: Symbols.straighten),
        MyDato('Quién paga', e.quienPaga.label, icono: Symbols.account_balance_wallet),
        const SizedBox(height: MySpacing.sm),
        Container(
          padding: const EdgeInsets.all(MySpacing.md),
          decoration: BoxDecoration(
            color: MyColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(MyRadius.lg),
          ),
          child: Column(
            children: [
              _Linea('Rider', Formato.pesos(e.cotizacion.gananciaRepartidor)),
              _Linea('Comisión MODO YA', Formato.pesos(e.cotizacion.comision)),
              const Divider(height: MySpacing.lg),
              _Linea('Total', Formato.pesos(e.total), fuerte: true),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.lg),
        MyBoton(
          label: 'Cancelar envío',
          icon: Symbols.cancel,
          tipo: MyBotonTipo.peligro,
          onPressed: () async {
            final motivo = await pedirTexto(context, titulo: 'Cancelar ${e.codigo}', label: 'Motivo', aceptar: 'Cancelar envío');
            if (motivo == null) return;
            try {
              await ref.read(enviosRepositoryProvider).cancelar(e.id, motivo);
            } catch (err) {
              if (context.mounted) mostrarError(context, err);
            }
          },
        ),
      ],
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.label, this.valor, {this.fuerte = false});

  final String label;
  final String valor;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: fuerte ? MyType.labelLg : MyType.bodyMd)),
          Text(valor, style: fuerte ? MyType.headlineSm.copyWith(color: MyColors.primary) : MyType.labelLg),
        ],
      ),
    );
  }
}
