import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/credenciales.dart';
import 'admin_shell.dart';

enum _Filtro { todos, conectados, enServicio, suspendidos }

/// Riders: quién está conectado, ficha con su última ubicación, alta,
/// suspensión y contraseña nueva.
class AdminRepartidoresPage extends ConsumerStatefulWidget {
  const AdminRepartidoresPage({super.key});

  @override
  ConsumerState<AdminRepartidoresPage> createState() => _AdminRepartidoresPageState();
}

class _AdminRepartidoresPageState extends ConsumerState<AdminRepartidoresPage> {
  var _busqueda = '';
  var _filtro = _Filtro.todos;
  String? _seleccionado;

  bool _pasa(Repartidor r, _Filtro f) => switch (f) {
        _Filtro.todos => true,
        _Filtro.conectados => r.conectado,
        _Filtro.enServicio => r.ocupado,
        _Filtro.suspendidos => !r.aprobacion.puedeOperar,
      };

  void _abrir(Repartidor r) {
    if (context.esEscritorio) {
      setState(() => _seleccionado = r.id);
    } else {
      mostrarPanelComoHoja(context, (_) => _FichaRider(riderId: r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final riders = ref.watch(todosLosRepartidoresProvider);

    return MyPagina(
      rotulo: 'Flota',
      titulo: 'Riders',
      bajada: 'Quién está conectado ahora, fichas y datos de acceso',
      onRefresh: () => ref.refresh(todosLosRepartidoresProvider.future),
      acciones: [
        MyBoton(
          label: 'Nuevo rider',
          icon: Symbols.person_add,
          onPressed: () => context.go('/admin/riders/nuevo'),
        ),
      ],
      children: [
        MyAsync(
          valor: riders,
          onReintentar: () => ref.invalidate(todosLosRepartidoresProvider),
          datos: (todos) {
            if (todos.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.sports_motorsports,
                  title: 'Todavía no hay riders',
                  message: 'Creá el primero con "Nuevo rider". Entra con esos datos en la app MODO YA Rider.',
                  action: MyBoton(
                    label: 'Nuevo rider',
                    icon: Symbols.person_add,
                    onPressed: () => context.go('/admin/riders/nuevo'),
                  ),
                ),
              );
            }

            final q = _busqueda.trim().toLowerCase();
            final lista = todos
                .where((r) => _pasa(r, _filtro))
                .where((r) => q.isEmpty || '${r.nombre} ${r.telefono} ${r.vehiculo.label}'.toLowerCase().contains(q))
                .toList();
            final seleccionado = todos.where((r) => r.id == _seleccionado).firstOrNull;

            final Widget contenido;
            if (lista.isEmpty) {
              contenido = const MyCard(
                child: MyEmptyState(icon: Symbols.search_off, title: 'Sin resultados', message: 'Probá con otra búsqueda o filtro.'),
              );
            } else if (context.esMovil) {
              contenido = Column(
                children: [
                  for (final r in lista) ...[
                    MyCard(
                      padding: const EdgeInsets.all(MySpacing.md),
                      onTap: () => _abrir(r),
                      child: Row(
                        children: [
                          _AvatarRider(rider: r),
                          const SizedBox(width: MySpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.nombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(
                                  '${r.vehiculo.label} · ${r.viajesCompletados} viajes',
                                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                                ),
                                const SizedBox(height: MySpacing.xs),
                                _EstadoRider(rider: r),
                              ],
                            ),
                          ),
                          Icon(Symbols.chevron_right, color: MyColors.secondary),
                        ],
                      ),
                    ),
                    const SizedBox(height: MySpacing.sm),
                  ],
                ],
              );
            } else {
              final compacta = seleccionado != null || !context.esEscritorio;
              contenido = MyTabla(
                columnas: [
                  const MyColumna('Rider', flex: 3),
                  if (!compacta) const MyColumna('Teléfono', flex: 2),
                  const MyColumna('Viajes'),
                  const MyColumna('Estado', flex: 2, alDerecha: true),
                ],
                filas: [
                  for (final r in lista)
                    MyFila(
                      seleccionada: r.id == _seleccionado,
                      onTap: () => _abrir(r),
                      celdas: [
                        MyCeldaDoble(r.nombre, bajada: r.vehiculo.label, inicio: _AvatarRider(rider: r)),
                        if (!compacta) Text(r.telefono, style: MyType.bodyMd),
                        Text('${r.viajesCompletados}', style: MyType.labelLg),
                        _EstadoRider(rider: r),
                      ],
                    ),
                ],
                pie: Text(
                  'Mostrando ${lista.length} de ${todos.length} riders',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyBuscador(hint: 'Buscar por nombre, teléfono o vehículo', onChanged: (t) => setState(() => _busqueda = t)),
                const SizedBox(height: MySpacing.sm),
                MyFiltros<_Filtro>(
                  seleccionado: _filtro,
                  onChanged: (f) => setState(() => _filtro = f),
                  opciones: [
                    (_Filtro.todos, 'Todos', todos.length),
                    (_Filtro.conectados, 'Conectados', todos.where((r) => r.conectado).length),
                    (_Filtro.enServicio, 'En servicio', todos.where((r) => r.ocupado).length),
                    (_Filtro.suspendidos, 'Suspendidos', todos.where((r) => !r.aprobacion.puedeOperar).length),
                  ],
                ),
                const SizedBox(height: MySpacing.lg),
                MyConPanel(
                  principal: contenido,
                  panel: seleccionado == null
                      ? null
                      : MyCard(
                          child: _FichaRider(
                            riderId: seleccionado.id,
                            onCerrar: () => setState(() => _seleccionado = null),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AvatarRider extends StatelessWidget {
  const _AvatarRider({required this.rider});

  final Repartidor rider;

  @override
  Widget build(BuildContext context) {
    return MyIconoCaja(
      Symbols.sports_motorsports,
      circular: true,
      tamano: 44,
      fondo: rider.conectado ? MyColors.successContainer : MyColors.surfaceContainerHigh,
      color: rider.conectado ? MyColors.success : MyColors.secondary,
    );
  }
}

class _EstadoRider extends StatelessWidget {
  const _EstadoRider({required this.rider});

  final Repartidor rider;

  @override
  Widget build(BuildContext context) {
    final r = rider;
    if (!r.aprobacion.puedeOperar) return MyBadge(r.aprobacion.label, tone: tonoAprobacion(r.aprobacion));
    return MyBadge(
      r.ocupado ? 'En servicio' : (r.conectado ? 'Conectado' : 'Desconectado'),
      tone: r.ocupado ? MyBadgeTone.ember : (r.conectado ? MyBadgeTone.success : MyBadgeTone.info),
      dot: true,
    );
  }
}

class _FichaRider extends ConsumerWidget {
  const _FichaRider({required this.riderId, this.onCerrar});

  final String riderId;
  final VoidCallback? onCerrar;

  Future<void> _cambiar(BuildContext context, WidgetRef ref, Repartidor r, EstadoAprobacion estado) async {
    String? motivo;
    if (estado == EstadoAprobacion.suspendido) {
      motivo = await pedirTexto(context, titulo: 'Suspender a ${r.nombre}', label: 'Motivo', aceptar: 'Suspender');
      if (motivo == null) return;
    }
    try {
      await ref.read(repartidoresRepositoryProvider).cambiarAprobacion(r.id, estado, motivo: motivo);
      ref.invalidate(todosLosRepartidoresProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(todosLosRepartidoresProvider).value?.where((x) => x.id == riderId).firstOrNull;
    if (r == null) return const SizedBox();
    final ubicacion = r.ubicacion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MyIconoCaja(
              Symbols.sports_motorsports,
              tamano: 64,
              fondo: r.conectado ? MyColors.successContainer : MyColors.primary,
              color: r.conectado ? MyColors.success : MyColors.onPrimary,
            ),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.nombre, style: MyType.headlineMd),
                  Text(r.vehiculo.label, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  const SizedBox(height: MySpacing.xs),
                  _EstadoRider(rider: r),
                ],
              ),
            ),
            if (onCerrar != null) IconButton(onPressed: onCerrar, icon: const Icon(Symbols.close), tooltip: 'Cerrar'),
          ],
        ),
        const SizedBox(height: MySpacing.lg),
        Row(
          children: [
            Expanded(
              child: MyStatTile(value: '${r.viajesCompletados}', label: 'Viajes', icon: Symbols.route),
            ),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: MyStatTile(
                value: r.reputacion > 0 ? r.reputacion.toStringAsFixed(1) : '—',
                label: 'Reputación',
                icon: Symbols.star,
              ),
            ),
          ],
        ),
        const SizedBox(height: MySpacing.md),
        DatosDeAcceso(repartidorId: r.id, nombre: r.nombre, telefono: r.telefono),
        const SizedBox(height: MySpacing.md),
        MyDato('Teléfono', r.telefono, icono: Symbols.call),
        if (ubicacion != null && ubicacion.tieneCoordenadas) ...[
          MyDato(
            'Última ubicación',
            r.ubicacionEn == null ? 'Sin fecha' : Formato.haceCuanto(r.ubicacionEn!),
            icono: Symbols.my_location,
          ),
          const SizedBox(height: MySpacing.xs),
          MyMapaVista(
            alto: 170,
            radio: MyRadius.lg,
            marcadores: [
              MyMarcador(
                punto: LatLng(ubicacion.lat!, ubicacion.lng!),
                icono: Symbols.sports_motorsports,
                color: r.ocupado ? MyColors.primary : MyColors.success,
              ),
            ],
          ),
        ],
        const SizedBox(height: MySpacing.lg),
        if (r.aprobacion.puedeOperar)
          MyBoton(
            label: 'Suspender cuenta',
            icon: Symbols.block,
            tipo: MyBotonTipo.peligro,
            onPressed: () => _cambiar(context, ref, r, EstadoAprobacion.suspendido),
          )
        else
          MyBoton(
            label: r.aprobacion == EstadoAprobacion.pendiente ? 'Aprobar y habilitar' : 'Reactivar cuenta',
            icon: Symbols.verified,
            onPressed: () => _cambiar(context, ref, r, EstadoAprobacion.aprobado),
          ),
      ],
    );
  }
}
