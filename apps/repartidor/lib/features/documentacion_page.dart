import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mi documentación: qué le pide MODO YA según su vehículo, qué subió y qué
/// dijo la administración de cada cosa.
class DocumentacionPage extends ConsumerWidget {
  const DocumentacionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rider = ref.watch(repartidorActualProvider).value;
    final carpeta = ref.watch(miCarpetaProvider);

    return MyPagina(
      volver: () => context.canPop() ? context.pop() : context.go('/perfil'),
      rotulo: 'Mi cuenta',
      titulo: 'Mi documentación',
      bajada: 'Saca la foto y la administración la revisa',
      onRefresh: () async {
        ref.invalidate(documentosExigidosProvider);
        ref.invalidate(documentacionProvider);
      },
      children: [
        MyAsync(
          valor: carpeta,
          onReintentar: () {
            ref.invalidate(documentosExigidosProvider);
            ref.invalidate(documentacionProvider);
          },
          datos: (c) {
            if (rider == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Resumen(carpeta: c, vehiculo: rider.vehiculo),
                const SizedBox(height: MySpacing.md),
                for (final r in c.renglones) ...[
                  _Renglon(renglon: r, repartidorId: rider.id),
                  const SizedBox(height: MySpacing.xs),
                ],
                const SizedBox(height: MySpacing.md),
                MyCard(
                  color: MyColors.secondaryContainer,
                  shadows: const [],
                  child: Row(
                    children: [
                      Icon(Symbols.shield, color: MyColors.secondary),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Text(
                          'Tus archivos los ve solamente la administración de MODO YA. '
                          'Ningún local ni cliente tiene acceso.',
                          style: MyType.bodySm.copyWith(color: MyColors.onSecondaryFixed),
                        ),
                      ),
                    ],
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

class _Resumen extends StatelessWidget {
  const _Resumen({required this.carpeta, required this.vehiculo});

  final CarpetaRider carpeta;
  final Vehiculo vehiculo;

  @override
  Widget build(BuildContext context) {
    final c = carpeta;
    return MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MyBadge(
            c.completa ? 'AL DÍA' : 'TE FALTA ALGO',
            tone: c.completa ? MyBadgeTone.success : MyBadgeTone.dark,
          ),
          const SizedBox(height: MySpacing.sm),
          Text(c.titular, style: MyType.headlineMd.copyWith(color: MyColors.inverseOnSurface)),
          const SizedBox(height: MySpacing.xxs),
          Text(
            c.total == 0
                ? 'Para ${vehiculo.label.toLowerCase()} no se pide documentación.'
                : '${c.alDia} de ${c.total} aprobados · ${vehiculo.label}',
            style: MyType.bodyMd.copyWith(color: MyColors.inverseOnSurface.withValues(alpha: 0.72)),
          ),
        ],
      ),
    );
  }
}

class _Renglon extends ConsumerStatefulWidget {
  const _Renglon({required this.renglon, required this.repartidorId});

  final RenglonDeCarpeta renglon;
  final String repartidorId;

  @override
  ConsumerState<_Renglon> createState() => _RenglonState();
}

class _RenglonState extends ConsumerState<_Renglon> {
  var _abriendo = false;

  RenglonDeCarpeta get r => widget.renglon;

  Future<void> _ver() async {
    final archivo = r.documento?.archivo;
    if (archivo == null) return;
    setState(() => _abriendo = true);
    try {
      // El bucket es privado: hay que pedir un link que vence.
      final url = await ref.read(documentacionRepositoryProvider).link(archivo);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        throw const ErrorModoYa('No pudimos abrir el archivo.');
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  Future<void> _subir() => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => _HojaSubir(
          tipo: r.tipo,
          repartidorId: widget.repartidorId,
          venceEn: r.documento?.venceEn,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final d = r.documento;

    final (icono, color, estado) = switch (r) {
      _ when r.vencido => (Symbols.event_busy, MyColors.error, 'Venció el ${Formato.fechaCorta(d!.venceEn!)}'),
      _ when r.rechazado => (Symbols.error, MyColors.error, 'No nos sirvió'),
      _ when r.alDia => (Symbols.verified, MyColors.success, 'Aprobado'),
      _ when r.enRevision => (Symbols.hourglass_top, MyColors.tertiary, 'Lo estamos revisando'),
      _ => (Symbols.add_a_photo, MyColors.outline, 'Todavía no lo subiste'),
    };

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, fill: r.alDia ? 1 : 0),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.tipo, style: MyType.labelLg),
                    Text(estado, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                  ],
                ),
              ),
              if (!r.obligatorio) const MyBadge('Ya no se pide', tone: MyBadgeTone.neutral),
            ],
          ),
          if (r.rechazado && d?.observacion != null) ...[
            const SizedBox(height: MySpacing.sm),
            MyCard(
              color: MyColors.errorContainer,
              shadows: const [],
              padding: const EdgeInsets.all(MySpacing.sm),
              child: Text(
                d!.observacion!,
                style: MyType.bodySm.copyWith(color: MyColors.onErrorContainer),
              ),
            ),
          ],
          if (r.alDia && d?.venceEn != null) ...[
            const SizedBox(height: MySpacing.xxs),
            Text(
              'Vence el ${Formato.fechaCorta(d!.venceEn!)}',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
          ],
          const SizedBox(height: MySpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (r.subido)
                MyBoton(
                  label: _abriendo ? 'Abriendo…' : 'Ver',
                  icon: Symbols.visibility,
                  tipo: MyBotonTipo.texto,
                  onPressed: _abriendo ? null : _ver,
                ),
              const SizedBox(width: MySpacing.xs),
              MyBoton(
                label: r.subido ? 'Subir de nuevo' : 'Subir',
                icon: Symbols.photo_camera,
                tipo: r.leFaltaAlRider ? MyBotonTipo.principal : MyBotonTipo.secundario,
                onPressed: _subir,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Elegir la foto y, si el documento vence, hasta cuándo vale.
class _HojaSubir extends ConsumerStatefulWidget {
  const _HojaSubir({required this.tipo, required this.repartidorId, this.venceEn});

  final String tipo;
  final String repartidorId;
  final DateTime? venceEn;

  @override
  ConsumerState<_HojaSubir> createState() => _HojaSubirState();
}

class _HojaSubirState extends ConsumerState<_HojaSubir> {
  Uint8List? _bytes;
  String _extension = 'jpg';
  DateTime? _vence;

  @override
  void initState() {
    super.initState();
    _vence = widget.venceEn;
  }

  Future<void> _elegir(ImageSource origen) async {
    try {
      final f = await ImagePicker().pickImage(
        source: origen,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _extension = f.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      });
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _elegirVencimiento() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _vence ?? DateTime(hoy.year + 1, hoy.month, hoy.day),
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 20),
      helpText: 'Hasta cuándo vale',
    );
    if (elegida != null && mounted) setState(() => _vence = elegida);
  }

  Future<void> _guardar() async {
    final bytes = _bytes;
    if (bytes == null) return;
    try {
      await ref.read(documentacionRepositoryProvider).subir(
            repartidorId: widget.repartidorId,
            tipo: widget.tipo,
            bytes: bytes,
            extension: _extension,
            venceEn: _vence,
          );
      ref.invalidate(documentacionProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      mostrarAviso(context, '${widget.tipo} enviado. La administración lo va a revisar.');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        MySpacing.screenEdge,
        MySpacing.md,
        MySpacing.screenEdge,
        MySpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.tipo, style: MyType.headlineMd),
          const SizedBox(height: MySpacing.xxs),
          Text(
            'Que se lea entero y sin brillos. Si no se lee, te lo vamos a rechazar.',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          const SizedBox(height: MySpacing.md),
          if (_bytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(MyRadius.lg),
              child: Image.memory(_bytes!, height: 180, fit: BoxFit.cover),
            ),
            const SizedBox(height: MySpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: MyBoton(
                  label: 'Cámara',
                  icon: Symbols.photo_camera,
                  tipo: MyBotonTipo.secundario,
                  onPressed: () => _elegir(ImageSource.camera),
                ),
              ),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: MyBoton(
                  label: 'Galería',
                  icon: Symbols.image,
                  tipo: MyBotonTipo.secundario,
                  onPressed: () => _elegir(ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          MyCard(
            padding: const EdgeInsets.all(MySpacing.sm),
            shadows: const [],
            color: MyColors.surfaceContainerHigh,
            onTap: _elegirVencimiento,
            child: Row(
              children: [
                Icon(Symbols.event, size: 20, color: MyColors.secondary),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Text(
                    _vence == null
                        ? 'Vencimiento (si tiene)'
                        : 'Vence el ${Formato.fechaCorta(_vence!)}',
                    style: MyType.labelMd,
                  ),
                ),
                if (_vence != null)
                  IconButton(
                    tooltip: 'Sacar el vencimiento',
                    onPressed: () => setState(() => _vence = null),
                    icon: Icon(Symbols.close, size: 18, color: MyColors.outline),
                  ),
              ],
            ),
          ),
          const SizedBox(height: MySpacing.md),
          MyBotonAccion(
            label: 'Enviar a revisión',
            icon: Symbols.upload,
            onPressed: _bytes == null ? null : _guardar,
          ),
        ],
      ),
    );
  }
}
