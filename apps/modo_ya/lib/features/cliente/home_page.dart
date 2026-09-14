import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'carrito.dart';
import 'iconos_rubro.dart';

/// Home del cliente (D1): direccion, rubros y locales.
///
/// Del diseno quedaron afuera a proposito los puntos "Club MODO YA", los
/// cupones y las estrellas de los locales: la base no tiene esos datos y el
/// documento de la clienta excluye el programa de puntos. Mejor no mostrar
/// numeros inventados.
class HomeClientePage extends ConsumerStatefulWidget {
  const HomeClientePage({super.key});

  @override
  ConsumerState<HomeClientePage> createState() => _HomeClientePageState();
}

class _HomeClientePageState extends ConsumerState<HomeClientePage> {
  String? _rubroId;
  final _busqueda = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direccion = ref.watch(direccionActualProvider);
    final rubros = ref.watch(rubrosProvider).value ?? const <Rubro>[];
    final locales = ref.watch(vidrieraProvider(_rubroId));
    final carrito = ref.watch(carritoProvider);
    final texto = _busqueda.text.trim().toLowerCase();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(vidrieraProvider(_rubroId));
          ref.invalidate(direccionesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MySpacing.screenEdge, MySpacing.md, MySpacing.screenEdge, MySpacing.dockClearance),
          children: [
            // ---- Direccion -------------------------------------------------
            MyCard(
              padding: const EdgeInsets.all(MySpacing.sm),
              color: MyColors.surfaceContainerLow,
              shadows: const [],
              onTap: () => context.push('/cliente/direcciones'),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: MyColors.primaryFixed, shape: BoxShape.circle),
                    child: const Icon(Symbols.location_on, size: 20, color: MyColors.primary, fill: 1),
                  ),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          direccion?.calle ?? 'Agrega tu direccion',
                          style: MyType.labelLg,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          direccion == null ? 'Para ver cuanto sale el envio' : '${direccion.alias} - Malargue',
                          style: MyType.bodySm.copyWith(color: MyColors.secondary),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Symbols.keyboard_arrow_down, color: MyColors.outline),
                ],
              ),
            ),
            const SizedBox(height: MySpacing.md),

            // ---- Busqueda --------------------------------------------------
            TextField(
              controller: _busqueda,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar pizzas, empanadas, farmacias...',
                prefixIcon: const Icon(Symbols.search, size: 22, color: MyColors.outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(MyRadius.full), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(MyRadius.full), borderSide: BorderSide.none),
              ),
            ),

            if (!carrito.vacio) ...[
              const SizedBox(height: MySpacing.md),
              MyHeroCard(
                padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
                child: InkWell(
                  onTap: () => context.push('/cliente/carrito'),
                  child: Row(
                    children: [
                      const Icon(Symbols.shopping_bag, color: Colors.white),
                      const SizedBox(width: MySpacing.sm),
                      Expanded(
                        child: Text(
                          'Tu pedido en ${carrito.comercio!.nombre} (${carrito.cantidad})',
                          style: MyType.labelLg.copyWith(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(Formato.pesos(carrito.subtotal), style: MyType.headlineSm.copyWith(color: Colors.white)),
                      const Icon(Symbols.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],

            // ---- Rubros ----------------------------------------------------
            const SizedBox(height: MySpacing.lg),
            Text('Que te provoca hoy?', style: MyType.headlineMd),
            const SizedBox(height: MySpacing.sm),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _Rubro(nombre: 'Todos', icono: Symbols.apps, activo: _rubroId == null, onTap: () => setState(() => _rubroId = null)),
                  for (final r in rubros)
                    _Rubro(
                      nombre: r.nombre,
                      icono: iconoDeRubro(r.icono),
                      activo: _rubroId == r.id,
                      onTap: () => setState(() => _rubroId = _rubroId == r.id ? null : r.id),
                    ),
                ],
              ),
            ),

            // ---- Locales ---------------------------------------------------
            const SizedBox(height: MySpacing.md),
            MySectionHeader(title: 'Locales en Malargue', subtitle: 'Abiertos primero'),
            const SizedBox(height: MySpacing.md),
            MyAsync(
              valor: locales,
              onReintentar: () => ref.invalidate(vidrieraProvider(_rubroId)),
              datos: (lista) {
                final visibles = texto.isEmpty
                    ? lista
                    : lista.where((c) => c.nombre.toLowerCase().contains(texto) || c.rubro.toLowerCase().contains(texto)).toList();
                if (visibles.isEmpty) {
                  return MyEmptyState(
                    icon: Symbols.storefront,
                    title: lista.isEmpty ? 'Todavia no hay locales' : 'No encontramos nada',
                    message: lista.isEmpty
                        ? 'Muy pronto vas a poder pedir a los locales de Malargue.'
                        : 'Proba con otra palabra o con otro rubro.',
                  );
                }
                return Column(
                  children: [
                    for (final c in visibles) ...[
                      _TarjetaLocal(comercio: c, direccionId: direccion?.id),
                      const SizedBox(height: MySpacing.md),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Rubro extends StatelessWidget {
  const _Rubro({required this.nombre, required this.icono, required this.activo, required this.onTap});

  final String nombre;
  final IconData icono;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: MySpacing.sm),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: activo ? MyColors.primaryFixed : MyColors.secondaryContainer,
                  shape: BoxShape.circle,
                  border: activo ? Border.all(color: MyColors.primary, width: 2) : null,
                ),
                child: Icon(icono, size: 26, color: MyColors.primary),
              ),
              const SizedBox(height: MySpacing.xxs),
              Text(nombre, style: MyType.labelSm, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaLocal extends ConsumerWidget {
  const _TarjetaLocal({required this.comercio, required this.direccionId});

  final Comercio comercio;
  final String? direccionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cot = direccionId == null
        ? null
        : ref.watch(cotizacionEnvioProvider((comercioId: comercio.id, direccionId: direccionId!))).value;

    return MyCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/cliente/local/${comercio.id}'),
      child: Opacity(
        opacity: comercio.abierto ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 8,
                  child: MyImagen(url: comercio.logoUrl, radio: 0, icono: iconoDeRubro(null)),
                ),
                Positioned(
                  left: MySpacing.sm,
                  top: MySpacing.sm,
                  child: MyBadge(
                    comercio.abierto ? 'Abierto' : 'Cerrado',
                    tone: comercio.abierto ? MyBadgeTone.success : MyBadgeTone.dark,
                    dot: true,
                  ),
                ),
                if (cot != null)
                  Positioned(
                    right: MySpacing.sm,
                    bottom: MySpacing.sm,
                    child: MyBadge('${cot.minutosEstimados} min', tone: MyBadgeTone.neutral, icon: Symbols.schedule),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(MySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comercio.nombre, style: MyType.headlineSm),
                  const SizedBox(height: 2),
                  Text(comercio.rubro, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                  const SizedBox(height: MySpacing.xs),
                  Row(
                    children: [
                      const Icon(Symbols.sports_motorsports, size: 16, color: MyColors.secondary),
                      const SizedBox(width: MySpacing.xxs),
                      Text(
                        cot == null ? 'Envio segun tu direccion' : 'Envio ${Formato.pesos(cot.costoEnvio)}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
