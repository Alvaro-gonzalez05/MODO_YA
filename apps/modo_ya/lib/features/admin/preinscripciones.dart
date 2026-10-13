import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cómo se muestra cada pregunta del formulario de la landing. Las que no
/// están acá se muestran con la clave tal cual; las de `null` no se muestran.
const _rotulos = <String, String?>{
  'rubro': 'Rubro',
  'responsable': 'Responsable',
  'direccion': 'Dirección',
  'horario': 'Horario',
  'uso': 'Quiere',
  'delivery': 'Delivery propio',
  'instagram': 'Instagram',
  'vehiculo': 'Vehículo',
  'zona': 'Zona',
  'documentacion': 'Documentación',
  'disponibilidad': 'Disponibilidad',
  'comentarios': 'Comentarios',
  'acepta_contacto': null,
  'mayor_y_contacto': null,
};

/// Los locales o riders que se pre-inscribieron en la landing y esperan que
/// la administración los contacte. Si no hay ninguna no ocupa lugar.
class PreinscripcionesWeb extends ConsumerStatefulWidget {
  const PreinscripcionesWeb({super.key, required this.tipo});

  final TipoPreinscripcion tipo;

  @override
  ConsumerState<PreinscripcionesWeb> createState() => _PreinscripcionesWebState();
}

class _PreinscripcionesWebState extends ConsumerState<PreinscripcionesWeb> {
  var _verAtendidas = false;

  @override
  Widget build(BuildContext context) {
    final todas = (ref.watch(preinscripcionesProvider).value ?? const <Preinscripcion>[])
        .where((p) => p.tipo == widget.tipo)
        .toList();
    if (todas.isEmpty) return const SizedBox.shrink();

    final pendientes = todas.where((p) => p.estado == EstadoPreinscripcion.pendiente).toList();
    final atendidas = todas.where((p) => p.estado != EstadoPreinscripcion.pendiente).toList();
    final esLocal = widget.tipo == TipoPreinscripcion.local;
    final titulo = switch (pendientes.length) {
      0 => esLocal ? 'Pre-inscripciones de locales' : 'Pre-inscripciones de riders',
      1 => esLocal ? '1 local se pre-inscribió' : '1 rider se pre-inscribió',
      final n => esLocal ? '$n locales se pre-inscribieron' : '$n riders se pre-inscribieron',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MySectionHeader(
          title: titulo,
          subtitle: pendientes.isEmpty
              ? 'Desde la página web. Ya contactaste a todos.'
              : 'Desde la página web: esperan que los contactes por WhatsApp',
        ),
        const SizedBox(height: MySpacing.sm),
        for (final p in pendientes) ...[
          _Tarjeta(p: p),
          const SizedBox(height: MySpacing.sm),
        ],
        if (atendidas.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: MyBoton(
              label: _verAtendidas
                  ? 'Ocultar las ya atendidas'
                  : (atendidas.length == 1 ? 'Ver 1 ya atendida' : 'Ver ${atendidas.length} ya atendidas'),
              icon: _verAtendidas ? Symbols.expand_less : Symbols.expand_more,
              tipo: MyBotonTipo.texto,
              onPressed: () => setState(() => _verAtendidas = !_verAtendidas),
            ),
          ),
          if (_verAtendidas)
            for (final p in atendidas) ...[
              const SizedBox(height: MySpacing.sm),
              _Tarjeta(p: p),
            ],
        ],
        const SizedBox(height: MySpacing.md),
      ],
    );
  }
}

class _Tarjeta extends ConsumerStatefulWidget {
  const _Tarjeta({required this.p});

  final Preinscripcion p;

  @override
  ConsumerState<_Tarjeta> createState() => _TarjetaState();
}

class _TarjetaState extends ConsumerState<_Tarjeta> {
  var _trabajando = false;

  Preinscripcion get p => widget.p;

  Future<void> _marcar(EstadoPreinscripcion estado) async {
    setState(() => _trabajando = true);
    try {
      await ref.read(preinscripcionesRepositoryProvider).marcar(p.id, estado);
      ref.invalidate(preinscripcionesProvider);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  void _whatsapp() {
    final numero = p.whatsapp.replaceAll(RegExp(r'\D'), '');
    final destino = numero.startsWith('54') ? numero : '549$numero';
    final saludo = p.tipo == TipoPreinscripcion.local
        ? '¡Hola! Te escribimos de MODO YA por la pre-inscripción de ${p.nombre}.'
        : '¡Hola ${p.nombre.split(' ').first}! Te escribimos de MODO YA por tu pre-inscripción como rider.';
    launchUrl(
      Uri.parse('https://wa.me/$destino?text=${Uri.encodeComponent(saludo)}'),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final detalle = [
      for (final MapEntry(:key, :value) in p.datos.entries)
        if (!_rotulos.containsKey(key) || _rotulos[key] != null) (_rotulos[key] ?? key, value),
    ];
    final pendiente = p.estado == EstadoPreinscripcion.pendiente;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MyAvatar(nombre: p.nombre, size: 40),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre, style: MyType.headlineSm),
                    Text(
                      [p.whatsapp, ?p.email, Formato.haceCuanto(p.creadoEn)].join(' · '),
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
              if (!pendiente)
                MyBadge(
                  p.estado.label,
                  tone: p.estado == EstadoPreinscripcion.contactada ? MyBadgeTone.success : MyBadgeTone.neutral,
                ),
            ],
          ),
          if (detalle.isNotEmpty) ...[
            const SizedBox(height: MySpacing.sm),
            for (final (rotulo, valor) in detalle)
              Padding(
                padding: const EdgeInsets.only(bottom: MySpacing.xxs),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '$rotulo: ', style: MyType.labelMd.copyWith(color: MyColors.secondary)),
                    TextSpan(text: valor, style: MyType.bodySm),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: MySpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              if (pendiente) ...[
                MyBoton(
                  label: 'Descartar',
                  icon: Symbols.block,
                  tipo: MyBotonTipo.texto,
                  onPressed: _trabajando ? null : () => _marcar(EstadoPreinscripcion.descartada),
                ),
                MyBoton(
                  label: 'WhatsApp',
                  icon: Symbols.chat,
                  tipo: MyBotonTipo.secundario,
                  onPressed: _whatsapp,
                ),
                MyBoton(
                  label: 'Ya lo contacté',
                  icon: Symbols.check,
                  onPressed: _trabajando ? null : () => _marcar(EstadoPreinscripcion.contactada),
                ),
              ] else ...[
                MyBoton(
                  label: 'WhatsApp',
                  icon: Symbols.chat,
                  tipo: MyBotonTipo.texto,
                  onPressed: _whatsapp,
                ),
                MyBoton(
                  label: 'Volver a pendiente',
                  icon: Symbols.undo,
                  tipo: MyBotonTipo.texto,
                  onPressed: _trabajando ? null : () => _marcar(EstadoPreinscripcion.pendiente),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
