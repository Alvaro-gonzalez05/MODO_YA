import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_emergente.dart';

/// Campañas del local: invertir para vender más.
///
///   * Publicidad: aparece destacado en la app, gasta hasta X por día.
///   * MODO YA Plus: les regala el envío a los clientes con Plus.
///
/// No se paga por adelantado: lo que gasta se le descuenta de sus ventas en la
/// liquidación. Por eso cada campaña tiene un tope que pone el local.
class CampaniasPage extends ConsumerWidget {
  const CampaniasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campanias = ref.watch(campaniasDelComercioProvider);

    return MyPagina(
      rotulo: 'Crecer',
      titulo: 'Campañas',
      bajada: 'Invertí para que más gente te pida. Lo que gastás se descuenta de tus ventas.',
      children: [
        MyAsync(
          valor: campanias,
          onReintentar: () => ref.invalidate(campaniasDelComercioProvider),
          datos: (lista) {
            final activas = lista.where((c) => c.estado != EstadoCampania.finalizada).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (activas.isEmpty)
                  const _Planes()
                else ...[
                  for (final c in activas) ...[
                    _TarjetaCampania(campania: c),
                    const SizedBox(height: MySpacing.md),
                  ],
                  _Agregar(yaTiene: activas.map((c) => c.tipo).toSet()),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Lo que ve un local que todavía no invirtió nada.
class _Planes extends ConsumerWidget {
  const _Planes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MyCard(
          child: Row(
            children: [
              const MyIconoCaja(Symbols.rocket_launch, tamano: 48, circular: true),
              const SizedBox(width: MySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Todavía no tenés campañas', style: MyType.headlineSm),
                    Text(
                      'Elegí cuánto querés invertir. Podés pausarla o cambiar el monto cuando quieras.',
                      style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MySpacing.lg),
        Text('Publicidad: aparecés destacado', style: MyType.headlineSm),
        Text(
          'Tu local va primero en la lista y en su rubro, con una etiqueta de "Destacado".',
          style: MyType.bodySm.copyWith(color: MyColors.secondary),
        ),
        const SizedBox(height: MySpacing.sm),
        // MyGrilla y no un GridView con proporción fija: en el celular la
        // tarjeta medía el ancho dividido 2,6 y el botón quedaba afuera.
        const MyGrilla(
          anchoMinimo: 220,
          maxColumnas: 3,
          espacio: MySpacing.sm,
          children: [
            _Plan(diario: 5000, recomendado: false, pedidosEstimados: 18, visitas: 220),
            _Plan(diario: 9000, recomendado: true, pedidosEstimados: 31, visitas: 375),
            _PlanPropio(),
          ],
        ),
        const SizedBox(height: MySpacing.lg),
        Text('MODO YA Plus: envío gratis para tus clientes', style: MyType.headlineSm),
        Text(
          'Los clientes con Plus ven "Envío gratis" en tu local. Vos ponés el envío; el rider cobra igual.',
          style: MyType.bodySm.copyWith(color: MyColors.secondary),
        ),
        const SizedBox(height: MySpacing.sm),
        MyCard(
          color: MyColors.primaryFixed,
          shadows: const [],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Symbols.local_shipping, color: MyColors.onPrimaryFixed),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Text(
                      'Los clientes de Plus piden más seguido y eligen los locales adheridos.',
                      style: MyType.bodyMd.copyWith(color: MyColors.onPrimaryFixed),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MySpacing.sm),
              MyBoton(
                label: 'Adherirme a Plus',
                icon: Symbols.add,
                onPressed: () => nuevaCampania(context, ref, TipoCampania.plus),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Plan extends ConsumerWidget {
  const _Plan({required this.diario, required this.recomendado, required this.pedidosEstimados, required this.visitas});

  final int diario;
  final bool recomendado;
  final int pedidosEstimados;
  final int visitas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyCard(
      color: recomendado ? MyColors.dock : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (recomendado)
            const MyBadge('Recomendado', tone: MyBadgeTone.ember, icon: Symbols.star),
          const SizedBox(height: MySpacing.xs),
          Text(
            '${Formato.pesos(diario)} / día',
            style: MyType.headlineMd.copyWith(color: recomendado ? Colors.white : null),
          ),
          Text(
            'Hasta ${Formato.pesos(diario * 30)} por mes',
            style: MyType.bodySm.copyWith(color: recomendado ? Colors.white70 : MyColors.secondary),
          ),
          const SizedBox(height: MySpacing.sm),
          _Estimado(Symbols.receipt_long, '+$pedidosEstimados pedidos', claro: recomendado),
          _Estimado(Symbols.visibility, '+$visitas visitas a tu local', claro: recomendado),
          const Spacer(),
          const SizedBox(height: MySpacing.sm),
          MyBoton(
            label: 'Empezar',
            onPressed: () => nuevaCampania(context, ref, TipoCampania.publicidad, diario: diario),
          ),
        ],
      ),
    );
  }
}

class _PlanPropio extends ConsumerWidget {
  const _PlanPropio();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Armar la mía', style: MyType.headlineSm),
          const SizedBox(height: MySpacing.xs),
          Text(
            'Vos elegís cuánto por día y cuánto en total.',
            style: MyType.bodySm.copyWith(color: MyColors.secondary),
          ),
          const Spacer(),
          MyBoton(
            label: 'Empezar',
            tipo: MyBotonTipo.secundario,
            onPressed: () => nuevaCampania(context, ref, TipoCampania.publicidad),
          ),
        ],
      ),
    );
  }
}

class _Estimado extends StatelessWidget {
  const _Estimado(this.icono, this.texto, {required this.claro});

  final IconData icono;
  final String texto;
  final bool claro;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icono, size: 18, color: claro ? Colors.white70 : MyColors.secondary),
            const SizedBox(width: MySpacing.xs),
            Flexible(
              child: Text(
                texto,
                style: MyType.bodySm.copyWith(color: claro ? Colors.white : MyColors.onSurface),
              ),
            ),
          ],
        ),
      );
}

/// Una campaña en marcha, con su rendimiento y su fondo.
class _TarjetaCampania extends ConsumerWidget {
  const _TarjetaCampania({required this.campania});

  final Campania campania;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rend = ref.watch(rendimientoCampaniaProvider(campania.id)).value;
    final esPlus = campania.tipo == TipoCampania.plus;
    final repo = ref.read(campaniasRepositoryProvider);

    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MyIconoCaja(esPlus ? Symbols.local_shipping : Symbols.campaign),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(campania.tipo.label, style: MyType.headlineSm),
                    Text(
                      esPlus
                          ? 'Envío gratis para los clientes con Plus'
                          : 'Hasta ${Formato.pesos(campania.presupuestoDiario ?? 0)} por día',
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
              MyBadge(
                campania.estado.label,
                tone: switch (campania.estado) {
                  EstadoCampania.activa => MyBadgeTone.success,
                  EstadoCampania.sinFondo => MyBadgeTone.ember,
                  _ => MyBadgeTone.neutral,
                },
                dot: campania.enMarcha,
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),

          // Rendimiento, como en las apps grandes.
          if (rend != null && rend.costo > 0) ...[
            Container(
              padding: const EdgeInsets.all(MySpacing.md),
              decoration: BoxDecoration(
                color: MyColors.claroSuperficieAlt,
                borderRadius: BorderRadius.circular(MyRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estás recibiendo \$${rend.retorno.toStringAsFixed(2).replaceAll('.', ',')} por cada peso que invertís.',
                    style: MyType.labelLg,
                  ),
                  const Divider(height: MySpacing.lg),
                  Wrap(
                    spacing: MySpacing.lg,
                    runSpacing: MySpacing.sm,
                    children: [
                      _Kpi('Ingresos', Formato.pesos(rend.ingresos)),
                      _Kpi('Pedidos', '${rend.pedidos}'),
                      _Kpi('Costo', Formato.pesos(rend.costo)),
                      _Kpi('Retorno', rend.retornoTexto, badge: rend.calificacion),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: MySpacing.md),
          ],

          // Fondo consumido.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gastado ${Formato.pesos(campania.gastado)} de ${Formato.pesos(campania.presupuesto)}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ),
              Text('Quedan ${Formato.pesos(campania.disponible)}', style: MyType.labelMd),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(MyRadius.full),
            child: LinearProgressIndicator(value: campania.consumido, minHeight: 8),
          ),
          const SizedBox(height: MySpacing.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              MyBoton(
                label: 'Ver gastos',
                icon: Symbols.receipt_long,
                tipo: MyBotonTipo.texto,
                onPressed: () => _verGastos(context, ref),
              ),
              if (campania.estado == EstadoCampania.activa)
                MyBoton(
                  label: 'Pausar',
                  icon: Symbols.pause,
                  tipo: MyBotonTipo.secundario,
                  onPressed: () => _cambiarEstado(context, repo, EstadoCampania.pausada),
                )
              else if (campania.estado == EstadoCampania.pausada)
                MyBoton(
                  label: 'Reanudar',
                  icon: Symbols.play_arrow,
                  tipo: MyBotonTipo.secundario,
                  onPressed: () => _cambiarEstado(context, repo, EstadoCampania.activa),
                ),
              MyBoton(
                label: 'Sumar fondo',
                icon: Symbols.add,
                onPressed: () => _sumarFondo(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Sin esto un error de la base al pausar no se mostraba en ningún lado.
  Future<void> _cambiarEstado(BuildContext context, CampaniasRepository repo, EstadoCampania nuevo) async {
    try {
      await repo.cambiarEstado(campania.id, nuevo);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  Future<void> _sumarFondo(BuildContext context) => mostrarFormularioEmergente(
        context,
        titulo: 'Sumar fondo',
        builder: (_) => _FormularioFondo(campania: campania),
      );

  Future<void> _verGastos(BuildContext context, WidgetRef ref) => mostrarFormularioEmergente(
        context,
        titulo: 'Gastos de ${campania.tipo.label}',
        builder: (h) => Consumer(
          builder: (context, ref, _) {
            final gastos = ref.watch(gastosDeCampaniaProvider(campania.id)).value ?? const <GastoCampania>[];
            if (gastos.isEmpty) {
              return Text('Todavía no gastó nada.', style: MyType.bodyMd.copyWith(color: MyColors.secondary));
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final g in gastos)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(g.detalle, style: MyType.bodyMd),
                    subtitle: Text(Formato.fechaCorta(g.fecha), style: MyType.bodySm.copyWith(color: MyColors.secondary)),
                    trailing: Text(Formato.pesos(g.monto), style: MyType.labelLg),
                  ),
              ],
            );
          },
        ),
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.titulo, this.valor, {this.badge});

  final String titulo;
  final String valor;
  final String? badge;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MyOverline(titulo),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(valor, style: MyType.headlineSm),
              if (badge != null) ...[
                const SizedBox(width: MySpacing.xs),
                MyBadge(badge!, tone: MyBadgeTone.success),
              ],
            ],
          ),
        ],
      );
}

class _Agregar extends ConsumerWidget {
  const _Agregar({required this.yaTiene});

  final Set<TipoCampania> yaTiene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final faltan = TipoCampania.values.where((t) => !yaTiene.contains(t)).toList();
    if (faltan.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: MySpacing.xs,
      runSpacing: MySpacing.xs,
      children: [
        for (final t in faltan)
          MyBoton(
            label: t == TipoCampania.plus ? 'Adherirme a MODO YA Plus' : 'Crear publicidad',
            icon: Symbols.add,
            tipo: MyBotonTipo.secundario,
            onPressed: () => nuevaCampania(context, ref, t),
          ),
      ],
    );
  }
}

/// Sumarle plata al tope de una campaña.
///
/// Antes era un campo de texto suelto, sin punto de miles: "50000" había que
/// contarlo, y no decía en cuánto quedaba el tope.
///
/// Es un widget con estado (y no un formulario armado en una función) para que
/// el controlador viva hasta que la hoja termine de cerrarse.
class _FormularioFondo extends ConsumerStatefulWidget {
  const _FormularioFondo({required this.campania});

  final Campania campania;

  @override
  ConsumerState<_FormularioFondo> createState() => _FormularioFondoState();
}

class _FormularioFondoState extends ConsumerState<_FormularioFondo> {
  final _form = GlobalKey<FormState>();
  final _suma = TextEditingController();

  @override
  void dispose() {
    _suma.dispose();
    super.dispose();
  }

  Future<void> _sumar() async {
    if (!_form.currentState!.validate()) return;
    final c = widget.campania;
    try {
      await ref.read(campaniasRepositoryProvider).cambiarPresupuesto(c.id, c.presupuesto + MilesFormatter.leer(_suma.text)!);
      if (!mounted) return;
      mostrarAviso(context, 'Fondo actualizado');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.campania;
    final n = MilesFormatter.leer(_suma.text) ?? 0;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${c.tipo.label}: hoy el tope es ${Formato.pesos(c.presupuesto)} y quedan ${Formato.pesos(c.disponible)}.',
            style: MyType.bodyMd.copyWith(color: MyColors.secondary),
          ),
          const SizedBox(height: MySpacing.md),
          MyCampo(
            controller: _suma,
            label: 'Cuánto le sumás',
            hint: 'Ej: 30.000',
            icon: Symbols.add_card,
            miles: true,
            onChanged: (_) => setState(() {}),
            validar: (v) => (MilesFormatter.leer(v) ?? 0) <= 0 ? 'Escribí cuánto le sumás' : null,
          ),
          if (n > 0) ...[
            Text('El tope pasa a ${Formato.pesos(c.presupuesto + n)}.', style: MyType.labelLg),
            const SizedBox(height: MySpacing.md),
          ],
          MyBotonAccion(label: 'Sumar', icon: Symbols.add, onPressed: _sumar),
        ],
      ),
    );
  }
}

/// Alta de una campaña: el tope total y, si es publicidad, cuánto por día.
Future<void> nuevaCampania(BuildContext context, WidgetRef ref, TipoCampania tipo, {int? diario}) async {
  if (ref.read(sesionProvider).comercioId == null) return;
  await mostrarFormularioEmergente(
    context,
    titulo: tipo == TipoCampania.plus ? 'Adherirme a MODO YA Plus' : 'Nueva publicidad',
    builder: (_) => _FormularioCampania(tipo: tipo, diario: diario),
  );
}

class _FormularioCampania extends ConsumerStatefulWidget {
  const _FormularioCampania({required this.tipo, this.diario});

  final TipoCampania tipo;

  /// El del plan que tocó, para arrancar con los números cargados.
  final int? diario;

  @override
  ConsumerState<_FormularioCampania> createState() => _FormularioCampaniaState();
}

class _FormularioCampaniaState extends ConsumerState<_FormularioCampania> {
  final _form = GlobalKey<FormState>();
  late final _presupuesto =
      TextEditingController(text: widget.diario == null ? '' : MilesFormatter.formatear(widget.diario! * 30));
  late final _porDia = TextEditingController(text: widget.diario == null ? '' : MilesFormatter.formatear(widget.diario!));

  bool get _esPublicidad => widget.tipo == TipoCampania.publicidad;

  @override
  void dispose() {
    _presupuesto.dispose();
    _porDia.dispose();
    super.dispose();
  }

  Future<void> _activar() async {
    if (!_form.currentState!.validate()) return;
    final comercioId = ref.read(sesionProvider).comercioId;
    if (comercioId == null) return;
    try {
      await ref.read(campaniasRepositoryProvider).crear(
            comercioId: comercioId,
            tipo: widget.tipo,
            presupuesto: MilesFormatter.leer(_presupuesto.text)!,
            presupuestoDiario: _esPublicidad ? MilesFormatter.leer(_porDia.text) : null,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dia = MilesFormatter.leer(_porDia.text) ?? 0;
    final tope = MilesFormatter.leer(_presupuesto.text) ?? 0;

    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _esPublicidad
                ? 'Tu local aparece destacado. Se te descuenta de tus ventas, hasta el tope que pongas.'
                : 'Los clientes con Plus no pagan envío en tu local: lo ponés vos. Se te descuenta de tus ventas y podés frenarlo cuando quieras.',
            style: MyType.bodyMd.copyWith(color: MyColors.secondary),
          ),
          const SizedBox(height: MySpacing.md),
          if (_esPublicidad)
            MyCampo(
              controller: _porDia,
              label: 'Cuánto por día, como máximo',
              hint: 'Ej: 9.000',
              icon: Symbols.today,
              miles: true,
              onChanged: (_) => setState(() {}),
              validar: (v) => (MilesFormatter.leer(v) ?? 0) <= 0 ? 'Escribí cuánto por día' : null,
            ),
          MyCampo(
            controller: _presupuesto,
            label: 'Tope total de la campaña',
            hint: 'Ej: 60.000',
            icon: Symbols.savings,
            miles: true,
            onChanged: (_) => setState(() {}),
            validar: (v) {
              final n = MilesFormatter.leer(v) ?? 0;
              if (n <= 0) return 'Escribí el tope';
              if (_esPublicidad && dia > n) return 'Es menos de lo que gastás en un día';
              return null;
            },
          ),
          // La cuenta que el local hacía de cabeza: cuánto le dura la plata.
          if (_esPublicidad && dia > 0 && tope >= dia) ...[
            Text(
              'Te alcanza para ${tope ~/ dia} ${tope ~/ dia == 1 ? 'día' : 'días'} como mínimo, si cada día se gasta el máximo.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.md),
          ],
          MyBotonAccion(label: 'Activar', icon: Symbols.rocket_launch, onPressed: _activar),
        ],
      ),
    );
  }
}
