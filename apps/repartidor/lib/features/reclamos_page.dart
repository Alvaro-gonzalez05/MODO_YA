import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Los reclamos del rider: los abre sobre un servicio que hizo (o sobre nada
/// en particular, si es de la liquidación) y acá lee la respuesta.
class ReclamosPage extends ConsumerWidget {
  const ReclamosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reclamos = ref.watch(reclamosProvider);

    return MyPagina(
      volver: () => context.canPop() ? context.pop() : context.go('/perfil'),
      rotulo: 'Ayuda',
      titulo: 'Mis reclamos',
      bajada: 'Contanos si algo salió mal y te contestamos acá',
      onRefresh: () => ref.refresh(reclamosProvider.future),
      acciones: [
        MyBoton(
          label: 'Abrir un reclamo',
          icon: Symbols.add,
          onPressed: () => _abrir(context, ref),
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
                  message: 'Si un local no tenía el pedido, el cliente no apareció o algo '
                      'de la liquidación no cierra, contanos.',
                  action: MyBoton(
                    label: 'Abrir un reclamo',
                    icon: Symbols.add,
                    onPressed: () => _abrir(context, ref),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in lista) ...[
                  _Tarjeta(reclamo: r),
                  const SizedBox(height: MySpacing.sm),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => const _Formulario(),
      );
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.reclamo});

  final Reclamo reclamo;

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
              MyBadge(
                r.estado.paraElQueReclama,
                tone: switch (r.estado) {
                  EstadoReclamo.abierto => MyBadgeTone.ember,
                  EstadoReclamo.enRevision => MyBadgeTone.info,
                  EstadoReclamo.resuelto => MyBadgeTone.success,
                  EstadoReclamo.desestimado => MyBadgeTone.neutral,
                },
                dot: !r.estado.esCerrado,
              ),
            ],
          ),
          const SizedBox(height: MySpacing.xxs),
          Text(
            [if (sobre != null) 'Sobre $sobre', Formato.haceCuanto(r.creadoEn)].join(' · '),
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          if (r.detalle != null) ...[
            const SizedBox(height: MySpacing.sm),
            Text(r.detalle!, style: MyType.bodyMd),
          ],
          if (r.resolucion != null) ...[
            const SizedBox(height: MySpacing.sm),
            MyCard(
              color: MyColors.primaryFixed,
              shadows: const [],
              padding: const EdgeInsets.all(MySpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.support_agent, size: 20, color: MyColors.onPrimaryFixed),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Text(
                      r.resolucion!,
                      style: MyType.bodyMd.copyWith(color: MyColors.onPrimaryFixed),
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

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario();

  @override
  ConsumerState<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends ConsumerState<_Formulario> {
  final _otroMotivo = TextEditingController();
  final _detalle = TextEditingController();

  String? _envioId;
  String? _motivo;
  var _escribiendoOtro = false;

  @override
  void initState() {
    super.initState();
    _otroMotivo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _otroMotivo.dispose();
    _detalle.dispose();
    super.dispose();
  }

  String get _motivoFinal => _escribiendoOtro ? _otroMotivo.text.trim() : (_motivo ?? '');

  Future<void> _enviar() async {
    try {
      await ref.read(reclamosRepositoryProvider).abrir(
            motivo: _motivoFinal,
            detalle: _detalle.text,
            envioId: _envioId,
          );
      ref.invalidate(reclamosProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      await mostrarExito(
        context,
        titulo: 'Reclamo abierto',
        mensaje: 'Lo mira la administración y te contesta en "Mis reclamos".',
      );
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Los últimos servicios, para que no tenga que acordarse del código.
    final envios = (ref.watch(enviosDelRepartidorProvider).value ?? const <Envio>[]).take(10).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MySpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Abrir un reclamo', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.md),
            const MyOverline('¿De qué servicio?'),
            const SizedBox(height: MySpacing.xs),
            for (final e in envios)
              Padding(
                padding: const EdgeInsets.only(bottom: MySpacing.xxs),
                child: MyCard(
                  padding: const EdgeInsets.all(MySpacing.sm),
                  color: e.id == _envioId ? MyColors.primaryFixed : null,
                  shadows: const [],
                  onTap: () => setState(() => _envioId = e.id),
                  child: Row(
                    children: [
                      Icon(
                        e.id == _envioId ? Symbols.radio_button_checked : Symbols.radio_button_unchecked,
                        size: 20,
                        color: e.id == _envioId ? MyColors.onPrimaryFixed : MyColors.outline,
                      ),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e.codigo} · ${e.nombreRetiro}',
                                style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              '${e.estado.label} · ${Formato.fechaCorta(e.creadoEn)}',
                              style: MyType.bodySm.copyWith(color: MyColors.secondary),
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
                label: 'No es de un servicio (liquidación, cuenta…)',
                icon: _envioId == null ? Symbols.radio_button_checked : Symbols.radio_button_unchecked,
                tipo: _envioId == null ? MyBotonTipo.secundario : MyBotonTipo.texto,
                onPressed: () => setState(() => _envioId = null),
              ),
            ),
            const MyOverline('¿Qué pasó?'),
            const SizedBox(height: MySpacing.xs),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (final m in MotivosDeReclamo.delRider)
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
              icon: Symbols.short_text,
              obligatorio: false,
              lineas: 3,
            ),
            MyBotonAccion(
              label: 'Enviar el reclamo',
              icon: Symbols.send,
              onPressed: _motivoFinal.length >= 3 ? _enviar : null,
            ),
          ],
        ),
      ),
    );
  }
}
