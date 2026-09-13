import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'widgets/envio_tile.dart';

/// Filtros del listado de envios del dia.
enum _Filtro {
  todos('Todos'),
  enCurso('En curso'),
  buscando('Buscando cadete'),
  cerrados('Cerrados');

  const _Filtro(this.label);
  final String label;

  bool aplica(Envio e) => switch (this) {
        todos => true,
        enCurso => e.estado.esActivo &&
            e.estado != EstadoEnvio.buscandoRepartidor,
        buscando => e.estado == EstadoEnvio.buscandoRepartidor,
        cerrados => e.estado.esFinal,
      };
}

/// A4 - Inicio del comercio.
class InicioComercioPage extends ConsumerStatefulWidget {
  const InicioComercioPage({super.key});

  @override
  ConsumerState<InicioComercioPage> createState() => _InicioComercioPageState();
}

class _InicioComercioPageState extends ConsumerState<InicioComercioPage> {
  var _filtro = _Filtro.todos;
  final _busqueda = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enviosAsync = ref.watch(enviosDelComercioProvider);
    final disponibles = ref.watch(repartidoresDisponiblesProvider);
    final tarifario = ref.watch(tarifarioProvider);

    return Column(
      children: [
        MyTopBar(onPerfil: () => context.goNamed('comercioSuscripcion')),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              MySpacing.screenEdge,
              MySpacing.xs,
              MySpacing.screenEdge,
              MySpacing.dockClearance,
            ),
            children: [
              _Buscador(controller: _busqueda, onChanged: (_) => setState(() {})),
              const SizedBox(height: MySpacing.md),

              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _Filtro.values.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: MySpacing.xs),
                  itemBuilder: (_, i) {
                    final f = _Filtro.values[i];
                    return MyChip(
                      f.label,
                      selected: f == _filtro,
                      onTap: () => setState(() => _filtro = f),
                    );
                  },
                ),
              ),

              const SizedBox(height: MySpacing.lg),
              _HeroPedir(
                precioBase: tarifario.value?.precioBase ??
                    Tarifario.inicial.precioBase,
                onPedir: () => context.goNamed('crearEnvio'),
              ),

              const SizedBox(height: MySpacing.md),
              _CadetesActivos(
                cantidad: disponibles.value?.length ?? 0,
              ),

              const SizedBox(height: MySpacing.xl),
              MySectionHeader(
                title: 'Envios de hoy',
                subtitle: 'Seguimiento en tiempo real de tus pedidos',
                actionLabel: 'Ver historial',
                onAction: () => context.goNamed('comercioHistorial'),
              ),
              const SizedBox(height: MySpacing.md),

              enviosAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(MySpacing.xxl),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => MyCard(
                  child: Text('No pudimos cargar los envios.\n$e',
                      style: MyType.bodyMd),
                ),
                data: (envios) {
                  final texto = _busqueda.text.trim().toLowerCase();
                  final lista = envios.where((e) {
                    if (!_filtro.aplica(e)) return false;
                    if (texto.isEmpty) return true;
                    return e.codigo.toLowerCase().contains(texto) ||
                        e.destino.calle.toLowerCase().contains(texto) ||
                        e.cliente.nombre.toLowerCase().contains(texto);
                  }).toList();

                  if (lista.isEmpty) {
                    return const MyEmptyState(
                      icon: Symbols.package_2,
                      title: 'Todavia no hay envios',
                      message:
                          'Cuando pidas un cadete lo vas a ver aca, con su '
                          'estado en vivo.',
                    );
                  }

                  return Column(
                    children: [
                      for (final envio in lista) ...[
                        EnvioTile(
                          envio: envio,
                          onTap: () => context.goNamed(
                            'seguimiento',
                            pathParameters: {'id': envio.id},
                          ),
                        ),
                        const SizedBox(height: MySpacing.sm),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Buscador extends StatelessWidget {
  const _Buscador({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Buscar envio, direccion o cliente',
              prefixIcon: const Icon(Symbols.search,
                  size: 22, color: MyColors.outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MyRadius.full),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MyRadius.full),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MyRadius.full),
                borderSide: const BorderSide(color: MyColors.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: MySpacing.sm),
        const MyCircleIconButton(icon: Symbols.tune, size: 52),
      ],
    );
  }
}

/// Tarjeta hero: el CTA principal de toda la app del comercio.
class _HeroPedir extends StatelessWidget {
  const _HeroPedir({required this.precioBase, required this.onPedir});

  final int precioBase;
  final VoidCallback onPedir;

  @override
  Widget build(BuildContext context) {
    return MyHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MyBadge(
                'SERVICIO FLASH',
                tone: MyBadgeTone.dark,
                icon: Symbols.bolt,
              ),
              const Spacer(),
              const Icon(Symbols.star, size: 18, color: Colors.white, fill: 1),
              const SizedBox(width: MySpacing.xxs),
              Text(
                '4,8',
                style: MyType.labelLg.copyWith(color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Text(
            'Pedir Cadete\nExpress',
            style: MyType.headlineLg.copyWith(color: Colors.white),
          ),
          const SizedBox(height: MySpacing.sm),
          Wrap(
            spacing: MySpacing.xs,
            children: const [
              _HeroTag('Envios locales'),
              _HeroTag('Prioritario'),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Formato.pesos(precioBase),
                style: MyType.displayLg.copyWith(color: Colors.white),
              ),
              const SizedBox(width: MySpacing.xxs),
              Text(
                '/base',
                style: MyType.bodyMd.copyWith(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: onPedir,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: MyColors.primary,
                shape: const StadiumBorder(),
                textStyle: MyType.headlineSm,
              ),
              icon: const Text('Pedir ahora'),
              label: const Icon(Symbols.arrow_forward, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MySpacing.sm,
        vertical: MySpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(MyRadius.full),
      ),
      child: Text(
        label,
        style: MyType.labelMd.copyWith(color: Colors.white),
      ),
    );
  }
}

class _CadetesActivos extends StatelessWidget {
  const _CadetesActivos({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: MyColors.primaryFixed,
              shape: BoxShape.circle,
            ),
            child: const Icon(Symbols.near_me,
                size: 22, color: MyColors.primary, fill: 1),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cantidad == 1
                      ? '1 cadete activo'
                      : '$cantidad cadetes activos',
                  style: MyType.headlineSm,
                ),
                Text(
                  'Cobertura en Malargue centro',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Symbols.schedule, size: 16, color: MyColors.primary),
              const SizedBox(width: MySpacing.xxs),
              Text(
                '~4 min',
                style: MyType.labelLg.copyWith(color: MyColors.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
