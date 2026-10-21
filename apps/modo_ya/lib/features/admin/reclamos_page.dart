import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/reclamos.dart';

enum _Filtro { pendientes, abiertos, enRevision, cerrados, todos }

/// Reclamos: lo que entra de clientes, locales y riders. Se toma, se responde
/// y se cierra. Antes esto no existía en ninguna pantalla y la tabla, el
/// trigger y `admin_resolver_reclamo` estaban desde 0004 sin usar.
class AdminReclamosPage extends ConsumerStatefulWidget {
  const AdminReclamosPage({super.key});

  @override
  ConsumerState<AdminReclamosPage> createState() => _AdminReclamosPageState();
}

class _AdminReclamosPageState extends ConsumerState<AdminReclamosPage> {
  var _filtro = _Filtro.pendientes;
  var _busqueda = '';

  bool _pasa(Reclamo r, _Filtro f) => switch (f) {
        _Filtro.pendientes => !r.estado.esCerrado,
        _Filtro.abiertos => r.estado == EstadoReclamo.abierto,
        _Filtro.enRevision => r.estado == EstadoReclamo.enRevision,
        _Filtro.cerrados => r.estado.esCerrado,
        _Filtro.todos => true,
      };

  @override
  Widget build(BuildContext context) {
    final reclamos = ref.watch(reclamosProvider);

    return MyPagina(
      rotulo: 'Atención',
      titulo: 'Reclamos',
      bajada: 'Lo que nos escriben los clientes, los locales y los riders',
      onRefresh: () => ref.refresh(reclamosProvider.future),
      children: [
        MyAsync(
          valor: reclamos,
          onReintentar: () => ref.invalidate(reclamosProvider),
          datos: (todos) {
            if (todos.isEmpty) {
              return const MyCard(
                child: MyEmptyState(
                  icon: Symbols.support_agent,
                  title: 'Ningún reclamo',
                  message: 'Cuando un cliente, un local o un rider abra uno, aparece acá.',
                ),
              );
            }

            final q = _busqueda.trim().toLowerCase();
            final lista = todos
                .where((r) => _pasa(r, _filtro))
                .where((r) => q.isEmpty ||
                    '${r.motivo} ${r.detalle ?? ''} ${r.abiertoPorNombre ?? ''} ${r.pedidoCodigo ?? ''} ${r.envioCodigo ?? ''}'
                        .toLowerCase()
                        .contains(q))
                .toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MyBuscador(
                  hint: 'Buscar por motivo, quién lo abrió o código de pedido',
                  onChanged: (t) => setState(() => _busqueda = t),
                ),
                const SizedBox(height: MySpacing.sm),
                MyFiltros<_Filtro>(
                  seleccionado: _filtro,
                  onChanged: (f) => setState(() => _filtro = f),
                  opciones: [
                    (_Filtro.pendientes, 'Sin resolver', todos.where((r) => !r.estado.esCerrado).length),
                    (_Filtro.abiertos, 'Nuevos', todos.where((r) => r.estado == EstadoReclamo.abierto).length),
                    (_Filtro.enRevision, 'En revisión', todos.where((r) => r.estado == EstadoReclamo.enRevision).length),
                    (_Filtro.cerrados, 'Cerrados', todos.where((r) => r.estado.esCerrado).length),
                    (_Filtro.todos, 'Todos', todos.length),
                  ],
                ),
                const SizedBox(height: MySpacing.lg),
                if (lista.isEmpty)
                  const MyCard(
                    child: MyEmptyState(
                      icon: Symbols.check_circle,
                      title: 'Nada para atender acá',
                      message: 'Probá con otro filtro o con otra búsqueda.',
                    ),
                  )
                else
                  for (final r in lista) ...[
                    _Reclamo(reclamo: r),
                    const SizedBox(height: MySpacing.sm),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Reclamo extends ConsumerStatefulWidget {
  const _Reclamo({required this.reclamo});

  final Reclamo reclamo;

  @override
  ConsumerState<_Reclamo> createState() => _ReclamoState();
}

class _ReclamoState extends ConsumerState<_Reclamo> {
  var _trabajando = false;

  Reclamo get r => widget.reclamo;

  /// `admin_resolver_reclamo` escribe `resolucion` siempre, así que mover un
  /// reclamo sin texto le borraría al que reclamó la respuesta que ya leyó.
  /// Por eso cuando no hay texto nuevo se reenvía el que estaba.
  Future<void> _mover(EstadoReclamo estado, {String? resolucion}) async {
    setState(() => _trabajando = true);
    try {
      await ref
          .read(reclamosRepositoryProvider)
          .resolver(r.id, estado, resolucion: resolucion ?? r.resolucion);
      ref.invalidate(reclamosProvider);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// Cerrar un reclamo pide siempre un texto: es lo único que el que reclamó
  /// va a leer, y sin eso le queda un "Resuelto" sin explicación.
  Future<void> _cerrar(EstadoReclamo estado) async {
    final resuelto = estado == EstadoReclamo.resuelto;
    final texto = await pedirTexto(
      context,
      titulo: resuelto ? 'Responder y cerrar' : 'No tomar el reclamo',
      label: resuelto
          ? 'Qué le decís a ${r.abiertoPorNombre ?? 'quien reclamó'}'
          : 'Por qué no se toma (lo lee quien reclamó)',
      aceptar: resuelto ? 'Responder y cerrar' : 'Desestimar',
      inicial: r.resolucion,
    );
    if (texto == null) return;
    await _mover(estado, resolucion: texto);
  }

  @override
  Widget build(BuildContext context) {
    final rol = switch (r.rolOrigen) {
      RolUsuario.cliente => 'un cliente',
      RolUsuario.comercio => 'un local',
      RolUsuario.repartidor => 'un rider',
      RolUsuario.admin => 'la administración',
    };
    final sobre = r.sobreQue;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MyAvatar(nombre: r.abiertoPorNombre ?? '?', size: 40),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.motivo, style: MyType.headlineSm),
                    Text(
                      [
                        '${r.abiertoPorNombre ?? 'Alguien'} ($rol)',
                        if (sobre != null) 'sobre $sobre',
                        Formato.haceCuanto(r.creadoEn),
                      ].join(' · '),
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MySpacing.xs),
              MyBadge(r.estado.label, tone: tonoReclamo(r.estado), dot: !r.estado.esCerrado),
            ],
          ),
          if (r.detalle != null) ...[
            const SizedBox(height: MySpacing.sm),
            Text('«${r.detalle}»', style: MyType.bodyMd),
          ],
          if (r.resolucion != null) ...[
            const SizedBox(height: MySpacing.sm),
            MyDato('Lo que le contestamos', r.resolucion!, icono: Symbols.reply),
          ],
          const SizedBox(height: MySpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              if (r.estado.esCerrado)
                MyBoton(
                  label: 'Volver a abrir',
                  icon: Symbols.undo,
                  tipo: MyBotonTipo.texto,
                  onPressed: _trabajando ? null : () => _mover(EstadoReclamo.abierto),
                )
              else ...[
                MyBoton(
                  label: 'Desestimar',
                  icon: Symbols.block,
                  tipo: MyBotonTipo.texto,
                  onPressed: _trabajando ? null : () => _cerrar(EstadoReclamo.desestimado),
                ),
                if (r.estado == EstadoReclamo.abierto)
                  MyBoton(
                    label: 'Lo estoy viendo',
                    icon: Symbols.visibility,
                    tipo: MyBotonTipo.secundario,
                    onPressed: _trabajando ? null : () => _mover(EstadoReclamo.enRevision),
                  ),
                MyBoton(
                  label: 'Responder y cerrar',
                  icon: Symbols.check,
                  onPressed: _trabajando ? null : () => _cerrar(EstadoReclamo.resuelto),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
