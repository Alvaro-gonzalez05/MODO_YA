import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/reclamos.dart';

enum _Filtro { pendientes, abiertos, enRevision, cerrados, todos }

/// Reclamos: lo que entra de clientes, locales y riders. Tocar uno abre su
/// ficha encima de la lista, y ahí se toma, se responde y se cierra. Antes esto no existía en ninguna pantalla y la tabla, el
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
                    _TarjetaReclamo(reclamo: r, onTap: () => mostrarFichaReclamo(context, r.id)),
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

/// "un cliente", "un local"…: para la frase de quién lo abrió.
String _quien(RolUsuario rol) => switch (rol) {
      RolUsuario.cliente => 'un cliente',
      RolUsuario.comercio => 'un local',
      RolUsuario.repartidor => 'un rider',
      RolUsuario.admin => 'la administración',
    };

/// El reclamo en la lista: quién, sobre qué y en qué está. Lo que se hace con
/// él está en la ficha: con tres botones adentro de cada tarjeta, en el
/// celular la lista era una pared de botones y no se distinguía un reclamo
/// del siguiente.
class _TarjetaReclamo extends StatelessWidget {
  const _TarjetaReclamo({required this.reclamo, required this.onTap});

  final Reclamo reclamo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reclamo;
    final sobre = r.sobreQue;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MyAvatar(nombre: r.abiertoPorNombre ?? '?', size: 40),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.motivo, style: MyType.headlineSm, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(
                  [
                    '${r.abiertoPorNombre ?? 'Alguien'} (${_quien(r.rolOrigen)})',
                    if (sobre != null) 'sobre $sobre',
                    Formato.haceCuanto(r.creadoEn),
                  ].join(' · '),
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (r.detalle != null) ...[
                  const SizedBox(height: MySpacing.xxs),
                  Text('«${r.detalle}»', style: MyType.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: MySpacing.xs),
                MyBadge(r.estado.label, tone: tonoReclamo(r.estado), dot: !r.estado.esCerrado),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.xs),
          Icon(Symbols.chevron_right, color: MyColors.secondary),
        ],
      ),
    );
  }
}

/// La ficha de un reclamo encima de la lista, con todo lo que se puede hacer.
///
/// Lee el reclamo de la lista en vivo y no de una copia: así, después de
/// tomarlo o cerrarlo, la ficha muestra el estado nuevo sin cerrarse.
Future<void> mostrarFichaReclamo(BuildContext context, String reclamoId) => mostrarHojaLateral(
      context,
      titulo: 'Reclamo',
      builder: (_) => _FichaReclamo(reclamoId: reclamoId),
    );

class _FichaReclamo extends ConsumerStatefulWidget {
  const _FichaReclamo({required this.reclamoId});

  final String reclamoId;

  @override
  ConsumerState<_FichaReclamo> createState() => _FichaReclamoState();
}

class _FichaReclamoState extends ConsumerState<_FichaReclamo> {
  var _trabajando = false;

  /// `admin_resolver_reclamo` escribe `resolucion` siempre, así que mover un
  /// reclamo sin texto le borraría al que reclamó la respuesta que ya leyó.
  /// Por eso cuando no hay texto nuevo se reenvía el que estaba.
  Future<void> _mover(Reclamo r, EstadoReclamo estado, {String? resolucion}) async {
    setState(() => _trabajando = true);
    try {
      await ref.read(reclamosRepositoryProvider).resolver(r.id, estado, resolucion: resolucion ?? r.resolucion);
      ref.invalidate(reclamosProvider);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /// Cerrar un reclamo pide siempre un texto: es lo único que el que reclamó
  /// va a leer, y sin eso le queda un "Resuelto" sin explicación.
  Future<void> _cerrar(Reclamo r, EstadoReclamo estado) async {
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
    await _mover(r, estado, resolucion: texto);
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(reclamosProvider).value?.where((x) => x.id == widget.reclamoId).firstOrNull;
    if (r == null) {
      return const MyEmptyState(
        icon: Symbols.search_off,
        title: 'Este reclamo ya no está',
        message: 'Puede que lo hayan borrado.',
      );
    }
    final sobre = r.sobreQue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MyAvatar(nombre: r.abiertoPorNombre ?? '?', size: 48),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.motivo, style: MyType.headlineMd),
                  const SizedBox(height: MySpacing.xxs),
                  MyBadge(r.estado.label, tone: tonoReclamo(r.estado), dot: !r.estado.esCerrado),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: MySpacing.md),
        MyDato('Lo abrió', '${r.abiertoPorNombre ?? 'Alguien'} (${_quien(r.rolOrigen)})', icono: Symbols.person),
        if (sobre != null) MyDato('Sobre', sobre, icono: Symbols.receipt_long),
        MyDato('Cuándo', Formato.fechaHora(r.creadoEn), icono: Symbols.schedule),
        if (r.detalle != null) MyDato('Lo que escribió', r.detalle!, icono: Symbols.chat),
        if (r.resolucion != null) MyDato('Lo que le contestamos', r.resolucion!, icono: Symbols.reply),
        const SizedBox(height: MySpacing.lg),
        if (r.estado.esCerrado)
          MyBoton(
            label: 'Volver a abrir',
            icon: Symbols.undo,
            tipo: MyBotonTipo.secundario,
            onPressed: _trabajando ? null : () => _mover(r, EstadoReclamo.abierto),
          )
        else ...[
          // De lo que más se hace a lo que menos: el principal queda primero,
          // a mano también en el celular.
          MyBoton(
            label: 'Responder y cerrar',
            icon: Symbols.check,
            onPressed: _trabajando ? null : () => _cerrar(r, EstadoReclamo.resuelto),
          ),
          if (r.estado == EstadoReclamo.abierto) ...[
            const SizedBox(height: MySpacing.xs),
            MyBoton(
              label: 'Lo estoy viendo',
              icon: Symbols.visibility,
              tipo: MyBotonTipo.secundario,
              onPressed: _trabajando ? null : () => _mover(r, EstadoReclamo.enRevision),
            ),
          ],
          const SizedBox(height: MySpacing.xs),
          MyBoton(
            label: 'Desestimar',
            icon: Symbols.block,
            tipo: MyBotonTipo.texto,
            onPressed: _trabajando ? null : () => _cerrar(r, EstadoReclamo.desestimado),
          ),
        ],
      ],
    );
  }
}
