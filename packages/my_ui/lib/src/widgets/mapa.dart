import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';

import '../tokens.dart';
import '../typography.dart';
import 'controls.dart';

export 'package:latlong2/latlong.dart' show LatLng;

/// Mapas de MODO YA.
///
/// Las baldosas salen de [Entorno.mapaBaldosas], que se fija al compilar. Sin
/// configurar es el servidor publico de OpenStreetMap: sirve para desarrollar,
/// pero su politica de uso NO lo permite para una app en produccion. El
/// proveedor de produccion se elige en env/publico.json, sin tocar codigo (ver
/// docs/salir-a-produccion.md). Todo el resto de la app no se entera: usa estos
/// widgets.
abstract final class MyMapa {
  /// Plaza San Martin, Malargue.
  static const centroMalargue = LatLng(-35.4756, -69.5847);

  static Widget _capaBase() => TileLayer(
        urlTemplate: Entorno.mapaBaldosas,
        userAgentPackageName: 'com.modoya.app',
        maxZoom: 19,
      );

  static Widget _atribucion() => const SimpleAttributionWidget(
        source: Text(Entorno.mapaAtribucion),
        backgroundColor: Color(0xCCFFFFFF),
      );

  /// Haversine y no Vincenty: para distancias de pueblo la diferencia es de
  /// centimetros y se calcula en cada lectura del GPS.
  static const _regla = DistanceHaversine();

  /// Metros entre dos puntos.
  static double metrosEntre(LatLng a, LatLng b) => _regla.distance(a, b);

  /// La ruta manejando de [desde] hasta [hasta].
  ///
  /// La pide la Edge Function `ruta`, que es la que sabe a que proveedor
  /// preguntarle y guarda su clave como secreto. Asi, pasar del servidor
  /// publico de OSRM (que no admite uso productivo) a uno pago o propio es
  /// cargar un secreto en Supabase, sin sacar una version nueva de la app.
  ///
  /// Sin Supabase configurado (pantallas sueltas, pruebas) se le pregunta
  /// directo al OSRM publico, como antes.
  ///
  /// Nunca falla ni tira excepcion: si el servicio no contesta, tarda o
  /// devuelve algo que no se entiende, vuelve la linea recta entre los dos
  /// puntos ([MyRuta.esRecta]) y sin duracion. El mapa siempre tiene algo que
  /// dibujar.
  static Future<MyRuta> ruta({required LatLng desde, required LatLng hasta}) async {
    final recta = MyRuta(puntos: [desde, hasta], esRecta: true);
    if (Entorno.tieneSupabase) return _rutaPorServidor(desde, hasta, recta);
    try {
      final r = await http
          .get(_urlDeRuta(desde, hasta))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return recta;
      final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
      if (cuerpo['code'] != 'Ok') return recta;
      final tramo = (cuerpo['routes'] as List).first as Map<String, dynamic>;
      final coordenadas = ((tramo['geometry'] as Map)['coordinates'] as List).cast<List>();
      // GeoJSON escribe [lng, lat]; LatLng es al reves.
      final puntos = [
        for (final c in coordenadas) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      if (puntos.length < 2) return recta;
      // El routing devuelve el camino pegado al eje de la calle. Si la casa
      // esta en mitad de cuadra, el trazo arranca o termina a unos metros del
      // pin y queda un hueco feo. Se cosen las dos puntas con los puntos de
      // verdad.
      if (metrosEntre(puntos.first, desde) > 5) puntos.insert(0, desde);
      if (metrosEntre(puntos.last, hasta) > 5) puntos.add(hasta);
      final segundos = (tramo['duration'] as num?)?.round();
      return MyRuta(
        puntos: puntos,
        duracion: segundos == null ? null : Duration(seconds: segundos),
      );
    } catch (_) {
      return recta;
    }
  }

  static Future<MyRuta> _rutaPorServidor(LatLng desde, LatLng hasta, MyRuta recta) async {
    try {
      final r = await Backend.db.functions.invoke('ruta', body: {
        'desde': {'lat': desde.latitude, 'lng': desde.longitude},
        'hasta': {'lat': hasta.latitude, 'lng': hasta.longitude},
      }).timeout(const Duration(seconds: 8));
      final cuerpo = r.data as Map<String, dynamic>;
      final puntos = [
        for (final p in (cuerpo['puntos'] as List).cast<List>())
          LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
      ];
      if (puntos.length < 2) return recta;
      // Mismo cosido de puntas que en la consulta directa: el camino viene
      // pegado al eje de la calle y la casa puede estar en mitad de cuadra.
      if (metrosEntre(puntos.first, desde) > 5) puntos.insert(0, desde);
      if (metrosEntre(puntos.last, hasta) > 5) puntos.add(hasta);
      final segundos = (cuerpo['segundos'] as num?)?.round();
      return MyRuta(puntos: puntos, duracion: segundos == null ? null : Duration(seconds: segundos));
    } catch (_) {
      return recta;
    }
  }

  static Uri _urlDeRuta(LatLng a, LatLng b) => Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
        '?overview=full&geometries=geojson',
      );

  /// Abre el selector a pantalla completa y devuelve el punto elegido.
  static Future<LatLng?> elegirPunto(
    BuildContext context, {
    LatLng? inicial,
    String titulo = 'Marcá el punto exacto',
    String ayuda = 'Mové el mapa hasta que el pin quede sobre la puerta.',
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
          IgnorePointer(
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

/// Una ruta calculada entre dos puntos: por donde se va y cuanto tarda.
class MyRuta {
  const MyRuta({required this.puntos, this.duracion, this.esRecta = false});

  /// El camino, punto por punto. Siempre tiene al menos dos.
  final List<LatLng> puntos;

  /// Lo que estima el servicio de routing. Null cuando no contesto.
  final Duration? duracion;

  /// true cuando [puntos] es la linea recta de reserva porque el servicio de
  /// routing no contesto. Sirve para no mostrar un ETA que no existe.
  final bool esRecta;
}

/// Un marcador sobre el mapa.
class MyMarcador {
  const MyMarcador({
    required this.punto,
    required this.icono,
    this._color,
    this.etiqueta,
    this.animado = false,
  });

  final LatLng punto;
  final IconData icono;
  final Color? _color;
  Color get color => _color ?? MyColors.primary;
  final String? etiqueta;

  /// Cuando el punto cambia, se desliza hasta la posicion nueva en vez de
  /// saltar. Para lo que se mueve de verdad (la motito del rider): un pin de
  /// una direccion no necesita deslizarse.
  final bool animado;
}

/// Mapa de solo lectura con uno o varios marcadores y, si se le pasa, el
/// camino dibujado. Encuadra solo.
///
/// Interactivo se puede arrastrar y tiene botones de zoom. La rueda del mouse
/// NO hace zoom a proposito: el mapa suele estar dentro de una pagina con
/// scroll, y la rueda tiene que seguir bajando la pagina.
class MyMapaVista extends StatefulWidget {
  const MyMapaVista({
    super.key,
    required this.marcadores,
    this.ruta,
    this.alto = 180,
    this.radio = MyRadius.lg,
    this.interactivo = false,
  });

  final List<MyMarcador> marcadores;

  /// El camino a dibujar, de [MyRuta.puntos]. Entra en el encuadre junto con
  /// los marcadores.
  final List<LatLng>? ruta;

  final double alto;
  final double radio;
  final bool interactivo;

  @override
  State<MyMapaVista> createState() => _MyMapaVistaState();
}

class _MyMapaVistaState extends State<MyMapaVista> with SingleTickerProviderStateMixin {
  final _control = MapController();

  static const _gestos = InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.scrollWheelZoom;

  /// Posiciones de salida y de llegada del deslizamiento. Lo que se dibuja es
  /// la interpolacion entre las dos, ver [_posiciones].
  late List<LatLng> _desde = [for (final m in widget.marcadores) m.punto];
  late List<LatLng> _hasta = _desde;

  /// Casi todo el hueco que hay entre dos lecturas del rider (5 s): asi el pin
  /// se mueve de corrido en vez de dar un tironcito y quedarse quieto, y llega
  /// igual antes de que entre la siguiente.
  late final _desliz = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))
    ..value = 1;

  /// El mapa recien acepta `fitCamera` cuando ya se midio. El primer encuadre
  /// lo hace `initialCameraFit`.
  var _listo = false;

  /// Alguien arrastro el mapa o toco el zoom. Desde ese momento el
  /// auto-encuadre no se lo roba mas: esta mirando algo.
  var _usuarioMovio = false;

  @override
  void dispose() {
    _desliz.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MyMapaVista anterior) {
    super.didUpdateWidget(anterior);
    // Las opciones se arman una sola vez (ver [_opciones]); si cambia la
    // interactividad hay que rearmarlas para que los gestos se actualicen.
    if (anterior.interactivo != widget.interactivo) _opciones = _crearOpciones();

    final nuevos = [for (final m in widget.marcadores) m.punto];
    final movio = !_mismosPuntos(nuevos, _hasta);
    // Aparecio o desaparecio algo (el rider, el camino): el encuadre de antes
    // ya no sirve ni aunque lo que habia siga a la vista, hay que rehacerlo.
    final cambioQueHay = nuevos.length != _hasta.length ||
        (widget.ruta?.isNotEmpty ?? false) != (anterior.ruta?.isNotEmpty ?? false);
    if (movio) {
      // Sin la misma cantidad de marcadores no hay con quien emparejar al
      // viejo: aparecio o desaparecio alguien y el pin se pone donde va.
      final sePuedeDeslizar = nuevos.length == _hasta.length && widget.marcadores.any((m) => m.animado);
      _desde = sePuedeDeslizar ? _posiciones : nuevos;
      _hasta = nuevos;
      if (sePuedeDeslizar) {
        _desliz.forward(from: 0);
      } else {
        _desliz.value = 1;
      }
    }
    final cambioElCamino = !_mismosPuntos(widget.ruta ?? const [], anterior.ruta ?? const []);
    if (movio || cambioElCamino) _reencuadrar(forzar: cambioQueHay);
  }

  static bool _mismosPuntos(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) return false;
    }
    return true;
  }

  /// Donde esta cada marcador ahora mismo. Los que no son [MyMarcador.animado]
  /// estan siempre en su destino.
  List<LatLng> get _posiciones {
    // Apenas una curva: una moto va a velocidad mas o menos constante entre
    // dos lecturas, un easeOut fuerte la haria arrancar de golpe y frenar.
    final t = Curves.easeOutSine.transform(_desliz.value);
    return [
      for (var i = 0; i < _hasta.length; i++)
        if (widget.marcadores[i].animado && i < _desde.length) _entre(_desde[i], _hasta[i], t) else _hasta[i],
    ];
  }

  /// Interpolacion lineal cruda. Malargue esta lejisimos del antimeridiano y
  /// las lecturas son de pocos metros: no hace falta nada mas fino.
  static LatLng _entre(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  List<LatLng> get _aEncuadrar => [..._hasta, ...?widget.ruta];

  // Arriba mas margen: la etiqueta va encima del pin y se cortaba.
  static const _margenEncuadre = EdgeInsets.fromLTRB(48, 84, 48, 32);

  var _encuadrePendiente = false;
  var _forzarEncuadre = false;

  /// Se pide para despues del frame: mover la camara hace `setState` por
  /// dentro del mapa, y desde `didUpdateWidget` estariamos en medio del build.
  ///
  /// El pedido queda anotado en [_encuadrePendiente] hasta que se cumple. Si
  /// se descartara cuando el mapa todavia no esta medido, el encuadre se
  /// perderia para siempre: no hay nadie mas que lo vuelva a pedir.
  void _reencuadrar({bool forzar = false}) {
    if (_usuarioMovio) return;
    _encuadrePendiente = true;
    _forzarEncuadre = _forzarEncuadre || forzar;
    WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrarAhora());
  }

  void _encuadrarAhora() {
    if (!mounted || !_listo || _usuarioMovio || !_encuadrePendiente) return;
    final puntos = _aEncuadrar;
    if (puntos.isEmpty) return;
    final forzar = _forzarEncuadre;
    _encuadrePendiente = false;
    _forzarEncuadre = false;
    if (!forzar && _todoALaVista(puntos)) return;
    if (puntos.length == 1) {
      _control.move(puntos.first, _control.camera.zoom);
      return;
    }
    _control.fitCamera(
      CameraFit.coordinates(coordinates: puntos, padding: _margenEncuadre, maxZoom: 17),
    );
  }

  /// Re-encuadrar en cada lectura hace saltar la camara cada pocos segundos
  /// aunque el rider se haya movido media cuadra, y el salto se nota mucho mas
  /// que el encuadre perfecto. Solo se re-encuadra cuando algo se esta yendo
  /// de la pantalla; el margen hacia adentro lo anticipa.
  bool _todoALaVista(List<LatLng> puntos) {
    final b = _control.camera.visibleBounds;
    final margenLat = (b.north - b.south) * 0.12;
    final margenLng = (b.east - b.west) * 0.12;
    return puntos.every((p) =>
        p.latitude > b.south + margenLat &&
        p.latitude < b.north - margenLat &&
        p.longitude > b.west + margenLng &&
        p.longitude < b.east - margenLng);
  }

  void _zoom(double delta) {
    final c = _control.camera;
    _control.move(c.center, (c.zoom + delta).clamp(3, 19));
    if (!_usuarioMovio) setState(() => _usuarioMovio = true);
  }

  void _volverAEncuadrar() {
    setState(() => _usuarioMovio = false);
    // Lo pidio el usuario con el dedo: se encuadra aunque todo este a la vista.
    _reencuadrar(forzar: true);
  }

  void _alEstarListo() {
    _listo = true;
    if (_encuadrePendiente) _encuadrarAhora();
  }

  void _alMoverse(MapCamera camara, bool huboGesto) {
    if (!huboGesto || _usuarioMovio) return;
    setState(() => _usuarioMovio = true);
  }

  /// Las opciones se arman una sola vez y no se rehacen en cada build: el mapa
  /// compara la instancia para decidir si tiene que reconfigurarse, y los
  /// `initial…` igual solo valen para el primer encuadre. Lo que viene despues
  /// lo mueve [_reencuadrar].
  late MapOptions _opciones = _crearOpciones();

  MapOptions _crearOpciones() {
    final puntos = _aEncuadrar;
    final gestos = InteractionOptions(flags: widget.interactivo ? _gestos : InteractiveFlag.none);
    if (puntos.length >= 2) {
      return MapOptions(
        initialCameraFit:
            CameraFit.coordinates(coordinates: puntos, padding: _margenEncuadre, maxZoom: 17),
        interactionOptions: gestos,
        onMapReady: _alEstarListo,
        onPositionChanged: _alMoverse,
      );
    }
    return MapOptions(
      initialCenter: puntos.isEmpty ? MyMapa.centroMalargue : puntos.first,
      initialZoom: puntos.isEmpty ? 14 : 16,
      interactionOptions: gestos,
      onMapReady: _alEstarListo,
      onPositionChanged: _alMoverse,
    );
  }

  @override
  Widget build(BuildContext context) {
    final puntos = _aEncuadrar;
    final ruta = widget.ruta;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radio),
      child: SizedBox(
        height: widget.alto,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _control,
              options: _opciones,
              children: [
                MyMapa._capaBase(),
                if (ruta != null && ruta.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: ruta,
                        strokeWidth: 5,
                        color: MyColors.dock,
                        // Con borde blanco: sin el, el trazo se perdia sobre
                        // el gris de las calles y el verde de las plazas.
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),
                // Solo la capa de marcadores se redibuja con el deslizamiento;
                // las baldosas y el camino no tienen por que repintarse 60
                // veces por segundo.
                AnimatedBuilder(
                  animation: _desliz,
                  builder: (context, _) {
                    final posiciones = _posiciones;
                    return MarkerLayer(
                      markers: [
                        for (var i = 0; i < widget.marcadores.length; i++)
                          Marker(
                            point: i < posiciones.length ? posiciones[i] : widget.marcadores[i].punto,
                            width: 120,
                            height: 64,
                            alignment: Alignment.topCenter,
                            child: _Pin(marcador: widget.marcadores[i]),
                          ),
                      ],
                    );
                  },
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
                    // Se ofrece recien cuando el usuario movio el mapa: es la
                    // forma de devolverle el auto-encuadre que le saco.
                    if (_usuarioMovio && puntos.length >= 2) ...[
                      const SizedBox(height: MySpacing.xs),
                      MyCircleIconButton(
                        icon: Symbols.recenter,
                        size: 36,
                        onTap: _volverAEncuadrar,
                      ),
                    ],
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
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 520),
          curve: Curves.elasticOut,
          builder: (context, t, hijo) => Transform.scale(scale: t, alignment: Alignment.bottomCenter, child: hijo),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: marcador.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: MyShadows.control,
            ),
            // Sobre el amarillo de marca el icono va negro; sobre negro/verde, blanco.
            child: Icon(
              marcador.icono,
              size: 18,
              color: marcador.color.computeLuminance() > 0.5 ? MyColors.onPrimary : Colors.white,
              fill: 1,
            ),
          ),
        ),
      ],
    );
  }
}
