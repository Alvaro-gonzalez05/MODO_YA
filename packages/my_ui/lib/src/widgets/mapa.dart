import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import '../typography.dart';
import 'controls.dart';

export 'package:latlong2/latlong.dart' show LatLng;

/// Mapas de MODO YA.
///
/// PROVISORIO: las baldosas salen del servidor publico de OpenStreetMap. Su
/// politica de uso lo permite para desarrollo y volumen bajo, pero NO para una
/// app en produccion. Antes de salir hay que cambiar [_capaBase] por el archivo
/// propio malargue.pmtiles que define el stack (vector_map_tiles_pmtiles).
/// Todo el resto de la app no se entera: usa estos widgets.
abstract final class MyMapa {
  /// Plaza San Martin, Malargue.
  static const centroMalargue = LatLng(-35.4756, -69.5847);

  static Widget _capaBase() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.modoya.app',
        maxZoom: 19,
      );

  static Widget _atribucion() => const SimpleAttributionWidget(
        source: Text('OpenStreetMap'),
        backgroundColor: Color(0xCCFFFFFF),
      );

  /// Abre el selector a pantalla completa y devuelve el punto elegido.
  static Future<LatLng?> elegirPunto(
    BuildContext context, {
    LatLng? inicial,
    String titulo = 'Marca el punto exacto',
    String ayuda = 'Mueve el mapa hasta que el pin quede sobre la puerta.',
  }) =>
      Navigator.of(context, rootNavigator: true).push<LatLng>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _SelectorPunto(inicial: inicial ?? centroMalargue, titulo: titulo, ayuda: ayuda),
        ),
      );
}

class _SelectorPunto extends StatefulWidget {
  const _SelectorPunto({required this.inicial, required this.titulo, required this.ayuda});

  final LatLng inicial;
  final String titulo;
  final String ayuda;

  @override
  State<_SelectorPunto> createState() => _SelectorPuntoState();
}

class _SelectorPuntoState extends State<_SelectorPunto> {
  late LatLng _centro = widget.inicial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        leading: IconButton(
          icon: const Icon(Symbols.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.inicial,
              initialZoom: 17,
              minZoom: 12,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (camara, _) => _centro = camara.center,
            ),
            children: [MyMapa._capaBase(), MyMapa._atribucion()],
          ),
          // El pin queda fijo en el centro y se mueve el mapa por debajo: es
          // mucho mas preciso con el dedo que arrastrar un marcador.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: Icon(Symbols.location_on, size: 48, color: MyColors.primary, fill: 1),
              ),
            ),
          ),
          Positioned(
            left: MySpacing.screenEdge,
            right: MySpacing.screenEdge,
            top: MySpacing.md,
            child: Container(
              padding: const EdgeInsets.all(MySpacing.sm),
              decoration: BoxDecoration(
                color: MyColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(MyRadius.lg),
                boxShadow: MyShadows.control,
              ),
              child: Text(widget.ayuda, style: MyType.bodySm, textAlign: TextAlign.center),
            ),
          ),
          Positioned(
            left: MySpacing.screenEdge,
            right: MySpacing.screenEdge,
            bottom: MySpacing.xl + MediaQuery.paddingOf(context).bottom,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_centro),
              icon: const Icon(Symbols.check, size: 22),
              label: const Text('Usar este punto'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un marcador sobre el mapa.
class MyMarcador {
  const MyMarcador({
    required this.punto,
    required this.icono,
    this.color = MyColors.primary,
    this.etiqueta,
  });

  final LatLng punto;
  final IconData icono;
  final Color color;
  final String? etiqueta;
}

/// Mapa de solo lectura con uno o varios marcadores. Encuadra solo.
///
/// Interactivo se puede arrastrar y tiene botones de zoom. La rueda del mouse
/// NO hace zoom a proposito: el mapa suele estar dentro de una pagina con
/// scroll, y la rueda tiene que seguir bajando la pagina.
class MyMapaVista extends StatefulWidget {
  const MyMapaVista({
    super.key,
    required this.marcadores,
    this.alto = 180,
    this.radio = MyRadius.lg,
    this.interactivo = false,
  });

  final List<MyMarcador> marcadores;
  final double alto;
  final double radio;
  final bool interactivo;

  @override
  State<MyMapaVista> createState() => _MyMapaVistaState();
}

class _MyMapaVistaState extends State<MyMapaVista> {
  final _control = MapController();

  static const _gestos = InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.scrollWheelZoom;

  void _zoom(double delta) {
    final c = _control.camera;
    _control.move(c.center, (c.zoom + delta).clamp(3, 19));
  }

  @override
  Widget build(BuildContext context) {
    final puntos = widget.marcadores.map((m) => m.punto).toList();
    final gestos = InteractionOptions(flags: widget.interactivo ? _gestos : InteractiveFlag.none);
    final MapOptions opciones;
    if (puntos.length >= 2) {
      opciones = MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: puntos,
          padding: const EdgeInsets.all(48),
          maxZoom: 17,
        ),
        interactionOptions: gestos,
      );
    } else {
      opciones = MapOptions(
        initialCenter: puntos.isEmpty ? MyMapa.centroMalargue : puntos.first,
        initialZoom: puntos.isEmpty ? 14 : 16,
        interactionOptions: gestos,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radio),
      child: SizedBox(
        height: widget.alto,
        child: Stack(
          children: [
            FlutterMap(
              // La clave cambia con los puntos para re-encuadrar cuando se mueven.
              key: ValueKey(puntos.map((p) => '${p.latitude},${p.longitude}').join('|')),
              mapController: _control,
              options: opciones,
              children: [
                MyMapa._capaBase(),
                MarkerLayer(
                  markers: [
                    for (final m in widget.marcadores)
                      Marker(
                        point: m.punto,
                        width: 120,
                        height: 64,
                        alignment: Alignment.topCenter,
                        child: _Pin(marcador: m),
                      ),
                  ],
                ),
                MyMapa._atribucion(),
              ],
            ),
            if (widget.interactivo)
              Positioned(
                top: MySpacing.sm,
                right: MySpacing.sm,
                child: Column(
                  children: [
                    MyCircleIconButton(icon: Symbols.add, size: 36, onTap: () => _zoom(1)),
                    const SizedBox(height: MySpacing.xs),
                    MyCircleIconButton(icon: Symbols.remove, size: 36, onTap: () => _zoom(-1)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pin extends StatelessWidget {
  const _Pin({required this.marcador});

  final MyMarcador marcador;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (marcador.etiqueta != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: MyBadge(marcador.etiqueta!, tone: MyBadgeTone.dark),
          ),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: marcador.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: MyShadows.control,
          ),
          child: Icon(marcador.icono, size: 18, color: Colors.white, fill: 1),
        ),
      ],
    );
  }
}
