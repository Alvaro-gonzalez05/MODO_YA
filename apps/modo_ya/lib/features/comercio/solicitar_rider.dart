import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Lo que el local pidió dar de alta, con su estado. Va dentro de "Mis riders".
class SolicitudesDelLocal extends ConsumerWidget {
  const SolicitudesDelLocal({super.key});

  Future<void> _retirar(BuildContext context, WidgetRef ref, SolicitudRider s) async {
    final ok = await confirmar(
      context,
      titulo: 'Retirar la solicitud',
      mensaje: 'La administración deja de revisar el alta de ${s.nombre}.',
      aceptar: 'Retirar',
      peligroso: true,
    );
    if (!ok) return;
    try {
      await ref.read(solicitudesRiderRepositoryProvider).retirar(s.id);
      ref.invalidate(solicitudesRiderProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solicitudes = ref.watch(solicitudesRiderProvider).value ?? const <SolicitudRider>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyCard(
          padding: const EdgeInsets.all(MySpacing.sm),
          child: Row(
            children: [
              Icon(Symbols.person_add, color: MyColors.tertiary),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  '¿Tu cadete todavía no está en MODO YA? Pedí su alta con su '
                  'documentación. Cuando la administración la apruebe, queda en tu lista.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ),
              const SizedBox(width: MySpacing.sm),
              MyBoton(
                label: 'Pedir alta',
                icon: Symbols.add,
                tipo: MyBotonTipo.secundario,
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const _FormularioSolicitud(),
                ),
              ),
            ],
          ),
        ),
        for (final s in solicitudes) ...[
          const SizedBox(height: MySpacing.xs),
          MyCard(
            padding: const EdgeInsets.all(MySpacing.sm),
            child: Row(
              children: [
                MyAvatar(nombre: s.nombre, size: 40),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.nombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        switch (s.estado) {
                          EstadoSolicitudRider.pendiente => '${s.vehiculo.label} · la está revisando la administración',
                          EstadoSolicitudRider.aprobada => '${s.vehiculo.label} · ya hace tus envíos',
                          EstadoSolicitudRider.rechazada => 'No se aprobó: ${s.motivoRechazo ?? ''}',
                        },
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ),
                MyBadge(
                  s.estado.label,
                  tone: switch (s.estado) {
                    EstadoSolicitudRider.pendiente => MyBadgeTone.info,
                    EstadoSolicitudRider.aprobada => MyBadgeTone.success,
                    EstadoSolicitudRider.rechazada => MyBadgeTone.danger,
                  },
                  dot: true,
                ),
                if (s.estado == EstadoSolicitudRider.pendiente)
                  IconButton(
                    tooltip: 'Retirar',
                    onPressed: () => _retirar(context, ref, s),
                    icon: Icon(Symbols.close, color: MyColors.outline),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Datos del cadete y una foto por cada documento que se le exige según su
/// vehículo (`documentos_exigidos`).
class _FormularioSolicitud extends ConsumerStatefulWidget {
  const _FormularioSolicitud();

  @override
  ConsumerState<_FormularioSolicitud> createState() => _FormularioSolicitudState();
}

class _FormularioSolicitudState extends ConsumerState<_FormularioSolicitud> {
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _nota = TextEditingController();
  var _vehiculo = Vehiculo.moto;
  List<String>? _exigidos;
  final _fotos = <String, (Uint8List, String)>{};
  var _enviando = false;

  SolicitudesRiderRepository get _repo => ref.read(solicitudesRiderRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _nombre.addListener(() => setState(() {}));
    _telefono.addListener(() => setState(() {}));
    _cargarExigidos();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargarExigidos() async {
    setState(() => _exigidos = null);
    try {
      final lista = await _repo.documentosExigidos(_vehiculo);
      if (mounted) setState(() => _exigidos = lista);
    } catch (e) {
      if (mounted) {
        setState(() => _exigidos = const []);
        mostrarError(context, e);
      }
    }
  }

  Future<void> _elegirFoto(String tipo) async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 85,
    );
    if (f == null) return;
    final ext = f.name.split('.').last.toLowerCase() == 'png' ? 'png' : 'jpg';
    final bytes = await f.readAsBytes();
    if (mounted) setState(() => _fotos[tipo] = (bytes, ext));
  }

  bool get _completa =>
      _nombre.text.trim().length >= 2 &&
      _telefono.text.trim().length >= 6 &&
      _exigidos != null &&
      _exigidos!.every(_fotos.containsKey);

  Future<void> _enviar() async {
    final comercioId = ref.read(sesionProvider).comercioId;
    if (comercioId == null || !_completa) return;
    setState(() => _enviando = true);
    try {
      await _repo.solicitar(
        comercioId: comercioId,
        nombre: _nombre.text,
        telefono: _telefono.text,
        vehiculo: _vehiculo,
        // Solo lo que se exige hoy: si cambió el vehículo, las fotos del
        // anterior no van.
        documentos: {for (final t in _exigidos!) t: _fotos[t]!},
        nota: _nota.text,
      );
      ref.invalidate(solicitudesRiderProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      await mostrarExito(
        context,
        titulo: 'Solicitud enviada',
        mensaje: 'Te avisamos acá cuando la administración la revise.',
      );
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exigidos = _exigidos;

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
            Text('Pedir el alta de un rider', style: MyType.headlineSm),
            const SizedBox(height: MySpacing.xs),
            Text(
              'La administración revisa la documentación. Si la aprueba, le crea '
              'la cuenta y queda como rider tuyo.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.lg),
            MyCampo(controller: _nombre, label: 'Nombre y apellido', icon: Symbols.person),
            MyCampo(
              controller: _telefono,
              label: 'Teléfono',
              icon: Symbols.call,
              keyboard: TextInputType.phone,
            ),
            const MyOverline('Vehículo'),
            const SizedBox(height: MySpacing.xs),
            Wrap(
              spacing: MySpacing.xs,
              runSpacing: MySpacing.xs,
              children: [
                for (final v in Vehiculo.values)
                  MyChip(
                    v.label,
                    selected: _vehiculo == v,
                    onTap: () {
                      setState(() => _vehiculo = v);
                      _cargarExigidos();
                    },
                  ),
              ],
            ),
            const SizedBox(height: MySpacing.lg),
            const MyOverline('Documentación'),
            const SizedBox(height: MySpacing.xs),
            if (exigidos == null)
              const Padding(
                padding: EdgeInsets.all(MySpacing.md),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final tipo in exigidos)
                Padding(
                  padding: const EdgeInsets.only(bottom: MySpacing.xs),
                  child: MyCard(
                    padding: const EdgeInsets.all(MySpacing.sm),
                    child: Row(
                      children: [
                        Icon(
                          _fotos.containsKey(tipo) ? Symbols.check_circle : Symbols.badge,
                          color: _fotos.containsKey(tipo) ? MyColors.success : MyColors.outline,
                          fill: _fotos.containsKey(tipo) ? 1 : 0,
                        ),
                        const SizedBox(width: MySpacing.sm),
                        Expanded(child: Text(tipo, style: MyType.labelLg)),
                        MyBoton(
                          label: _fotos.containsKey(tipo) ? 'Cambiar' : 'Subir foto',
                          icon: Symbols.photo_camera,
                          tipo: MyBotonTipo.texto,
                          onPressed: () => _elegirFoto(tipo),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: MySpacing.md),
            MyCampo(
              controller: _nota,
              label: 'Algo que quieras aclarar',
              icon: Symbols.short_text,
              obligatorio: false,
              lineas: 2,
            ),
            const SizedBox(height: MySpacing.md),
            MyBotonAccion(
              label: _enviando ? 'Enviando…' : 'Enviar a la administración',
              icon: Symbols.send,
              onPressed: _completa && !_enviando ? _enviar : null,
            ),
            const SizedBox(height: MySpacing.md),
          ],
        ),
      ),
    );
  }
}
