import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

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
      if (respuesta == RespuestaOferta.acepta && mounted) context.push('/servicio/${oferta.envio.id}');
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  Future<void> _cambiarConexion(bool conectar) async {
    final ubicacion = ref.read(ubicacionRiderProvider.notifier);
    try {
      if (conectar) {
        final l = await ubicacion.enviar();
        if (l is LecturaError) {
          if (mounted) mostrarError(context, l.mensaje);
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

  @override
  Widget build(BuildContext context) {
    final rider = ref.watch(repartidorActualProvider).value;
    final enCurso = ref.watch(envioEnCursoProvider).value;
    final lectura = ref.watch(ubicacionRiderProvider);
    final conectado = rider?.conectado ?? false;

    // Si la base dice que esta conectado (por ejemplo, reabrio la app), se
    // retoma el envio periodico de la ubicacion.
    final ubic = ref.read(ubicacionRiderProvider.notifier);
    if (conectado && !ubic.activo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ubic.enviar();
        ubic.empezar();
      });
    }

    ref.listen(ofertasProvider, (_, ahora) {
      final primera = ahora.value?.firstOrNull;
      if (primera != null) _atender(primera);
    });

    return Column(
      children: [
        MyTopBar(zona: 'Malargüe', onPerfil: () => context.go('/perfil')),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.xs, MySpacing.screenEdge, MySpacing.dockClearance),
            children: [
              if (rider != null && !rider.aprobacion.puedeOperar)
                MyCard(
                  color: MyColors.errorContainer,
                  shadows: const [],
                  child: Text(
                    'Tu cuenta esta ${rider.aprobacion.label.toLowerCase()}. Hablalo con la administracion.',
                    style: MyType.labelLg.copyWith(color: MyColors.onErrorContainer),
                  ),
                )
              else
                _TarjetaConexion(
                  conectado: conectado,
                  nombre: rider?.nombre ?? '',
                  onCambiar: _cambiarConexion,
                ),

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
                  subtitle: Text('Usa el centro de Malargüe si esta PC no tiene GPS', style: MyType.bodySm),
                ),
              ],

              if (enCurso != null) ...[
                const SizedBox(height: MySpacing.md),
                MyCard(
                  onTap: () => context.push('/servicio/${enCurso.id}'),
                  color: MyColors.primaryFixed,
                  child: Row(
                    children: [
                      const Icon(Symbols.local_shipping, color: MyColors.primary, size: 28),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const MyOverline('Servicio en curso'),
                            Text('${enCurso.codigo} - ${enCurso.comercioNombre}', style: MyType.headlineSm),
                            Text(enCurso.estado.label, style: MyType.bodySm),
                          ],
                        ),
                      ),
                      const Icon(Symbols.chevron_right, color: MyColors.primary),
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
              if (conectado && enCurso == null)
                MyCard(
                  child: Column(
                    children: [
                      const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3)),
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

class _EstadoUbicacion extends StatelessWidget {
  const _EstadoUbicacion({required this.lectura});

  final Lectura lectura;

  @override
  Widget build(BuildContext context) {
    final l = lectura;
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
