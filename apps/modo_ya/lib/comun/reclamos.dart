import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'formulario_emergente.dart';

/// Algo sobre lo que se puede reclamar: un pedido o un envío.
///
/// La pantalla del cliente arma estos de sus pedidos y la del local de sus
/// pedidos y envíos. Los dos usan el mismo formulario.
class SobreQue {
  const SobreQue({required this.titulo, required this.bajada, this.pedidoId, this.envioId});

  final String titulo;
  final String bajada;
  final String? pedidoId;
  final String? envioId;
}

/// Tono de la pastilla del estado de un reclamo.
MyBadgeTone tonoReclamo(EstadoReclamo e) => switch (e) {
      EstadoReclamo.abierto => MyBadgeTone.ember,
      EstadoReclamo.enRevision => MyBadgeTone.info,
      EstadoReclamo.resuelto => MyBadgeTone.success,
      EstadoReclamo.desestimado => MyBadgeTone.neutral,
    };

/// "Mis reclamos": la misma pantalla para el cliente y para el local, que solo
/// se diferencian en los textos, los motivos sugeridos y sobre qué se puede
/// reclamar.
class MisReclamosPage extends ConsumerWidget {
  const MisReclamosPage({
    super.key,
    required this.bajada,
    required this.motivos,
    required this.candidatos,
    required this.volver,
  });

  /// La línea de abajo del título.
  final String bajada;

  /// Motivos sugeridos (ver [MotivosDeReclamo]).
  final List<String> motivos;

  /// Los pedidos y envíos sobre los que puede reclamar, los más nuevos primero.
  final List<SobreQue> candidatos;

  final VoidCallback volver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reclamos = ref.watch(reclamosProvider);

    return MyPagina(
      volver: volver,
      rotulo: 'Ayuda',
      titulo: 'Mis reclamos',
      bajada: bajada,
      anchoMaximo: 900,
      onRefresh: () => ref.refresh(reclamosProvider.future),
      acciones: [
        MyBoton(
          label: 'Abrir un reclamo',
          icon: Symbols.add,
          onPressed: () => abrirReclamo(context, ref, motivos: motivos, candidatos: candidatos),
        ),
      ],
      children: [
        MyAsync(
          valor: reclamos,
          onReintentar: () => ref.invalidate(reclamosProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.support_agent,
                  title: 'No tenés reclamos',
                  message: 'Si algo sale mal, abrí uno y te contestamos acá mismo.',
                  action: MyBoton(
                    label: 'Abrir un reclamo',
                    icon: Symbols.add,
                    onPressed: () => abrirReclamo(context, ref, motivos: motivos, candidatos: candidatos),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in lista) ...[
                  TarjetaDeReclamo(reclamo: r),
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

/// Un reclamo visto por el que lo abrió: qué pidió, en qué anda y la respuesta.
class TarjetaDeReclamo extends StatelessWidget {
  const TarjetaDeReclamo({super.key, required this.reclamo, this.compacta = false});

  final Reclamo reclamo;

  /// Dentro del seguimiento de un pedido no hace falta repetir de qué pedido es.
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final r = reclamo;
    final sobre = r.sobreQue;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(r.motivo, style: MyType.headlineSm)),
              const SizedBox(width: MySpacing.xs),
              MyBadge(r.estado.paraElQueReclama, tone: tonoReclamo(r.estado), dot: !r.estado.esCerrado),
            ],
          ),
          const SizedBox(height: MySpacing.xxs),
          Text(
            [
              if (!compacta && sobre != null) 'Sobre $sobre',
              Formato.haceCuanto(r.creadoEn),
            ].join(' · '),
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          if (r.detalle != null) ...[
            const SizedBox(height: MySpacing.sm),
            Text(r.detalle!, style: MyType.bodyMd),
          ],
          if (r.resolucion != null) ...[
            const SizedBox(height: MySpacing.sm),
            MyCard(
              color: r.estado == EstadoReclamo.desestimado
                  ? MyColors.surfaceContainerHigh
                  : MyColors.primaryFixed,
              shadows: const [],
              padding: const EdgeInsets.all(MySpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.support_agent, size: 20, color: MyColors.onPrimaryFixed),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MODO YA',
                          style: MyType.labelMd.copyWith(color: MyColors.onPrimaryFixedVariant),
                        ),
                        Text(r.resolucion!, style: MyType.bodyMd.copyWith(color: MyColors.onPrimaryFixed)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lo que ve el cliente del reclamo de un pedido, dentro de su seguimiento:
/// el botón para abrirlo, o el estado del que ya abrió.
class ReclamoDelPedido extends ConsumerWidget {
  const ReclamoDelPedido({super.key, required this.pedido});

  final Pedido pedido;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mios = ref.watch(reclamosDelPedidoProvider(pedido.id));

    if (mios.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MyOverline('Tu reclamo'),
          const SizedBox(height: MySpacing.xs),
          for (final r in mios) ...[
            TarjetaDeReclamo(reclamo: r, compacta: true),
            const SizedBox(height: MySpacing.xs),
          ],
        ],
      );
    }

    return MyCard(
      color: MyColors.claroSuperficieAlt,
      shadows: const [],
      padding: const EdgeInsets.all(MySpacing.md),
      child: Row(
        children: [
          Icon(Symbols.support_agent, color: MyColors.claroAcento),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Text(
              '¿Algo salió mal con este pedido?',
              style: MyType.bodyMd.copyWith(color: MyColors.claroTextoSecundario),
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          MyBoton(
            label: 'Reclamar',
            icon: Symbols.flag,
            tipo: MyBotonTipo.secundario,
            onPressed: () => abrirReclamo(
              context,
              ref,
              motivos: MotivosDeReclamo.delCliente,
              candidatos: [
                SobreQue(
                  pedidoId: pedido.id,
                  titulo: 'Pedido ${pedido.codigo}',
                  bajada: pedido.comercioNombre,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Formulario para abrir un reclamo. Si [candidatos] trae uno solo, ya viene
/// elegido; si trae varios, primero hay que decir sobre cuál es.
Future<void> abrirReclamo(
  BuildContext context,
  WidgetRef ref, {
  required List<String> motivos,
  required List<SobreQue> candidatos,
}) =>
    mostrarFormularioEmergente(
      context,
      titulo: 'Abrir un reclamo',
      builder: (_) => _Formulario(motivos: motivos, candidatos: candidatos),
    );

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({required this.motivos, required this.candidatos});

  final List<String> motivos;
  final List<SobreQue> candidatos;

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _otroMotivo = TextEditingController();
  final _detalle = TextEditingController();

  SobreQue? _sobre;
  String? _motivo;
  var _escribiendoOtro = false;

  @override
  void initState() {
    super.initState();
    if (widget.candidatos.length == 1) _sobre = widget.candidatos.first;
    _otroMotivo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _otroMotivo.dispose();
    _detalle.dispose();
    super.dispose();
  }

  String get _motivoFinal => _escribiendoOtro ? _otroMotivo.text.trim() : (_motivo ?? '');

  bool get _completo => _motivoFinal.length >= 3;

  Future<void> _enviar() async {
    if (!_completo) return;
    try {
      await ref.read(reclamosRepositoryProvider).abrir(
            motivo: _motivoFinal,
            detalle: _detalle.text,
            pedidoId: _sobre?.pedidoId,
            envioId: _sobre?.envioId,
          );
      ref.invalidate(reclamosProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      await mostrarExito(
        context,
        titulo: 'Reclamo abierto',
        mensaje: 'Lo vamos a mirar y te contestamos en "Mis reclamos".',
      );
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Con un solo candidato no se elige nada: ya se sabe de qué se reclama.
    final elegir = widget.candidatos.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (elegir) ...[
          const MyOverline('¿Sobre qué es?'),
          const SizedBox(height: MySpacing.xs),
          for (final c in widget.candidatos.take(15))
            Padding(
              padding: const EdgeInsets.only(bottom: MySpacing.xxs),
              child: MyCard(
                padding: const EdgeInsets.all(MySpacing.sm),
                color: c == _sobre ? MyColors.primaryFixed : null,
                shadows: const [],
                onTap: () => setState(() => _sobre = c),
                child: Row(
                  children: [
                    Icon(
                      c == _sobre ? Symbols.radio_button_checked : Symbols.radio_button_unchecked,
                      size: 20,
                      color: c == _sobre ? MyColors.onPrimaryFixed : MyColors.outline,
                    ),
                    const SizedBox(width: MySpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.titulo, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            c.bajada,
                            style: MyType.bodySm.copyWith(color: MyColors.secondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: MySpacing.md),
            child: MyBoton(
              label: 'No es sobre un pedido en particular',
              icon: _sobre == null ? Symbols.radio_button_checked : Symbols.radio_button_unchecked,
              tipo: _sobre == null ? MyBotonTipo.secundario : MyBotonTipo.texto,
              onPressed: () => setState(() => _sobre = null),
            ),
          ),
        ] else if (_sobre != null) ...[
          MyCard(
            color: MyColors.surfaceContainerHigh,
            shadows: const [],
            padding: const EdgeInsets.all(MySpacing.sm),
            child: Row(
              children: [
                Icon(Symbols.receipt_long, size: 20, color: MyColors.secondary),
                const SizedBox(width: MySpacing.sm),
                Expanded(child: Text('${_sobre!.titulo} · ${_sobre!.bajada}', style: MyType.labelMd)),
              ],
            ),
          ),
          const SizedBox(height: MySpacing.md),
        ],
        const MyOverline('¿Qué pasó?'),
        const SizedBox(height: MySpacing.xs),
        Wrap(
          spacing: MySpacing.xs,
          runSpacing: MySpacing.xs,
          children: [
            for (final m in widget.motivos)
              MyChip(
                m,
                selected: !_escribiendoOtro && _motivo == m,
                onTap: () => setState(() {
                  _escribiendoOtro = false;
                  _motivo = m;
                }),
              ),
            MyChip(
              'Otra cosa',
              selected: _escribiendoOtro,
              onTap: () => setState(() => _escribiendoOtro = true),
            ),
          ],
        ),
        const SizedBox(height: MySpacing.md),
        if (_escribiendoOtro)
          MyCampo(controller: _otroMotivo, label: 'Contanos en una línea', icon: Symbols.flag),
        MyCampo(
          controller: _detalle,
          label: 'Detalle (opcional)',
          hint: 'Todo lo que nos ayude a entender qué pasó',
          icon: Symbols.short_text,
          obligatorio: false,
          lineas: 3,
        ),
        MyBotonAccion(
          label: 'Enviar el reclamo',
          icon: Symbols.send,
          onPressed: _completo ? _enviar : null,
        ),
      ],
    );
  }
}
