import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'oferta_sheet.dart';

/// B2 - Inicio del cadete.
///
/// El interruptor Conectarme/Desconectarme es el control central: define si el
/// motor de asignacion le puede ofrecer envios y si la app comparte ubicacion.
class InicioRepartidorPage extends ConsumerStatefulWidget {
  const InicioRepartidorPage({super.key});

  @override
  ConsumerState<InicioRepartidorPage> createState() =>
      _InicioRepartidorPageState();
}

class _InicioRepartidorPageState extends ConsumerState<InicioRepartidorPage> {
  var _mostrandoOferta = false;

  /// Muestra la oferta apenas el motor de asignacion emite una.
  Future<void> _atenderOferta(OfertaServicio oferta) async {
    if (_mostrandoOferta) return;
    _mostrandoOferta = true;

    final acepto = await OfertaSheet.mostrar(context, oferta);
    _mostrandoOferta = false;
    if (!mounted) return;

    final repo = ref.read(enviosRepositoryProvider);
    final repartidorId = ref.read(sesionProvider).repartidorId!;

    if (acepto == true) {
      final envio = await repo.aceptar(
        envioId: oferta.envio.id,
        repartidorId: repartidorId,
      );
      if (!mounted) return;
      context.goNamed('servicio', pathParameters: {'id': envio.id});
    } else {
      await repo.rechazar(
        envioId: oferta.envio.id,
        repartidorId: repartidorId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repartidor = ref.watch(repartidorActualProvider).value;
    final enCurso = ref.watch(envioEnCursoProvider).value;
    final conectado = repartidor?.conectado ?? false;

    ref.listen(ofertaActualProvider, (_, next) {
      final oferta = next.value;
      if (oferta != null && !oferta.vencida) _atenderOferta(oferta);
    });

    return Column(
      children: [
        MyTopBar(
          zona: 'Malargue urbano',
          onPerfil: () => context.goNamed('perfil'),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MySpacing.screenEdge,
              MySpacing.xs,
              MySpacing.screenEdge,
              MySpacing.dockClearance,
            ),
            children: [
              _TarjetaConexion(
                conectado: conectado,
                nombre: repartidor?.nombre ?? '',
                onCambiar: (valor) {
                  final id = ref.read(sesionProvider).repartidorId!;
                  ref
                      .read(repartidoresRepositoryProvider)
                      .setConectado(id, valor);
                },
              ),

              if (enCurso != null) ...[
                const SizedBox(height: MySpacing.md),
                _ServicioEnCurso(
                  envio: enCurso,
                  onAbrir: () => context.goNamed(
                    'servicio',
                    pathParameters: {'id': enCurso.id},
                  ),
                ),
              ],

              const SizedBox(height: MySpacing.lg),
              Text('Tu jornada', style: MyType.headlineMd),
              const SizedBox(height: MySpacing.sm),
              MyStatRow(
                tiles: [
                  MyStatTile(
                    icon: Symbols.package_2,
                    value: '${repartidor?.viajesCompletados ?? 0}',
                    label: 'Viajes totales',
                  ),
                  MyStatTile(
                    icon: Symbols.star,
                    value: (repartidor?.reputacion ?? 5).toStringAsFixed(1),
                    label: 'Reputacion',
                  ),
                  MyStatTile(
                    icon: Symbols.two_wheeler,
                    value: repartidor?.vehiculo.label ?? '-',
                    label: 'Vehiculo',
                  ),
                ],
              ),

              const SizedBox(height: MySpacing.lg),
              if (conectado && enCurso == null) _EsperandoPedidos(ref: ref),
              if (!conectado)
                const MyEmptyState(
                  icon: Symbols.wifi_off,
                  title: 'Estas desconectado',
                  message:
                      'Conectate para empezar a recibir ofertas de envios '
                      'cerca tuyo.',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TarjetaConexion extends StatelessWidget {
  const _TarjetaConexion({
    required this.conectado,
    required this.nombre,
    required this.onCambiar,
  });

  final bool conectado;
  final String nombre;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    if (!conectado) {
      return MyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MyOverline('Estado'),
                      Text('Desconectado', style: MyType.headlineLg),
                      Text(
                        'No vas a recibir ofertas',
                        style: MyType.bodyMd
                            .copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ),
                Switch(value: false, onChanged: onCambiar),
              ],
            ),
            const SizedBox(height: MySpacing.md),
            FilledButton.icon(
              onPressed: () => onCambiar(true),
              icon: const Icon(Symbols.bolt, size: 22, fill: 1),
              label: const Text('Conectarme'),
            ),
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
              const MyBadge(
                'CONECTADO',
                tone: MyBadgeTone.dark,
                dot: true,
              ),
              const Spacer(),
              Switch(value: true, onChanged: onCambiar),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Text(
            nombre.isEmpty ? 'Listo para trabajar' : 'Hola, $nombre',
            style: MyType.headlineLg.copyWith(color: Colors.white),
          ),
          const SizedBox(height: MySpacing.xxs),
          Text(
            'Estas recibiendo ofertas de envios cerca tuyo. Tu ubicacion se '
            'comparte solo mientras estas conectado.',
            style: MyType.bodyMd.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _ServicioEnCurso extends StatelessWidget {
  const _ServicioEnCurso({required this.envio, required this.onAbrir});

  final Envio envio;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      onTap: onAbrir,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: MyColors.primaryFixed,
              shape: BoxShape.circle,
            ),
            child: const Icon(Symbols.local_shipping,
                size: 24, color: MyColors.primary),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MyOverline('Servicio en curso'),
                Text('#${envio.codigo}', style: MyType.headlineSm),
                Text(
                  envio.estado.label,
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
          Text(
            Formato.pesos(envio.cotizacion.gananciaRepartidor),
            style: MyType.headlineSm.copyWith(color: MyColors.primary),
          ),
          const SizedBox(width: MySpacing.xs),
          const Icon(Symbols.chevron_right, color: MyColors.outline),
        ],
      ),
    );
  }
}

/// Estado de espera. El boton de simular existe solo mientras no hay motor de
/// asignacion real: dispara una oferta para poder recorrer el flujo completo.
class _EsperandoPedidos extends StatelessWidget {
  const _EsperandoPedidos({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      child: Column(
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: MySpacing.md),
          Text('Esperando pedidos', style: MyType.headlineSm),
          const SizedBox(height: MySpacing.xxs),
          Text(
            'Te vamos a avisar apenas haya un envio cerca.',
            style: MyType.bodyMd.copyWith(color: MyColors.secondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: MySpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              final repo = ref.read(enviosRepositoryProvider);
              if (repo is EnviosRepositoryDemo) repo.simularOferta();
            },
            icon: const Icon(Symbols.science, size: 20),
            label: const Text('Simular una oferta (demo)'),
          ),
        ],
      ),
    );
  }
}
