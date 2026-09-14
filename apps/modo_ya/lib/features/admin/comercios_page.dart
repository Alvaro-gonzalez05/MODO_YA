import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/credenciales.dart';
import 'admin_shell.dart';

enum _Filtro { todos, abiertos, suspendidos, sinUbicacion }

/// Locales: padrón con búsqueda y filtros, ficha al costado (PC) o en una hoja
/// (celular), alta, suspensión y contraseña nueva.
class AdminComerciosPage extends ConsumerStatefulWidget {
  const AdminComerciosPage({super.key});

  @override
  ConsumerState<AdminComerciosPage> createState() => _AdminComerciosPageState();
}

class _AdminComerciosPageState extends ConsumerState<AdminComerciosPage> {
  var _busqueda = '';
  var _filtro = _Filtro.todos;
  String? _seleccionado;

  bool _pasa(Comercio c, _Filtro f) => switch (f) {
        _Filtro.todos => true,
        _Filtro.abiertos => c.aprobacion.puedeOperar && c.abierto,
        _Filtro.suspendidos => !c.aprobacion.puedeOperar,
        _Filtro.sinUbicacion => !c.direccion.tieneCoordenadas,
      };

  void _abrir(Comercio c) {
    if (context.esEscritorio) {
      setState(() => _seleccionado = c.id);
    } else {
      mostrarPanelComoHoja(context, (_) => _FichaLocal(comercioId: c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final comercios = ref.watch(todosLosComerciosProvider);

    return MyPagina(
      rotulo: 'Malargüe',
      titulo: 'Locales',
      bajada: 'Padrón de locales, estado y datos de acceso',
      onRefresh: () => ref.refresh(todosLosComerciosProvider.future),
      acciones: [
        MyBoton(
          label: 'Nuevo local',
          icon: Symbols.add_business,
          onPressed: () => context.go('/admin/locales/nuevo'),
        ),
      ],
      children: [
        MyAsync(
          valor: comercios,
          onReintentar: () => ref.invalidate(todosLosComerciosProvider),
          datos: (todos) {
            if (todos.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.storefront,
                  title: 'Todavía no hay locales',
                  message: 'Creá el primero con "Nuevo local". Queda aprobado y listo para usar.',
                  action: MyBoton(
                    label: 'Nuevo local',
                    icon: Symbols.add_business,
                    onPressed: () => context.go('/admin/locales/nuevo'),
                  ),
                ),
              );
            }

            final q = _busqueda.trim().toLowerCase();
            final lista = todos
                .where((c) => _pasa(c, _filtro))
                .where((c) => q.isEmpty || '${c.nombre} ${c.rubro} ${c.direccion.calle} ${c.telefono}'.toLowerCase().contains(q))
                .toList();
            final seleccionado = todos.where((c) => c.id == _seleccionado).firstOrNull;

            final filtros = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyBuscador(hint: 'Buscar por nombre, rubro, dirección o teléfono', onChanged: (t) => setState(() => _busqueda = t)),
                const SizedBox(height: MySpacing.sm),
                MyFiltros<_Filtro>(
                  seleccionado: _filtro,
                  onChanged: (f) => setState(() => _filtro = f),
                  opciones: [
                    (_Filtro.todos, 'Todos', todos.length),
                    (_Filtro.abiertos, 'Abiertos', todos.where((c) => _pasa(c, _Filtro.abiertos)).length),
                    (_Filtro.suspendidos, 'Suspendidos', todos.where((c) => _pasa(c, _Filtro.suspendidos)).length),
                    (_Filtro.sinUbicacion, 'Sin ubicación', todos.where((c) => _pasa(c, _Filtro.sinUbicacion)).length),
                  ],
                ),
                const SizedBox(height: MySpacing.lg),
              ],
            );

            final Widget contenido;
            if (lista.isEmpty) {
              contenido = const MyCard(
                child: MyEmptyState(icon: Symbols.search_off, title: 'Sin resultados', message: 'Probá con otra búsqueda o filtro.'),
              );
            } else if (context.esMovil) {
              contenido = Column(
                children: [
                  for (final c in lista) ...[
                    _TarjetaLocal(comercio: c, onTap: () => _abrir(c)),
                    const SizedBox(height: MySpacing.sm),
                  ],
                ],
              );
            } else {
              contenido = MyTabla(
                columnas: [
                  const MyColumna('Local / rubro', flex: 3),
                  const MyColumna('Dirección', flex: 3),
                  if (context.esEscritorio && seleccionado == null) const MyColumna('Teléfono', flex: 2),
                  const MyColumna('Estado', flex: 2, alDerecha: true),
                ],
                filas: [
                  for (final c in lista)
                    MyFila(
                      seleccionada: c.id == _seleccionado,
                      onTap: () => _abrir(c),
                      celdas: [
                        MyCeldaDoble(c.nombre, bajada: c.rubro, inicio: MyImagen(url: c.logoUrl, ancho: 44, alto: 44, icono: Symbols.storefront)),
                        MyCeldaDoble(
                          c.direccion.calle,
                          bajada: c.direccion.tieneCoordenadas ? c.direccion.referencia : 'Sin ubicación en el mapa',
                        ),
                        if (context.esEscritorio && seleccionado == null) Text(c.telefono, style: MyType.bodyMd),
                        _EstadoLocal(comercio: c),
                      ],
                    ),
                ],
                pie: Text(
                  'Mostrando ${lista.length} de ${todos.length} locales',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filtros,
                MyConPanel(
                  principal: contenido,
                  panel: seleccionado == null
                      ? null
                      : MyCard(
                          child: _FichaLocal(
                            comercioId: seleccionado.id,
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

class _EstadoLocal extends StatelessWidget {
  const _EstadoLocal({required this.comercio});

  final Comercio comercio;

  @override
  Widget build(BuildContext context) {
    final c = comercio;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: MySpacing.xxs,
      runSpacing: MySpacing.xxs,
      children: [
        if (!c.aprobacion.puedeOperar)
          MyBadge(c.aprobacion.label, tone: tonoAprobacion(c.aprobacion))
        else
          MyBadge(
            c.abierto ? 'Abierto' : 'Cerrado',
            tone: c.abierto ? MyBadgeTone.success : MyBadgeTone.info,
            dot: true,
          ),
        if (!c.direccion.tieneCoordenadas) const MyBadge('Sin ubicación', tone: MyBadgeTone.danger),
      ],
    );
  }
}

class _TarjetaLocal extends StatelessWidget {
  const _TarjetaLocal({required this.comercio, required this.onTap});

  final Comercio comercio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = comercio;
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          MyImagen(url: c.logoUrl, ancho: 52, alto: 52, icono: Symbols.storefront),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.nombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${c.rubro} · ${c.direccion.calle}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: MySpacing.xs),
                Align(alignment: Alignment.centerLeft, child: _EstadoLocal(comercio: c)),
              ],
            ),
          ),
          const Icon(Symbols.chevron_right, color: MyColors.secondary),
        ],
      ),
    );
  }
}

/// Ficha del local: se usa en el panel lateral y en la hoja del celular.
/// Lee el local del provider para reflejar los cambios al instante.
class _FichaLocal extends ConsumerWidget {
  const _FichaLocal({required this.comercioId, this.onCerrar});

  final String comercioId;
  final VoidCallback? onCerrar;

  Future<void> _cambiar(BuildContext context, WidgetRef ref, Comercio c, EstadoAprobacion estado) async {
    String? motivo;
    if (estado == EstadoAprobacion.suspendido) {
      motivo = await pedirTexto(
        context,
        titulo: 'Suspender ${c.nombre}',
        label: 'Motivo (lo ve la administración)',
        aceptar: 'Suspender',
      );
      if (motivo == null) return;
    }
    try {
      await ref.read(comerciosRepositoryProvider).cambiarAprobacion(c.id, estado, motivo: motivo);
      ref.invalidate(todosLosComerciosProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(todosLosComerciosProvider).value?.where((x) => x.id == comercioId).firstOrNull;
    if (c == null) return const SizedBox();
    final operando = c.aprobacion.puedeOperar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MyImagen(url: c.logoUrl, ancho: 64, alto: 64, radio: MyRadius.lg, icono: Symbols.storefront),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.nombre, style: MyType.headlineMd),
                  Text(c.rubro, style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
                  const SizedBox(height: MySpacing.xs),
                  _EstadoLocal(comercio: c),
                ],
              ),
            ),
            if (onCerrar != null)
              IconButton(onPressed: onCerrar, icon: const Icon(Symbols.close), tooltip: 'Cerrar'),
          ],
        ),
        const SizedBox(height: MySpacing.lg),
        DatosDeAcceso(comercioId: c.id, nombre: c.nombre, telefono: c.telefono),
        const SizedBox(height: MySpacing.md),
        MyDato('Teléfono', c.telefono, icono: Symbols.call),
        MyDato('Dirección de retiro', c.direccion.calle, icono: Symbols.location_on),
        if ((c.direccion.referencia ?? '').isNotEmpty) MyDato('Referencia', c.direccion.referencia!, icono: Symbols.pin_drop),
        MyDato('Demora estimada', '${c.demoraEstimadaMin} min', icono: Symbols.timer),
        if (c.direccion.tieneCoordenadas) ...[
          const SizedBox(height: MySpacing.sm),
          MyMapaVista(
            alto: 170,
            radio: MyRadius.lg,
            marcadores: [
              MyMarcador(punto: LatLng(c.direccion.lat!, c.direccion.lng!), icono: Symbols.storefront),
            ],
          ),
        ],
        const SizedBox(height: MySpacing.lg),
        if (operando)
          MyBoton(
            label: 'Suspender cuenta',
            icon: Symbols.block,
            tipo: MyBotonTipo.peligro,
            onPressed: () => _cambiar(context, ref, c, EstadoAprobacion.suspendido),
          )
        else
          MyBoton(
            label: c.aprobacion == EstadoAprobacion.pendiente ? 'Aprobar y habilitar' : 'Reactivar cuenta',
            icon: Symbols.verified,
            onPressed: () => _cambiar(context, ref, c, EstadoAprobacion.aprobado),
          ),
      ],
    );
  }
}
