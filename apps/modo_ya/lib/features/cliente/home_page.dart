import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'carrito.dart';
import 'iconos_rubro.dart';

/// Home del cliente (D1): dirección, rubros y locales.
///
/// Del diseño quedaron afuera a propósito los puntos "Club MODO YA", los
/// cupones y las estrellas de los locales: la base no tiene esos datos y el
/// documento de la clienta excluye el programa de puntos. Mejor no mostrar
/// números inventados.
class HomeClientePage extends ConsumerStatefulWidget {
  const HomeClientePage({super.key});

  @override
  ConsumerState<HomeClientePage> createState() => _HomeClientePageState();
}

class _HomeClientePageState extends ConsumerState<HomeClientePage> {
  String? _rubroId;
  var _texto = '';

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    final direccion = ref.watch(direccionActualProvider);
    final rubros = ref.watch(rubrosProvider).value ?? const <Rubro>[];
    final locales = ref.watch(vidrieraProvider(_rubroId));
    final carrito = ref.watch(carritoProvider);
    final q = _texto.trim().toLowerCase();
    final nombre = sesion.nombre.trim().split(' ').first;

    final direccionCard = MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      onTap: () => context.go('/cliente/direcciones'),
      child: Row(
        children: [
          const MyIconoCaja(Symbols.location_on, tamano: 40, circular: true),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(direccion?.calle ?? 'Agregá tu dirección', style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  direccion == null ? 'Para ver cuánto sale el envío' : '${direccion.alias} · Malargüe',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            ),
          ),
          const Icon(Symbols.keyboard_arrow_down, color: MyColors.secondary),
        ],
      ),
    );

    final buscador = MyBuscador(
      hint: 'Buscar pizzas, empanadas, farmacias…',
      onChanged: (t) => setState(() => _texto = t),
    );

    return MyPagina(
      rotulo: 'Malargüe',
      titulo: nombre.isEmpty ? '¿Qué pedimos hoy?' : 'Hola, $nombre',
      bajada: nombre.isEmpty ? null : '¿Qué pedimos hoy?',
      onRefresh: () async {
        ref.invalidate(vidrieraProvider(_rubroId));
        ref.invalidate(direccionesProvider);
      },
      children: [
        if (context.esMovil) ...[
          direccionCard,
          const SizedBox(height: MySpacing.sm),
          buscador,
        ] else
          Row(
            children: [
              Expanded(flex: 3, child: buscador),
              const SizedBox(width: MySpacing.md),
              Expanded(flex: 2, child: direccionCard),
            ],
          ),
        if (!carrito.vacio) ...[
          const SizedBox(height: MySpacing.md),
          MyHeroCard(
            padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
            child: InkWell(
              onTap: () => context.go('/cliente/carrito'),
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
        const SizedBox(height: MySpacing.lg),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              MyApareceEn(
                child: _Rubro(nombre: 'Todos', icono: Symbols.apps, activo: _rubroId == null, onTap: () => setState(() => _rubroId = null)),
              ),
              for (final (i, r) in rubros.indexed)
                MyApareceEn(
                  retraso: Duration(milliseconds: 30 * (i + 1)),
                  child: _Rubro(
                    nombre: r.nombre,
                    icono: iconoDeRubro(r.icono),
                    imagen: imagenDeRubro(nombre: r.nombre, icono: r.icono),
                    activo: _rubroId == r.id,
                    onTap: () => setState(() => _rubroId = _rubroId == r.id ? null : r.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.md),
        const MySectionHeader(title: 'Locales en Malargüe', subtitle: 'Abiertos primero'),
        const SizedBox(height: MySpacing.md),
        MyAsync(
          valor: locales,
          onReintentar: () => ref.invalidate(vidrieraProvider(_rubroId)),
          datos: (lista) {
            final visibles = q.isEmpty
                ? lista
                : lista.where((c) => c.nombre.toLowerCase().contains(q) || c.rubro.toLowerCase().contains(q)).toList();
            if (visibles.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.storefront,
                  title: lista.isEmpty ? 'Todavía no hay locales' : 'No encontramos nada',
                  message: lista.isEmpty
                      ? 'Muy pronto vas a poder pedir a los locales de Malargüe.'
                      : 'Probá con otra palabra o con otro rubro.',
                ),
              );
            }
            return MyGrilla(
              anchoMinimo: 290,
              maxColumnas: 4,
              espacio: MySpacing.md,
              children: [for (final c in visibles) _TarjetaLocal(comercio: c, direccionId: direccion?.id)],
            );
          },
        ),
      ],
    );
  }
}

class _Rubro extends StatelessWidget {
  const _Rubro({required this.nombre, required this.icono, required this.activo, required this.onTap, this.imagen});

  final String nombre;
  final IconData icono;
  final String? imagen;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: MySpacing.sm),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: MyPressable(
          onTap: onTap,
          child: SizedBox(
            width: 76,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: imagen != null
                        ? MyColors.surfaceContainerLowest
                        : (activo ? MyColors.primary : MyColors.surfaceContainerLowest),
                    shape: BoxShape.circle,
                    boxShadow: activo ? MyShadows.control : MyShadows.subtle,
                    border: Border.all(color: activo ? MyColors.primary : MyColors.outlineVariant, width: activo ? 2.5 : 1),
                  ),
                  child: imagen == null
                      ? Icon(icono, size: 26, color: activo ? Colors.white : MyColors.primary)
                      : ClipOval(
                          child: Transform.scale(
                            // Las fotos vienen recortadas de una grilla: un pelin
                            // de zoom saca cualquier resto de borde/otra celda.
                            scale: 1.18,
                            child: Image.asset(
                              imagen!,
                              package: 'my_ui',
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: MySpacing.xxs),
                Text(
                  nombre,
                  style: MyType.labelMd.copyWith(color: activo ? MyColors.primary : MyColors.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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
      onTap: () => context.go('/cliente/local/${comercio.id}'),
      child: Opacity(
        opacity: comercio.abierto ? 1 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                MyImagen(url: comercio.logoUrl, alto: 150, radio: MyRadius.card, icono: iconoDeRubro(null)),
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
                  Text(comercio.nombre, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(comercio.rubro, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                  const SizedBox(height: MySpacing.xs),
                  Row(
                    children: [
                      const Icon(Symbols.sports_motorsports, size: 16, color: MyColors.secondary),
                      const SizedBox(width: MySpacing.xxs),
                      Flexible(
                        child: Text(
                          cot == null ? 'Envío según tu dirección' : 'Envío ${Formato.pesos(cot.costoEnvio)}',
                          style: MyType.bodySm.copyWith(color: MyColors.secondary),
                          overflow: TextOverflow.ellipsis,
                        ),
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
