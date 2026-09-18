import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Carteles del inicio del cliente (el banner negro "El mejor sabor, en tu
/// casa"). La administración los escribe acá y se guardan solos mientras
/// escribe; el celular de cada cliente los actualiza en vivo.
class AdminCartelesPage extends ConsumerWidget {
  const AdminCartelesPage({super.key});

  Future<void> _agregar(BuildContext context, WidgetRef ref, int orden) async {
    try {
      await ref.read(cartelesRepositoryProvider).crear(orden: orden);
      ref.invalidate(cartelesProvider);
    } catch (e) {
      if (context.mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carteles = ref.watch(cartelesProvider);

    return MyPagina(
      rotulo: 'Inicio del cliente',
      titulo: 'Carteles',
      bajada: 'Lo que ve el cliente arriba de todo al abrir la app. Se guarda solo mientras escribís.',
      anchoMaximo: 900,
      acciones: [
        MyBoton(
          label: 'Agregar cartel',
          icon: Symbols.add,
          onPressed: () => _agregar(context, ref, carteles.value?.length ?? 0),
        ),
      ],
      onRefresh: () async => ref.invalidate(cartelesProvider),
      children: [
        MyAsync(
          valor: carteles,
          onReintentar: () => ref.invalidate(cartelesProvider),
          datos: (lista) {
            if (lista.isEmpty) {
              return MyCard(
                child: MyEmptyState(
                  icon: Symbols.campaign,
                  title: 'Sin carteles',
                  message: 'El inicio del cliente muestra el cartel de siempre. Agregá uno para cambiarlo.',
                  action: MyBoton(label: 'Agregar cartel', icon: Symbols.add, onPressed: () => _agregar(context, ref, 0)),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, c) in lista.indexed) ...[
                  if (i > 0) const SizedBox(height: MySpacing.md),
                  _EditorCartel(
                    key: ValueKey(c.id),
                    cartel: c,
                    numero: i + 1,
                    total: lista.length,
                  ),
                ],
                const SizedBox(height: MySpacing.md),
                Text(
                  'Si hay más de un cartel encendido, el cliente los pasa deslizando. Un cartel apagado no se ve pero queda guardado.',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Un cartel: la vista previa tal cual la ve el cliente y, abajo, los campos.
/// Cada cambio se guarda 700 ms después de la última tecla.
class _EditorCartel extends ConsumerStatefulWidget {
  const _EditorCartel({super.key, required this.cartel, required this.numero, required this.total});

  final Cartel cartel;
  final int numero;
  final int total;

  @override
  ConsumerState<_EditorCartel> createState() => _EditorCartelState();
}

enum _Guardado { alDia, escribiendo, guardando, error }

class _EditorCartelState extends ConsumerState<_EditorCartel> {
  late final _titulo = TextEditingController(text: widget.cartel.titulo);
  late final _subtitulo = TextEditingController(text: widget.cartel.subtitulo);
  late var _activo = widget.cartel.activo;
  Timer? _espera;
  var _estado = _Guardado.alDia;

  CartelesRepository get _repo => ref.read(cartelesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _titulo.addListener(_programar);
    _subtitulo.addListener(_programar);
  }

  @override
  void dispose() {
    _espera?.cancel();
    _titulo.dispose();
    _subtitulo.dispose();
    super.dispose();
  }

  void _programar() {
    setState(() => _estado = _Guardado.escribiendo);
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 700), _guardarTexto);
  }

  Future<void> _guardarTexto() async {
    final titulo = _titulo.text.trim();
    if (titulo.isEmpty) {
      // El titulo es obligatorio en la base: se espera a que escriba algo.
      setState(() => _estado = _Guardado.escribiendo);
      return;
    }
    setState(() => _estado = _Guardado.guardando);
    try {
      await _repo.guardar(widget.cartel.id, titulo: titulo, subtitulo: _subtitulo.text.trim());
      if (mounted) setState(() => _estado = _Guardado.alDia);
    } catch (e) {
      if (mounted) {
        setState(() => _estado = _Guardado.error);
        mostrarError(context, e);
      }
    }
  }

  Future<void> _cambiarActivo(bool v) async {
    setState(() {
      _activo = v;
      _estado = _Guardado.guardando;
    });
    try {
      await _repo.guardar(widget.cartel.id, activo: v);
      if (mounted) setState(() => _estado = _Guardado.alDia);
    } catch (e) {
      if (mounted) {
        setState(() {
          _activo = !v;
          _estado = _Guardado.error;
        });
        mostrarError(context, e);
      }
    }
  }

  Future<void> _borrar() async {
    final ok = await confirmar(
      context,
      titulo: 'Borrar cartel',
      mensaje: 'Deja de verse en el inicio de todos los clientes. No se puede deshacer.',
      aceptar: 'Borrar',
      peligroso: true,
    );
    if (!ok) return;
    try {
      await _repo.borrar(widget.cartel.id);
      ref.invalidate(cartelesProvider);
    } catch (e) {
      if (mounted) mostrarError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.total == 1 ? 'Cartel' : 'Cartel ${widget.numero} de ${widget.total}',
                  style: MyType.headlineSm,
                ),
              ),
              _IndicadorGuardado(estado: _estado),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          // Vista previa: exactamente el bloque del home del cliente, con lo que
          // se esta escribiendo.
          Opacity(
            opacity: _activo ? 1 : 0.45,
            child: ListenableBuilder(
              listenable: Listenable.merge([_titulo, _subtitulo]),
              builder: (_, _) => _VistaPrevia(titulo: _titulo.text, subtitulo: _subtitulo.text),
            ),
          ),
          const SizedBox(height: MySpacing.lg),
          MyCampo(
            controller: _titulo,
            label: 'Título',
            hint: 'El mejor sabor, en tu casa',
            icon: Symbols.title,
            lineas: 2,
          ),
          MyCampo(
            controller: _subtitulo,
            label: 'Bajada (amarilla)',
            hint: 'Delivery rápido, simple y local',
            icon: Symbols.short_text,
            obligatorio: false,
          ),
          Row(
            children: [
              Switch(value: _activo, onChanged: _cambiarActivo),
              const SizedBox(width: MySpacing.xs),
              Expanded(
                child: Text(
                  _activo ? 'Se muestra en el inicio' : 'Apagado: no se muestra',
                  style: MyType.labelLg.copyWith(color: _activo ? MyColors.onSurface : MyColors.secondary),
                ),
              ),
              MyBoton(label: 'Borrar', icon: Symbols.delete, tipo: MyBotonTipo.peligro, onPressed: _borrar),
            ],
          ),
        ],
      ),
    );
  }
}

class _VistaPrevia extends StatelessWidget {
  const _VistaPrevia({required this.titulo, required this.subtitulo});

  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: MyHeroCard(
        padding: const EdgeInsets.fromLTRB(MySpacing.lg, MySpacing.md, MySpacing.md, MySpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo.trim().isEmpty ? 'Escribí un título…' : titulo,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: MyType.headlineMd.copyWith(
                      color: titulo.trim().isEmpty ? MyColors.outline : MyColors.inverseOnSurface,
                      height: 1.15,
                    ),
                  ),
                  if (subtitulo.trim().isNotEmpty) ...[
                    const SizedBox(height: MySpacing.xs),
                    Text(
                      subtitulo,
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
      ),
    );
  }
}

/// "Guardado ✓" / "Guardando…" / "Sin guardar", arriba a la derecha de la tarjeta.
class _IndicadorGuardado extends StatelessWidget {
  const _IndicadorGuardado({required this.estado});

  final _Guardado estado;

  @override
  Widget build(BuildContext context) {
    final (texto, tono, icono) = switch (estado) {
      _Guardado.alDia => ('Guardado', MyBadgeTone.success, Symbols.check),
      _Guardado.escribiendo => ('Escribiendo…', MyBadgeTone.info, Symbols.edit),
      _Guardado.guardando => ('Guardando…', MyBadgeTone.ember, Symbols.cloud_upload),
      _Guardado.error => ('No se guardó', MyBadgeTone.danger, Symbols.error),
    };
    return MyBadge(texto, tone: tono, icon: icono);
  }
}
