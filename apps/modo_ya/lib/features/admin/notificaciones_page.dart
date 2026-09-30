import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Notificaciones: la administración le escribe a la gente.
///
/// Se elige a quién le llega (todos, los que tienen Plus, los que hace rato no
/// piden…) y la app lo muestra en la campanita de cada uno. Antes de mandarla
/// se ve a cuántas personas le va a llegar, porque una vez enviada no se
/// deshace.
class AdminNotificacionesPage extends ConsumerWidget {
  const AdminNotificacionesPage({super.key});

  Future<void> _redactar(BuildContext context, WidgetRef ref, {Notificacion? borrador}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _Redactar(borrador: borrador),
    );
    ref.invalidate(notificacionesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notis = ref.watch(notificacionesProvider);

    return MyPagina(
      rotulo: 'Comunicación',
      titulo: 'Notificaciones',
      bajada: 'Mensajes que le llegan a la gente dentro de la app, en su campanita.',
      anchoMaximo: 900,
      acciones: [
        MyBoton(
          label: 'Escribir',
          icon: Symbols.edit_square,
          onPressed: () => _redactar(context, ref),
        ),
      ],
      onRefresh: () async => ref.invalidate(notificacionesProvider),
      children: [
        MyAsync(
          valor: notis,
          onReintentar: () => ref.invalidate(notificacionesProvider),
          datos: (lista) {
            final automaticas = lista.where((n) => n.esAutomatica).toList();
            final borradores = lista.where((n) => !n.esAutomatica && !n.enviada).toList();
            final enviadas = lista.where((n) => !n.esAutomatica && n.enviada).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MySectionHeader(
                  title: 'Solas',
                  subtitle: 'Salen sin que nadie las mande, cuando se cumple la condición',
                ),
                const SizedBox(height: MySpacing.sm),
                for (final d in DisparadorNotificacion.values) ...[
                  _Automatica(
                    disparador: d,
                    notificacion: automaticas.where((n) => n.disparador == d).firstOrNull,
                  ),
                  const SizedBox(height: MySpacing.xs),
                ],
                const SizedBox(height: MySpacing.lg),
                if (borradores.isNotEmpty) ...[
                  const MySectionHeader(
                    title: 'Sin mandar',
                    subtitle: 'Todavía no las recibió nadie',
                  ),
                  const SizedBox(height: MySpacing.sm),
                  for (final n in borradores) ...[
                    _Fila(notificacion: n, onEditar: () => _redactar(context, ref, borrador: n)),
                    const SizedBox(height: MySpacing.xs),
                  ],
                  const SizedBox(height: MySpacing.lg),
                ],
                if (enviadas.isNotEmpty) ...[
                  const MySectionHeader(
                    title: 'Enviadas',
                    subtitle: 'Cuánta gente la recibió y cuántos la abrieron',
                  ),
                  const SizedBox(height: MySpacing.sm),
                  for (final n in enviadas) ...[
                    _Fila(notificacion: n),
                    const SizedBox(height: MySpacing.xs),
                  ],
                ],
                if (borradores.isEmpty && enviadas.isEmpty)
                  MyCard(
                    child: MyEmptyState(
                      icon: Symbols.notifications,
                      title: 'Todavía no mandaste ninguna a mano',
                      message: 'Sirve para avisar de un cambio de horario o de una '
                          'promoción que arranca. Para lo repetido están las de arriba.',
                      action: MyBoton(
                        label: 'Escribir la primera',
                        icon: Symbols.edit_square,
                        onPressed: () => _redactar(context, ref),
                      ),
                    ),
                  ),
                const SizedBox(height: MySpacing.md),
                Text(
                  'Por ahora la notificación se ve cuando la persona abre la app. '
                  'El aviso en la pantalla del celular con la app cerrada necesita '
                  'conectar Firebase, y queda para cuando esté.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Una notificación que sale sola. Siempre se muestran las dos, estén
/// escritas o no: la pantalla tiene que contar qué puede hacer la app, no solo
/// qué se hizo hasta ahora.
class _Automatica extends ConsumerWidget {
  const _Automatica({required this.disparador, this.notificacion});

  final DisparadorNotificacion disparador;
  final Notificacion? notificacion;

  Future<void> _editar(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditarAutomatica(disparador: disparador, notificacion: notificacion),
    );
    ref.invalidate(notificacionesProvider);
  }

  Future<void> _prender(BuildContext context, WidgetRef ref, bool v) async {
    final n = notificacion;
    if (n == null) return;
    try {
      await ref.read(notificacionesRepositoryProvider).prender(n.id, activa: v);
      ref.invalidate(notificacionesProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notificacion;
    final escrita = n != null;
    final prendida = escrita && n.activa;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                disparador == DisparadorNotificacion.carritoAbandonado
                    ? Symbols.shopping_cart_off
                    : Symbols.bedtime,
                color: prendida ? MyColors.onSurface : MyColors.outline,
                fill: prendida ? 1 : 0,
              ),
              const SizedBox(width: MySpacing.sm),
              Expanded(child: Text(disparador.rotulo, style: MyType.labelLg)),
              if (!escrita)
                MyBadge('Sin escribir', tone: MyBadgeTone.neutral)
              else
                Switch(value: prendida, onChanged: (v) => _prender(context, ref, v)),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Text(
            disparador.detalle,
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          if (escrita) ...[
            const SizedBox(height: MySpacing.sm),
            Text('«${n.titulo}»', style: MyType.labelMd, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: MySpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  !escrita
                      ? 'Todavía no sale'
                      : disparador == DisparadorNotificacion.carritoAbandonado
                          ? 'A los ${n.recordatorios.join(", ")} min · salió ${n.alcance} veces, abrieron ${n.leidas}'
                          : 'Sin pedir hace ${n.diasInactividad} días · salió ${n.alcance} veces, abrieron ${n.leidas}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              MyBoton(
                label: escrita ? 'Editar' : 'Escribirla',
                icon: escrita ? Symbols.edit : Symbols.add,
                tipo: escrita ? MyBotonTipo.texto : MyBotonTipo.secundario,
                onPressed: () => _editar(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({required this.notificacion, this.onEditar});

  final Notificacion notificacion;
  final VoidCallback? onEditar;

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    final ok = await confirmar(
      context,
      titulo: 'Borrar notificación',
      mensaje: notificacion.enviada
          ? 'Desaparece de la campanita de todos los que la recibieron.'
          : 'Es un borrador que todavía no recibió nadie.',
      aceptar: 'Borrar',
      peligroso: true,
    );
    if (!ok) return;
    try {
      await ref.read(notificacionesRepositoryProvider).borrar(notificacion.id);
      ref.invalidate(notificacionesProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notificacion;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(n.titulo, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: MySpacing.sm),
              if (n.enviada)
                MyBadge('Enviada', tone: MyBadgeTone.success, dot: true)
              else
                MyBadge('Borrador', tone: MyBadgeTone.neutral, dot: true),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Text(
            n.cuerpo,
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: MySpacing.sm),
          Row(
            children: [
              Icon(Symbols.group, size: 16, color: MyColors.outline),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  n.enviada
                      ? '${n.segmento.rotulo} · llegó a ${n.alcance}, la abrieron ${n.leidas}'
                      : '${n.segmento.rotulo}${n.segmento.usaDias ? ' (${n.diasInactividad} días)' : ''}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onEditar != null)
                MyBoton(label: 'Abrir', icon: Symbols.edit, tipo: MyBotonTipo.texto, onPressed: onEditar),
              MyBoton(
                label: 'Borrar',
                icon: Symbols.delete,
                tipo: MyBotonTipo.texto,
                onPressed: () => _borrar(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Redactar y mandar. El alcance se consulta a la base cada vez que cambia el
/// segmento: el número que se ve es el mismo que se va a usar al mandar.
class _Redactar extends ConsumerStatefulWidget {
  const _Redactar({this.borrador});

  final Notificacion? borrador;

  @override
  ConsumerState<_Redactar> createState() => _RedactarState();
}

class _RedactarState extends ConsumerState<_Redactar> {
  late final _titulo = TextEditingController(text: widget.borrador?.titulo ?? '');
  late final _cuerpo = TextEditingController(text: widget.borrador?.cuerpo ?? '');
  late var _segmento = widget.borrador?.segmento ?? SegmentoNotificacion.clientes;
  late var _dias = widget.borrador?.diasInactividad ?? 30;
  late var _destino = widget.borrador?.destino ?? DestinoNotificacion.ninguno;

  int? _alcance;
  var _calculando = false;

  NotificacionesRepository get _repo => ref.read(notificacionesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _titulo.addListener(_refrescar);
    _cuerpo.addListener(_refrescar);
    _calcularAlcance();
  }

  @override
  void dispose() {
    _titulo.dispose();
    _cuerpo.dispose();
    super.dispose();
  }

  void _refrescar() => setState(() {});

  Future<void> _calcularAlcance() async {
    setState(() => _calculando = true);
    try {
      final n = await _repo.alcanceDe(_segmento, dias: _dias);
      if (mounted) setState(() => _alcance = n);
    } catch (_) {
      // Que no se pueda contar no tiene que trabar la pantalla: se manda igual
      // y la base vuelve a resolver el segmento en ese momento.
      if (mounted) setState(() => _alcance = null);
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  bool get _completa => _titulo.text.trim().isNotEmpty && _cuerpo.text.trim().isNotEmpty;

  Future<void> _guardar({required bool mandar}) async {
    if (!_completa) return;
    try {
      final id = await _repo.guardar(
        id: widget.borrador?.id,
        titulo: _titulo.text,
        cuerpo: _cuerpo.text,
        segmento: _segmento,
        diasInactividad: _dias,
        destino: _destino,
      );

      if (!mandar) {
        if (mounted) {
          Navigator.of(context).pop();
          mostrarInfo(context, 'Guardada como borrador');
        }
        return;
      }

      final cuantos = await _repo.enviar(id);
      if (mounted) {
        Navigator.of(context).pop();
        mostrarAviso(context, cuantos == 1 ? 'Le llegó a 1 persona' : 'Le llegó a $cuantos personas');
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _confirmarEnvio() async {
    final cuantos = _alcance;
    final ok = await confirmar(
      context,
      titulo: 'Mandar la notificación',
      mensaje: cuantos == null
          ? 'Le va a llegar a todos los de "${_segmento.rotulo}". Una vez enviada no se puede deshacer.'
          : 'Le va a llegar a $cuantos ${cuantos == 1 ? 'persona' : 'personas'} '
              '(${_segmento.rotulo}). Una vez enviada no se puede deshacer.',
      aceptar: 'Mandar',
    );
    if (ok) await _guardar(mandar: true);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: MyColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(MyRadius.hero)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(MySpacing.lg),
          children: [
            Text('Nueva notificación', style: MyType.headlineSm),
            const SizedBox(height: MySpacing.md),

            _VistaPrevia(titulo: _titulo.text, cuerpo: _cuerpo.text),
            const SizedBox(height: MySpacing.lg),

            MyCampo(
              controller: _titulo,
              label: 'Título',
              hint: 'Hoy tenés envío gratis',
              icon: Symbols.title,
            ),
            MyCampo(
              controller: _cuerpo,
              label: 'Mensaje',
              hint: 'Pedí en cualquier local adherido y no pagás el envío.',
              icon: Symbols.short_text,
              lineas: 3,
            ),
            Text(
              'Escribí {nombre} donde quieras que aparezca el nombre de cada uno.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.md),

            const MyOverline('A quién le llega'),
            const SizedBox(height: MySpacing.xs),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (final s in SegmentoNotificacion.values)
                  MyChip(
                    s.rotulo,
                    selected: _segmento == s,
                    onTap: () {
                      setState(() => _segmento = s);
                      _calcularAlcance();
                    },
                  ),
              ],
            ),
            const SizedBox(height: MySpacing.xs),
            Text(_segmento.detalle, style: MyType.bodySm.copyWith(color: MyColors.secondary)),

            if (_segmento.usaDias) ...[
              const SizedBox(height: MySpacing.md),
              const MyOverline('Sin pedir desde hace'),
              const SizedBox(height: MySpacing.xs),
              Wrap(
                spacing: MySpacing.xs,
                runSpacing: MySpacing.xs,
                children: [
                  for (final d in const [7, 15, 30, 60, 90])
                    MyChip(
                      d == 7 ? '1 semana' : d == 30 ? '1 mes' : '$d días',
                      selected: _dias == d,
                      onTap: () {
                        setState(() => _dias = d);
                        _calcularAlcance();
                      },
                    ),
                ],
              ),
            ],

            const SizedBox(height: MySpacing.md),
            const MyOverline('Qué abre al tocarla'),
            const SizedBox(height: MySpacing.xs),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (final d in DestinoNotificacion.values)
                  // "Un local" necesita elegir cuál: queda para cuando haga falta.
                  if (d != DestinoNotificacion.local)
                    MyChip(
                      d.rotulo,
                      selected: _destino == d,
                      onTap: () => setState(() => _destino = d),
                    ),
              ],
            ),

            const SizedBox(height: MySpacing.lg),
            MyCard(
              padding: const EdgeInsets.all(MySpacing.sm),
              child: Row(
                children: [
                  Icon(Symbols.group, color: MyColors.tertiary),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Text(
                      _calculando
                          ? 'Contando a cuántos les llega…'
                          : _alcance == null
                              ? 'No se pudo contar el alcance'
                              : _alcance == 1
                                  ? 'Le llega a 1 persona'
                                  : 'Le llega a $_alcance personas',
                      style: MyType.labelLg,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: MySpacing.lg),
            MyBotonAccion(
              label: 'Mandar ahora',
              icon: Symbols.send,
              onPressed: _completa && _alcance != 0 ? _confirmarEnvio : null,
            ),
            const SizedBox(height: MySpacing.sm),
            MyBoton(
              label: 'Guardar sin mandar',
              icon: Symbols.save,
              tipo: MyBotonTipo.secundario,
              onPressed: _completa ? () => _guardar(mandar: false) : null,
            ),
            const SizedBox(height: MySpacing.md),
          ],
        ),
      ),
    );
  }
}

/// Escribir la notificación que sale sola: el texto y cuándo sale.
class _EditarAutomatica extends ConsumerStatefulWidget {
  const _EditarAutomatica({required this.disparador, this.notificacion});

  final DisparadorNotificacion disparador;
  final Notificacion? notificacion;

  @override
  ConsumerState<_EditarAutomatica> createState() => _EditarAutomaticaState();
}

class _EditarAutomaticaState extends ConsumerState<_EditarAutomatica> {
  late final _titulo = TextEditingController(
    text: widget.notificacion?.titulo ??
        (widget.disparador == DisparadorNotificacion.carritoAbandonado
            ? '{nombre}, te quedó un pedido sin pagar'
            : '{nombre}, te extrañamos'),
  );
  late final _cuerpo = TextEditingController(
    text: widget.notificacion?.cuerpo ??
        (widget.disparador == DisparadorNotificacion.carritoAbandonado
            ? 'Terminá de pagarlo antes de que se cancele.'
            : 'Hace rato no pedís. Mirá lo que hay hoy en MODO YA.'),
  );
  late final _minutos = {...?widget.notificacion?.recordatorios} .isEmpty
      ? <int>{10}
      : {...?widget.notificacion?.recordatorios};
  late var _dias = widget.notificacion?.diasInactividad ?? 30;
  late var _repetir = widget.notificacion?.repetirCadaDias ?? 30;

  bool get _esCarrito => widget.disparador == DisparadorNotificacion.carritoAbandonado;
  bool get _completa => _titulo.text.trim().isNotEmpty && _cuerpo.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titulo.addListener(() => setState(() {}));
    _cuerpo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titulo.dispose();
    _cuerpo.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    try {
      await ref.read(notificacionesRepositoryProvider).guardarAutomatica(
            id: widget.notificacion?.id,
            disparador: widget.disparador,
            titulo: _titulo.text,
            cuerpo: _cuerpo.text,
            activa: widget.notificacion?.activa ?? true,
            recordatorios: _minutos.toList()..sort(),
            diasInactividad: _dias,
            repetirCadaDias: _repetir,
          );
      if (mounted) {
        Navigator.of(context).pop();
        mostrarAviso(context, 'Lista: sale sola de acá en más');
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: MyColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(MyRadius.hero)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(MySpacing.lg),
          children: [
            Text(widget.disparador.rotulo, style: MyType.headlineSm),
            const SizedBox(height: MySpacing.xs),
            Text(
              widget.disparador.detalle,
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.md),

            _VistaPrevia(titulo: _titulo.text, cuerpo: _cuerpo.text),
            const SizedBox(height: MySpacing.lg),

            MyCampo(controller: _titulo, label: 'Título', icon: Symbols.title),
            MyCampo(controller: _cuerpo, label: 'Mensaje', icon: Symbols.short_text, lineas: 3),
            Text(
              'Escribí {nombre} donde quieras que aparezca el nombre de cada uno.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.md),

            if (_esCarrito) ...[
              const MyOverline('Cuándo se le recuerda'),
              const SizedBox(height: MySpacing.xs),
              Wrap(
                spacing: MySpacing.xs,
                runSpacing: MySpacing.xs,
                children: [
                  for (final m in const [5, 10, 15, 20, 25])
                    MyChip(
                      '$m min',
                      selected: _minutos.contains(m),
                      // Siempre tiene que quedar al menos uno: una automatica
                      // sin ningun momento no avisaria nunca.
                      onTap: () => setState(() {
                        if (!_minutos.remove(m)) _minutos.add(m);
                        if (_minutos.isEmpty) _minutos.add(m);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: MySpacing.xs),
              Text(
                _minutos.length == 1
                    ? 'Un solo aviso. Podés marcar varios para insistir.'
                    : 'Le van a llegar ${_minutos.length} avisos, uno por cada momento marcado.',
                style: MyType.labelMd,
              ),
              const SizedBox(height: 2),
              Text(
                'El pedido sin pagar se cancela solo a los 30 minutos, así que '
                'todos los recordatorios entran antes: después avisarían por algo '
                'que ya no existe.',
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
            ] else ...[
              const MyOverline('Se considera dormido a los'),
              const SizedBox(height: MySpacing.xs),
              Wrap(
                spacing: MySpacing.xs,
                runSpacing: MySpacing.xs,
                children: [
                  for (final d in const [15, 30, 60, 90])
                    MyChip('$d días', selected: _dias == d, onTap: () => setState(() => _dias = d)),
                ],
              ),
              const SizedBox(height: MySpacing.md),
              const MyOverline('No volver a escribirle antes de'),
              const SizedBox(height: MySpacing.xs),
              Wrap(
                spacing: MySpacing.xs,
                runSpacing: MySpacing.xs,
                children: [
                  for (final d in const [15, 30, 60, 90])
                    MyChip('$d días', selected: _repetir == d, onTap: () => setState(() => _repetir = d)),
                ],
              ),
            ],

            const SizedBox(height: MySpacing.lg),
            MyBotonAccion(
              label: 'Guardar',
              icon: Symbols.save,
              onPressed: _completa ? _guardar : null,
            ),
            const SizedBox(height: MySpacing.md),
          ],
        ),
      ),
    );
  }
}

/// Cómo se va a ver en la campanita, mientras se escribe.
class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({required this.titulo, required this.cuerpo});

  final String titulo;
  final String cuerpo;

  @override
  Widget build(BuildContext context) {
    final vacia = titulo.trim().isEmpty && cuerpo.trim().isEmpty;
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MyColors.primary,
              borderRadius: BorderRadius.circular(MyRadius.card),
            ),
            child: Icon(Symbols.notifications, fill: 1, color: MyColors.onPrimary),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vacia ? 'Así se va a ver' : (titulo.trim().isEmpty ? 'Sin título' : titulo),
                  style: MyType.labelLg.copyWith(color: vacia ? MyColors.outline : MyColors.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (cuerpo.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    cuerpo,
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
