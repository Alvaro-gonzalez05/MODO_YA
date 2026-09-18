import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'carrito.dart';
import 'comidas.dart';
import 'cuenta_cliente_page.dart';
import 'iconos_rubro.dart';

/// Home del cliente (D1): dirección, comidas y locales.
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
  Comida? _comida;
  var _texto = '';

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    final direccion = ref.watch(direccionActualProvider);
    final rubros = ref.watch(rubrosProvider).value ?? const <Rubro>[];
    final locales = ref.watch(vidrieraProvider(null));
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
          Icon(Symbols.keyboard_arrow_down, color: MyColors.secondary),
        ],
      ),
    );

    final buscador = MyBuscador(
      hint: '¿Qué se te antoja hoy?',
      onChanged: (t) => setState(() => _texto = t),
    );

    // Barra superior del celular, como la de la app del rider: la marca a la
    // izquierda, la direccion de entrega como pastilla al lado y el avatar
    // que abre "Mi cuenta" a la derecha.
    final cabecera = Row(
      children: [
        const MyLogoMark(size: 30),
        const SizedBox(width: MySpacing.xs),
        Text('MODO YA', style: MyType.headlineSm.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        const SizedBox(width: MySpacing.sm),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: MyPastillaZona(
              zona: direccion?.calle ?? 'Agregá tu dirección',
              maxAncho: 150,
              onTap: () => context.go('/cliente/direcciones'),
            ),
          ),
        ),
        const SizedBox(width: MySpacing.xs),
        GestureDetector(
          onTap: () => mostrarCuentaCliente(context, ref),
          child: MyAvatar(nombre: sesion.nombre, size: 36),
        ),
      ],
    );

    return MyPagina(
      cabecera: cabecera,
      rotulo: 'Malargüe',
      titulo: nombre.isEmpty ? '¿Qué pedimos hoy?' : 'Hola, $nombre',
      bajada: nombre.isEmpty ? null : '¿Qué pedimos hoy?',
      onRefresh: () async {
        ref.invalidate(vidrieraProvider(null));
        ref.invalidate(direccionesProvider);
      },
      children: [
        if (context.esMovil)
          buscador
        else
          Row(
            children: [
              Expanded(flex: 3, child: buscador),
              const SizedBox(width: MySpacing.md),
              Expanded(flex: 2, child: direccionCard),
            ],
          ),
        const SizedBox(height: MySpacing.md),
        MyCambio(
          child: carrito.vacio
              ? const _Carteles(key: ValueKey('carteles'))
              : _BannerCarrito(key: const ValueKey('carrito'), carrito: carrito),
        ),
        const SizedBox(height: MySpacing.lg),
        const MySectionHeader(title: '¿Qué comemos?'),
        const SizedBox(height: MySpacing.sm),
        SizedBox(
          height: 104,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              MyApareceEn(
                child: _BotonComida(
                  nombre: 'Todo',
                  icono: Symbols.apps,
                  activo: _comida == null,
                  onTap: () => setState(() => _comida = null),
                ),
              ),
              for (final (i, c) in comidas.indexed)
                MyApareceEn(
                  retraso: Duration(milliseconds: 35 * (i + 1)),
                  child: _BotonComida(
                    nombre: c.nombre,
                    imagen: c.asset,
                    activo: _comida == c,
                    onTap: () => setState(() => _comida = _comida == c ? null : c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.md),
        MySectionHeader(
          title: _comida == null ? 'Locales en Malargüe' : _comida!.nombre,
          subtitle: _comida == null ? 'Abiertos primero' : 'Locales con ${_comida!.nombre.toLowerCase()}',
          actionLabel: _comida == null ? null : 'Ver todos',
          onAction: _comida == null ? null : () => setState(() => _comida = null),
        ),
        const SizedBox(height: MySpacing.md),
        MyAsync(
          valor: locales,
          onReintentar: () => ref.invalidate(vidrieraProvider(null)),
          datos: (lista) {
            var visibles = lista;
            if (_comida != null) visibles = visibles.where((c) => _comida!.coincideCon(c, rubros)).toList();
            if (q.isNotEmpty) {
              visibles = visibles.where((c) => c.nombre.toLowerCase().contains(q) || c.rubro.toLowerCase().contains(q)).toList();
            }
            if (visibles.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.storefront,
                  title: lista.isEmpty ? 'Todavía no hay locales' : 'No encontramos nada',
                  message: lista.isEmpty
                      ? 'Muy pronto vas a poder pedir a los locales de Malargüe.'
                      : _comida == null
                          ? 'Probá con otra palabra.'
                          : 'Todavía no hay locales de ${_comida!.nombre.toLowerCase()} en MODO YA. Probá con otra comida.',
                  action: _comida == null && q.isEmpty
                      ? null
                      : MyBoton(
                          label: 'Ver todos los locales',
                          tipo: MyBotonTipo.secundario,
                          onPressed: () => setState(() {
                            _comida = null;
                            _texto = '';
                          }),
                        ),
                ),
              );
            }
            return MyGrilla(
              anchoMinimo: 290,
              maxColumnas: 4,
              espacio: MySpacing.md,
              children: [
                for (final (i, c) in visibles.indexed)
                  MyApareceEn(
                    key: ValueKey(c.id),
                    retraso: Duration(milliseconds: 40 * (i.clamp(0, 8))),
                    child: _TarjetaLocal(comercio: c, direccionId: direccion?.id),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Carteles del inicio: los escribe la administracion desde el panel y se
/// actualizan en vivo. Si hay mas de uno, se pasan deslizando; se muestran
/// mientras el carrito esta vacio.
class _Carteles extends ConsumerStatefulWidget {
  const _Carteles({super.key});

  @override
  ConsumerState<_Carteles> createState() => _CartelesState();
}

class _CartelesState extends ConsumerState<_Carteles> {
  final _pagina = PageController();
  var _actual = 0;

  @override
  void dispose() {
    _pagina.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mientras carga (o si falla) se ve el cartel de siempre: el home nunca
    // queda con un hueco.
    final carteles = ref.watch(cartelesActivosProvider).value ??
        const [Cartel(id: '', titulo: 'El mejor sabor,\nen tu casa', subtitulo: 'Delivery rápido, simple y local')];
    if (carteles.isEmpty) return const SizedBox.shrink();
    if (carteles.length == 1) return _BannerMarca(cartel: carteles.first);

    final indice = _actual.clamp(0, carteles.length - 1);
    return Column(
      children: [
        SizedBox(
          height: 124,
          child: PageView.builder(
            controller: _pagina,
            itemCount: carteles.length,
            onPageChanged: (i) => setState(() => _actual = i),
            itemBuilder: (_, i) => _BannerMarca(cartel: carteles[i]),
          ),
        ),
        const SizedBox(height: MySpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < carteles.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == indice ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == indice ? MyColors.primary : MyColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(MyRadius.full),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Banner negro de marca del home (como "El mejor sabor en tu casa" de la
/// referencia), con el texto de un [Cartel].
class _BannerMarca extends StatelessWidget {
  const _BannerMarca({required this.cartel});

  final Cartel cartel;

  @override
  Widget build(BuildContext context) {
    return MyHeroCard(
      padding: const EdgeInsets.fromLTRB(MySpacing.lg, MySpacing.md, MySpacing.md, MySpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cartel.titulo,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: MyType.headlineMd.copyWith(color: MyColors.inverseOnSurface, height: 1.15),
                ),
                if (cartel.subtitulo.trim().isNotEmpty) ...[
                  const SizedBox(height: MySpacing.xs),
                  Text(
                    cartel.subtitulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MyType.labelMd.copyWith(color: MyColors.primary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          const MyLogoMark(size: 84),
        ],
      ),
    );
  }
}

class _BannerCarrito extends StatelessWidget {
  const _BannerCarrito({super.key, required this.carrito});

  final Carrito carrito;

  @override
  Widget build(BuildContext context) {
    return MyPressable(
      escala: 0.98,
      onTap: () => context.go('/cliente/carrito'),
      child: MyHeroCard(
        padding: const EdgeInsets.symmetric(horizontal: MySpacing.md, vertical: MySpacing.sm),
        child: Row(
          children: [
            MyPop(
              disparador: carrito.cantidad,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: MyColors.primary, shape: BoxShape.circle),
                child: Icon(Symbols.shopping_bag, color: MyColors.onPrimary, fill: 1),
              ),
            ),
            const SizedBox(width: MySpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu pedido en ${carrito.comercio!.nombre}',
                    style: MyType.labelLg.copyWith(color: MyColors.inverseOnSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${carrito.cantidad} ${carrito.cantidad == 1 ? 'producto' : 'productos'}',
                    style: MyType.bodySm.copyWith(color: MyColors.primary),
                  ),
                ],
              ),
            ),
            MyNumeroAnimado(
              valor: carrito.subtotal,
              formato: Formato.pesos,
              style: MyType.headlineSm.copyWith(color: MyColors.inverseOnSurface),
            ),
            Icon(Symbols.chevron_right, color: MyColors.primary),
          ],
        ),
      ),
    );
  }
}

/// Botoncito de comida: la foto recortada en alta resolución dentro de un
/// círculo amarillo pálido; al elegirlo el círculo pasa a amarillo de marca
/// con brillo y la foto crece apenas.
class _BotonComida extends StatelessWidget {
  const _BotonComida({required this.nombre, required this.activo, required this.onTap, this.imagen, this.icono});

  final String nombre;
  final String? imagen;
  final IconData? icono;
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
            width: 74,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutBack,
                  width: 66,
                  height: 66,
                  padding: EdgeInsets.all(activo ? 5 : 8),
                  decoration: BoxDecoration(
                    color: activo ? MyColors.primary : MyColors.primaryFixed,
                    shape: BoxShape.circle,
                    border: Border.all(color: activo ? MyColors.onPrimary : Colors.transparent, width: activo ? 2 : 0),
                    boxShadow: activo ? MyShadows.glow : MyShadows.subtle,
                  ),
                  child: imagen == null
                      ? Icon(icono, size: 28, color: activo ? MyColors.onPrimary : MyColors.onPrimaryFixed, fill: 1)
                      : Image.asset(
                          imagen!,
                          package: 'my_ui',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                ),
                const SizedBox(height: MySpacing.xs),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: MyType.labelMd.copyWith(
                    color: activo ? MyColors.onSurface : MyColors.onSurfaceVariant,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
                  ),
                  child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
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
                      Icon(Symbols.sports_motorsports, size: 16, color: MyColors.tertiary),
                      const SizedBox(width: MySpacing.xxs),
                      Flexible(
                        child: Text(
                          cot == null ? 'Envío según tu dirección' : 'Envío ${Formato.pesos(cot.costoEnvio)}',
                          style: MyType.bodySm.copyWith(color: cot == null ? MyColors.secondary : MyColors.tertiary, fontWeight: FontWeight.w600),
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
