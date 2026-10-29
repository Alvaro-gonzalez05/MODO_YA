import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'encoger.dart';

/// La carpeta de un rider dentro de su ficha: qué se le pide por su vehículo,
/// qué subió, y aprobarlo o rechazarlo.
///
/// Es el lugar donde se usa `EstadoAprobacion.rechazado`, que hasta ahora no
/// se podía fijar desde ninguna pantalla (hallazgo 15): rechazar un documento
/// es justo la acción que necesita decir por qué.
class DocumentacionDelRider extends ConsumerWidget {
  const DocumentacionDelRider({super.key, required this.rider});

  final Repartidor rider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carpeta = ref.watch(carpetaDeRiderProvider((repartidorId: rider.id, vehiculo: rider.vehiculo)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyAsync(
          valor: carpeta,
          onReintentar: () {
            ref.invalidate(documentosExigidosProvider);
            ref.invalidate(documentacionProvider);
          },
          datos: (c) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: MyOverline('Documentación')),
                  const SizedBox(width: MySpacing.xs),
                  // El titular puede ser una frase entera: en la ficha angosta
                  // del celular se achica en vez de desbordar.
                  Flexible(
                    flex: 3,
                    child: Encoger(
                      child: MyBadge(
                        c.completa ? 'Completa' : c.titular,
                        tone: c.completa
                            ? MyBadgeTone.success
                            : c.esperaRevision
                                ? MyBadgeTone.ember
                                : MyBadgeTone.danger,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MySpacing.xs),
              if (c.renglones.isEmpty)
                Text(
                  'Para ${rider.vehiculo.label.toLowerCase()} no se le pide documentación. '
                  'Se configura en documentos_exigidos.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                )
              else
                for (final r in c.renglones)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MySpacing.xs),
                    child: _Documento(renglon: r, rider: rider),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Documento extends ConsumerStatefulWidget {
  const _Documento({required this.renglon, required this.rider});

  final RenglonDeCarpeta renglon;
  final Repartidor rider;

  @override
  ConsumerState<_Documento> createState() => _DocumentoState();
}

class _DocumentoState extends ConsumerState<_Documento> {
  var _trabajando = false;

  RenglonDeCarpeta get r => widget.renglon;

  Future<void> _ver() async {
    final archivo = r.documento?.archivo;
    if (archivo == null) return;
    setState(() => _trabajando = true);
    try {
      // `documentos` es privado: se abre con un link firmado que vence.
      final url = await ref.read(documentacionRepositoryProvider).link(archivo);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw const ErrorModoYa('No pudimos abrir el archivo.');
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _validar(EstadoAprobacion estado) async {
    final doc = r.documento;
    if (doc == null) return;

    String? observacion;
    if (estado == EstadoAprobacion.rechazado) {
      // Sin esto el rider ve "Rechazado" y no sabe qué volver a sacar.
      observacion = await pedirTexto(
        context,
        titulo: 'Rechazar ${r.tipo}',
        label: 'Qué le decís al rider (lo lee en su app)',
        aceptar: 'Rechazar',
        inicial: doc.observacion,
      );
      if (observacion == null) return;
    }

    setState(() => _trabajando = true);
    try {
      await ref.read(documentacionRepositoryProvider).validar(doc.id, estado, observacion: observacion);
      ref.invalidate(documentacionProvider);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = r.documento;

    final (icono, color, estado) = switch (r) {
      _ when r.vencido => (Symbols.event_busy, MyColors.error, 'Venció el ${Formato.fechaCorta(d!.venceEn!)}'),
      _ when r.rechazado => (Symbols.error, MyColors.error, 'Rechazado'),
      _ when r.alDia => (Symbols.verified, MyColors.success, 'Aprobado'),
      _ when r.enRevision => (Symbols.hourglass_top, MyColors.tertiary, 'Esperando revisión'),
      _ => (Symbols.block, MyColors.outline, 'No lo subió'),
    };

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      shadows: const [],
      color: MyColors.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icono, size: 20, color: color, fill: r.alDia ? 1 : 0),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.tipo, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [
                        estado,
                        if (d != null) Formato.haceCuanto(d.actualizadoEn),
                      ].join(' · '),
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
              if (!r.obligatorio) const MyBadge('Ya no se pide', tone: MyBadgeTone.neutral),
            ],
          ),
          if (r.rechazado && d?.observacion != null) ...[
            const SizedBox(height: MySpacing.xs),
            Text('«${d!.observacion}»', style: MyType.bodySm),
          ],
          if (d != null) ...[
            const SizedBox(height: MySpacing.xs),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: MySpacing.xxs,
              children: [
                MyBoton(
                  label: 'Ver',
                  icon: Symbols.visibility,
                  tipo: MyBotonTipo.texto,
                  onPressed: _trabajando || d.archivo == null ? null : _ver,
                ),
                if (d.estado != EstadoAprobacion.rechazado)
                  MyBoton(
                    label: 'Rechazar',
                    icon: Symbols.close,
                    tipo: MyBotonTipo.texto,
                    onPressed: _trabajando ? null : () => _validar(EstadoAprobacion.rechazado),
                  ),
                if (d.estado != EstadoAprobacion.aprobado)
                  MyBoton(
                    label: 'Aprobar',
                    icon: Symbols.check,
                    tipo: MyBotonTipo.secundario,
                    onPressed: _trabajando ? null : () => _validar(EstadoAprobacion.aprobado),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
