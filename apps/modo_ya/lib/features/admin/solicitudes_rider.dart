import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../comun/credenciales.dart';

final _documentosProvider = FutureProvider.autoDispose.family<List<DocumentoSolicitud>, String>(
  (ref, id) => ref.read(solicitudesRiderRepositoryProvider).documentosDe(id),
);

/// Los riders que pidieron dar de alta los locales y esperan revisión. Si no
/// hay ninguna pendiente no ocupa lugar.
class SolicitudesPendientes extends ConsumerWidget {
  const SolicitudesPendientes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendientes = (ref.watch(solicitudesRiderProvider).value ?? const <SolicitudRider>[])
        .where((s) => s.estado == EstadoSolicitudRider.pendiente)
        .toList();
    if (pendientes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MySectionHeader(
          title: pendientes.length == 1 ? '1 rider para aprobar' : '${pendientes.length} riders para aprobar',
          subtitle: 'Los pidieron los locales para que hagan sus envíos',
        ),
        const SizedBox(height: MySpacing.sm),
        for (final s in pendientes) ...[
          _Solicitud(solicitud: s),
          const SizedBox(height: MySpacing.sm),
        ],
        const SizedBox(height: MySpacing.md),
      ],
    );
  }
}

class _Solicitud extends ConsumerStatefulWidget {
  const _Solicitud({required this.solicitud});

  final SolicitudRider solicitud;

  @override
  ConsumerState<_Solicitud> createState() => _SolicitudState();
}

class _SolicitudState extends ConsumerState<_Solicitud> {
  var _trabajando = false;

  SolicitudRider get s => widget.solicitud;

  Future<void> _aprobar() async {
    final ok = await confirmar(
      context,
      titulo: 'Aprobar a ${s.nombre}',
      mensaje: 'Se le crea la cuenta de rider y queda vinculado a '
          '${s.comercioNombre ?? 'el local'}: sus envíos se le ofrecen primero.',
      aceptar: 'Aprobar y crear cuenta',
    );
    if (!ok) return;
    setState(() => _trabajando = true);
    try {
      final alta = await ref.read(cuentasRepositoryProvider).crearRepartidor(
            nombre: s.nombre,
            telefono: s.telefono,
            vehiculo: s.vehiculo,
            solicitudId: s.id,
          );
      ref.invalidate(solicitudesRiderProvider);
      ref.invalidate(todosLosRepartidoresProvider);
      if (!mounted) return;
      await mostrarCredenciales(
        context,
        titulo: 'Rider creado',
        alta: alta,
        esRider: true,
        telefono: s.telefono,
      );
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _rechazar() async {
    final motivo = await pedirTexto(
      context,
      titulo: 'No aprobar a ${s.nombre}',
      label: 'Por qué (lo ve el local)',
      aceptar: 'No aprobar',
    );
    if (motivo == null || motivo.trim().isEmpty) return;
    setState(() => _trabajando = true);
    try {
      await ref.read(solicitudesRiderRepositoryProvider).rechazar(s.id, motivo);
      ref.invalidate(solicitudesRiderProvider);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(_documentosProvider(s.id));

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MyAvatar(nombre: s.nombre, size: 40),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.nombre, style: MyType.headlineSm),
                    Text(
                      '${s.vehiculo.label} · ${s.telefono} · lo pide ${s.comercioNombre ?? 'un local'}',
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.nota != null) ...[
            const SizedBox(height: MySpacing.xs),
            Text('«${s.nota}»', style: MyType.bodySm),
          ],
          const SizedBox(height: MySpacing.sm),
          const MyOverline('Documentación'),
          const SizedBox(height: MySpacing.xs),
          MyAsync(
            valor: docs,
            onReintentar: () => ref.invalidate(_documentosProvider(s.id)),
            datos: (lista) => lista.isEmpty
                ? Text('No subió documentación.', style: MyType.bodySm.copyWith(color: MyColors.error))
                : Wrap(
                    spacing: MySpacing.xs,
                    runSpacing: MySpacing.xs,
                    children: [
                      for (final d in lista)
                        MyChip(
                          d.tipo,
                          onTap: () => launchUrl(Uri.parse(d.url), mode: LaunchMode.externalApplication),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: MySpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              MyBoton(
                label: 'No aprobar',
                icon: Symbols.block,
                tipo: MyBotonTipo.texto,
                onPressed: _trabajando ? null : _rechazar,
              ),
              const SizedBox(width: MySpacing.xs),
              MyBoton(
                label: 'Aprobar',
                icon: Symbols.check,
                onPressed: _trabajando ? null : _aprobar,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
