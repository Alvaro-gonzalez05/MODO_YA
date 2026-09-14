import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import '../widgets/responsive.dart';
import 'plataforma_stub.dart' if (dart.library.io) 'plataforma_io.dart';
import 'version_publicada.dart';

export 'version_publicada.dart';

/// Envuelve la app y avisa cuando hay una versión nueva publicada.
///
/// Se pone en el `builder` de `MaterialApp`: queda por encima de todas las
/// pantallas sin depender del Navigator. Consulta al abrir y cada 6 horas (un
/// local deja la app abierta todo el día).
///
/// Si la versión es obligatoria, tapa la app hasta actualizar.
class MyAvisoActualizacion extends StatefulWidget {
  const MyAvisoActualizacion({
    super.key,
    required this.child,
    required this.app,
    required this.versionActual,
    required this.urlManifiesto,
  });

  final Widget child;

  /// "modo_ya" o "rider": elige el instalador dentro de `ultima.json`.
  final String app;

  /// Versión instalada. Vacía (desarrollo) = no se busca nada.
  final String versionActual;
  final String urlManifiesto;

  @override
  State<MyAvisoActualizacion> createState() => _MyAvisoActualizacionState();
}

enum _Paso { oculto, disponible, descargando, instalando, error }

class _MyAvisoActualizacionState extends State<MyAvisoActualizacion> {
  Timer? _temporizador;
  VersionPublicada? _nueva;
  String? _url;
  var _paso = _Paso.oculto;
  double? _progreso;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || widget.versionActual.isEmpty) return;
    // Unos segundos de gracia: primero que cargue la app.
    Future.delayed(const Duration(seconds: 4), _buscar);
    _temporizador = Timer.periodic(const Duration(hours: 6), (_) => _buscar());
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> _buscar() async {
    if (!mounted || _paso == _Paso.descargando || _paso == _Paso.instalando) return;
    final v = await leerManifiesto(widget.urlManifiesto);
    if (v == null || compararVersiones(v.version, widget.versionActual) <= 0) return;
    final plataforma = await plataformaActual();
    final url = plataforma == null ? null : v.archivos['${widget.app}-$plataforma'];
    if (url == null || !mounted) return;
    // Si ya la había descartado ("Más tarde") no se vuelve a mostrar hasta la
    // próxima versión, salvo que sea obligatoria.
    if (_nueva?.version == v.version && _paso == _Paso.oculto && !v.obligatoria) return;
    setState(() {
      _nueva = v;
      _url = url;
      _paso = _Paso.disponible;
    });
  }

  Future<void> _instalar() async {
    final v = _nueva;
    final url = _url;
    if (v == null || url == null) return;
    setState(() {
      _paso = _Paso.descargando;
      _progreso = 0;
      _error = null;
    });
    try {
      await instalarVersion(url, v.version, (p) {
        if (mounted) setState(() => _progreso = p);
      });
      // En Windows la app ya se cerró. En Android queda el instalador encima.
      if (mounted) setState(() => _paso = _Paso.instalando);
    } catch (e) {
      if (mounted) {
        setState(() {
          _paso = _Paso.error;
          _error = 'No se pudo descargar: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _nueva;
    if (v == null || _paso == _Paso.oculto) return widget.child;

    final tarjeta = _Tarjeta(
      version: v,
      versionActual: widget.versionActual,
      paso: _paso,
      progreso: _progreso,
      error: _error,
      onActualizar: _instalar,
      onMasTarde: v.obligatoria ? null : () => setState(() => _paso = _Paso.oculto),
    );

    final movil = MediaQuery.sizeOf(context).width < MyBreakpoints.tableta;
    return Stack(
      children: [
        widget.child,
        if (v.obligatoria) const ModalBarrier(color: Color(0x991E293B), dismissible: false),
        if (v.obligatoria)
          Center(child: Padding(padding: const EdgeInsets.all(MySpacing.lg), child: tarjeta))
        else
          Positioned(
            left: movil ? MySpacing.md : null,
            right: MySpacing.md,
            top: MediaQuery.paddingOf(context).top + (movil ? MySpacing.sm : 84),
            child: tarjeta,
          ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.version,
    required this.versionActual,
    required this.paso,
    required this.progreso,
    required this.error,
    required this.onActualizar,
    required this.onMasTarde,
  });

  final VersionPublicada version;
  final String versionActual;
  final _Paso paso;
  final double? progreso;
  final String? error;
  final VoidCallback onActualizar;
  final VoidCallback? onMasTarde;

  @override
  Widget build(BuildContext context) {
    final descargando = paso == _Paso.descargando;
    final instalando = paso == _Paso.instalando;

    return Material(
      color: MyColors.surfaceContainerLowest,
      elevation: 12,
      shadowColor: const Color(0x401E293B),
      borderRadius: BorderRadius.circular(MyRadius.card),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(MySpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: MyColors.primaryFixed, shape: BoxShape.circle),
                    child: const Icon(Symbols.system_update, color: MyColors.primary),
                  ),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          version.obligatoria ? 'Tenés que actualizar' : 'Hay una versión nueva',
                          style: MyType.headlineSm,
                        ),
                        Text(
                          'Versión ${version.version} · tenés la $versionActual',
                          style: MyType.bodySm.copyWith(color: MyColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (version.notas.isNotEmpty) ...[
                const SizedBox(height: MySpacing.sm),
                Text(version.notas, style: MyType.bodyMd, maxLines: 6, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: MySpacing.md),
              if (descargando) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(MyRadius.full),
                  child: LinearProgressIndicator(value: progreso, minHeight: 8),
                ),
                const SizedBox(height: MySpacing.xs),
                Text(
                  progreso == null ? 'Descargando…' : 'Descargando ${(progreso! * 100).round()}%',
                  style: MyType.labelMd.copyWith(color: MyColors.secondary),
                ),
              ] else if (instalando)
                Text(
                  'Seguí los pasos del instalador. Si Android te pide permiso para instalar apps de '
                  'este origen, activalo y volvé.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                )
              else ...[
                if (error != null) ...[
                  Text(error!, style: MyType.bodySm.copyWith(color: MyColors.error)),
                  const SizedBox(height: MySpacing.sm),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onMasTarde != null)
                      TextButton(onPressed: onMasTarde, child: const Text('Más tarde')),
                    const SizedBox(width: MySpacing.xs),
                    FilledButton.icon(
                      onPressed: onActualizar,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44), textStyle: MyType.labelLg),
                      icon: const Icon(Symbols.download, size: 19),
                      label: Text(error == null ? 'Actualizar' : 'Reintentar'),
                    ),
                  ],
                ),
              ],
              if (instalando && onMasTarde != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: onMasTarde, child: const Text('Cerrar')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
