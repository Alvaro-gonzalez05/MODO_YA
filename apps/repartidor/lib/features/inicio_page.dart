import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'notificaciones.dart';
import 'oferta_sheet.dart';
import 'ubicacion.dart';

/// Inicio del rider (B2). Conectarme / desconectarme y espera de ofertas.
class InicioRepartidorPage extends ConsumerStatefulWidget {
  const InicioRepartidorPage({super.key});

  @override
  ConsumerState<InicioRepartidorPage> createState() => _InicioRepartidorPageState();
}

class _InicioRepartidorPageState extends ConsumerState<InicioRepartidorPage> {
  /// Ofertas ya mostradas, para no abrir dos veces la misma.
  final _vistas = <String>{};
  var _mostrando = false;

  Future<void> _atender(OfertaServicio oferta) async {
    if (_mostrando || _vistas.contains(oferta.id) || oferta.vencida) return;
    _mostrando = true;
    _vistas.add(oferta.id);

    final respuesta = await OfertaSheet.mostrar(context, oferta);
    _mostrando = false;
    if (!mounted) return;

    // Si se vencio no se llama a nada: la base ya la cierra sola y la pasa al
    // siguiente rider.
    if (respuesta == RespuestaOferta.vencio) return;
    try {
      await ref.read(enviosRepositoryProvider).responderOferta(oferta.id, acepta: respuesta == RespuestaOferta.acepta);
      if (respuesta != RespuestaOferta.acepta || !mounted) return;
      await mostrarExito(
        context,
        titulo: '¡Servicio tuyo!',
        mensaje: oferta.envio.esMandado
            ? 'Andá a retirarlo a ${oferta.envio.origen.calle}.'
            : 'Andá a buscarlo a ${oferta.envio.comercioNombre}.',
        icono: Symbols.sports_motorsports,
      );
      if (mounted) context.push('/servicio/${oferta.envio.id}');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _cambiarConexion(bool conectar) async {
    final ubicacion = ref.read(ubicacionRiderProvider.notifier);
    try {
      if (conectar) {
        if (!await ubicacion.tieneTodoElTiempo() && !await _avisoDeUbicacion()) return;
        final l = await ubicacion.enviar();
        if (l is LecturaError) {
          if (mounted) mostrarError(context, l.mensaje);
          return;
        }
        if (l is LecturaSinSegundoPlano) {
          await _pedirTodoElTiempo();
          return;
        }
        await ref.read(repartidoresRepositoryProvider).setConectado(true);
        ubicacion.empezar();
      } else {
        await ref.read(repartidoresRepositoryProvider).setConectado(false);
        ubicacion.parar();
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  /// El aviso que Google Play exige **antes** de pedir la ubicación en segundo
  /// plano ("divulgación destacada"): qué se junta, para qué, y que sigue con
  /// la app cerrada. Sin este cartel, y con este texto, rechaza la publicación.
  /// Apple pide lo mismo en la revisión. Devuelve si acepta seguir.
  Future<bool> _avisoDeUbicacion() async {
    if (!mounted) return false;
    return confirmar(
      context,
      titulo: 'Tu ubicación mientras estás conectado',
      mensaje: 'MODO YA Rider recopila tu ubicación para ofrecerte los envíos más cercanos y '
          'para que el local y el cliente vean por dónde vas, incluso cuando la app está '
          'cerrada o no la estás usando. Solo mientras estás conectado: al desconectarte '
          'deja de recopilarla.',
      aceptar: 'Entendido, seguir',
    );
  }

  /// Sin "Permitir todo el tiempo" no se conecta: con la pantalla apagada su
  /// ubicación se congela, el motor le sigue ofreciendo envíos como si
  /// estuviera ahí y el local espera a alguien que quizás ya se fue.
  Future<void> _pedirTodoElTiempo() async {
    if (!mounted) return;
    final ir = await confirmar(
      context,
      titulo: 'Permití la ubicación todo el tiempo',
      mensaje: 'Para recibir envíos, MODO YA Rider necesita tu ubicación también con la '
          'pantalla apagada. En Ubicación elegí "Permitir todo el tiempo" y volvé a conectarte.',
      aceptar: 'Abrir ajustes',
    );
    if (ir) await ref.read(ubicacionRiderProvider.notifier).abrirAjustes();
  }

  /// Le sacaron el permiso estando conectado: se lo desconecta para que no le
  /// lleguen ofertas que no va a poder seguir.
  Future<void> _desconectarSinPermiso() async {
    try {
      await ref.read(repartidoresRepositoryProvider).setConectado(false);
      ref.read(ubicacionRiderProvider.notifier).parar();
      if (mounted) {
        mostrarError(context, 'Te desconectamos: sin la ubicación todo el tiempo no te podemos ofrecer envíos.');
      }
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = ref.watch(repartidorActualProvider).value;
    final enCurso = ref.watch(enviosEnCursoProvider).value ?? const <Envio>[];
    final lectura = ref.watch(ubicacionRiderProvider);
    final conectado = rider?.conectado ?? false;
    final carpeta = ref.watch(miCarpetaProvider).value;

    // Si la base dice que esta conectado (por ejemplo, reabrio la app), se
    // retoma el envio periodico de la ubicacion.
    final ubic = ref.read(ubicacionRiderProvider.notifier);
    if (conectado && !ubic.activo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ubic.enviar();
        ubic.empezar();
      });
    }

    // Y al revés: si la base lo desconectó (0078: media hora sin señales), se
    // deja de mandar la ubicación. La app promete que solo se comparte
    // mientras está conectado. Se mira el paso de conectado a desconectado y
    // no el estado: al conectarse, la base tarda un instante en avisarlo y en
    // ese rato el rider todavía figura desconectado.
    ref.listen(repartidorActualProvider, (antes, ahora) {
      if (antes?.value?.conectado == true && ahora.value?.conectado == false && ubic.activo) {
        ubic.parar();
      }
    });

    // Vale también para el que reabre la app ya conectado: la primera lectura
    // dice si sigue teniendo el permiso.
    ref.listen(ubicacionRiderProvider, (antes, ahora) {
      if (conectado && ahora is LecturaSinSegundoPlano && antes is! LecturaSinSegundoPlano) {
        _desconectarSinPermiso();
      }
    });

    ref.listen(ofertasProvider, (_, ahora) {
      final primera = ahora.value?.firstOrNull;
      if (primera != null) _atender(primera);
    });

    return Column(
      children: [
        MyTopBar(
          zona: 'Malargüe',
          onPerfil: () => context.go('/perfil'),
          // Lo que manda la administración a los riders.
          trailing: const MiCampanita(),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance),
            children: [
              if (rider != null && !rider.aprobacion.puedeOperar)
                MyCard(
                  color: MyColors.errorContainer,
                  shadows: const [],
                  child: Text(
                    'Tu cuenta está ${rider.aprobacion.label.toLowerCase()}. Hablalo con la administración.',
                    style: MyType.labelLg.copyWith(color: MyColors.onErrorContainer),
                  ),
                )
              else
                _TarjetaConexion(
                  conectado: conectado,
                  nombre: rider?.nombre ?? '',
                  onCambiar: _cambiarConexion,
                ),

              // Antes la documentacion no tenia pantalla: el rider no sabia que
              // se le pedia ni que le faltaba, y la administracion lo aprobaba
              // a ciegas. El aviso va en el inicio porque el perfil casi nadie
              // lo abre.
              if (carpeta != null && !carpeta.completa) ...[
                const SizedBox(height: MySpacing.sm),
                MyCard(
                  color: MyColors.primaryFixed,
                  shadows: const [],
                  onTap: () => context.go('/perfil/documentacion'),
                  child: Row(
                    children: [
                      Icon(Symbols.badge, color: MyColors.onPrimaryFixed, fill: 1),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(carpeta.titular,
                                style: MyType.labelLg.copyWith(color: MyColors.onPrimaryFixed)),
                            Text(
                              'Tocá para subirla. Sin la documentación al día no podés trabajar.',
                              style: MyType.bodySm.copyWith(color: MyColors.onPrimaryFixedVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(Symbols.chevron_right, color: MyColors.onPrimaryFixed),
                    ],
                  ),
                ),
              ],

              if (conectado && lectura != null) ...[
                const SizedBox(height: MySpacing.sm),
                _EstadoUbicacion(lectura: lectura),
              ],

              if (permitirSimularUbicacion) ...[
                const SizedBox(height: MySpacing.xs),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: ubic.simular,
                  onChanged: (v) => setState(() => ubic.simular = v),
                  title: Text('Simular ubicación (solo desarrollo)', style: MyType.labelMd),
                  subtitle: Text('La app usa el centro de Malargüe si esta PC no tiene GPS', style: MyType.bodySm),
                ),
              ],

              for (final e in enCurso) ...[
                const SizedBox(height: MySpacing.md),
                MyCard(
                  onTap: () => context.push('/servicio/${e.id}'),
                  color: MyColors.primaryFixed,
                  child: Row(
                    children: [
                      Icon(Symbols.local_shipping, color: MyColors.onPrimaryFixed, size: 28, fill: 1),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MyOverline(enCurso.length > 1
                                ? 'Servicio en curso · ${enCurso.indexOf(e) + 1} de ${enCurso.length}'
                                : 'Servicio en curso'),
                            Text('${e.codigo} - ${e.nombreRetiro}', style: MyType.headlineSm),
                            Text('${e.estado.label} · a ${e.destino.calle}', style: MyType.bodySm),
                          ],
                        ),
                      ),
                      Icon(Symbols.chevron_right, color: MyColors.onSurface),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: MySpacing.lg),
              Text('Tu jornada', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),
              MyStatRow(tiles: [
                MyStatTile(icon: Symbols.package_2, value: '${rider?.viajesCompletados ?? 0}', label: 'Viajes'),
                MyStatTile(icon: Symbols.star, value: (rider?.reputacion ?? 5).toStringAsFixed(1), label: 'Reputación'),
                MyStatTile(icon: Symbols.two_wheeler, value: rider?.vehiculo.label ?? '-', label: 'Vehículo'),
              ]),

              const SizedBox(height: MySpacing.lg),
              if (conectado && enCurso.isEmpty)
                MyCard(
                  child: Column(
                    children: [
                      const MyCargando(size: 44, padding: EdgeInsets.zero),
                      const SizedBox(height: MySpacing.md),
                      Text('Esperando pedidos', style: MyType.headlineSm),
                      Text(
                        'Cuando haya un envío cerca te aparece acá. Deja la app abierta.',
                        style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (!conectado)
                const MyEmptyState(
                  icon: Symbols.wifi_off,
                  title: 'Estás desconectado',
                  message: 'Conectate para recibir ofertas de envíos cerca tuyo.',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TarjetaConexion extends StatelessWidget {
  const _TarjetaConexion({required this.conectado, required this.nombre, required this.onCambiar});

  final bool conectado;
  final String nombre;
  final Future<void> Function(bool) onCambiar;

  @override
  Widget build(BuildContext context) {
    if (!conectado) {
      return MyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MyOverline('Estado'),
            Text('Desconectado', style: MyType.headlineLg),
            Text('No vas a recibir ofertas', style: MyType.bodyMd.copyWith(color: MyColors.secondary)),
            const SizedBox(height: MySpacing.md),
            MyBotonAccion(label: 'Conectarme', icon: Symbols.bolt, onPressed: () => onCambiar(true)),
          ],
        ),
      );
    }
    return MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MyBadge('CONECTADO', tone: MyBadgeTone.dark, dot: true),
              const Spacer(),
              TextButton(
                onPressed: () => onCambiar(false),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Desconectarme'),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Text(nombre.isEmpty ? 'Listo para trabajar' : 'Hola, ${nombre.split(' ').first}',
              style: MyType.headlineLg.copyWith(color: Colors.white)),
          Text(
            'Tu ubicación se comparte solo mientras estás conectado.',
            style: MyType.bodyMd.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _EstadoUbicacion extends ConsumerWidget {
  const _EstadoUbicacion({required this.lectura});

  final Lectura lectura;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = lectura;
    if (l is LecturaSinSegundoPlano) {
      // Con "solo mientras se usa la app", al apagar la pantalla deja de
      // mandar: no se puede conectar hasta que lo cambie.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.warning, size: 16, color: MyColors.error),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: Text(
                  'Para conectarte, en Ubicación elegí "Permitir todo el tiempo".',
                  style: MyType.bodySm.copyWith(color: MyColors.error),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: () => ref.read(ubicacionRiderProvider.notifier).abrirAjustes(),
            child: const Text('Abrir ajustes'),
          ),
        ],
      );
    }
    final (icono, texto, color) = switch (l) {
      LecturaOk(simulada: true) => (Symbols.science, 'Ubicación simulada (centro de Malargüe)', MyColors.secondary),
      LecturaOk() => (Symbols.my_location, 'Ubicación enviada', MyColors.success),
      LecturaError(:final mensaje) => (Symbols.location_off, mensaje, MyColors.error),
    };
    return Row(
      children: [
        Icon(icono, size: 16, color: color),
        const SizedBox(width: MySpacing.xs),
        Expanded(child: Text(texto, style: MyType.bodySm.copyWith(color: color))),
      ],
    );
  }
}
