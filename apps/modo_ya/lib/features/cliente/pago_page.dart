import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Pago del pedido con tarjeta, dentro de la app.
///
/// Los datos de la tarjeta viajan directo a Mercado Pago, que devuelve un token
/// de un solo uso; el número nunca pasa por nuestro servidor (ver
/// `packages/my_core/lib/src/repositories/pagos_repository.dart`).
///
/// El pedido ya está creado y esperando el pago: si la tarjeta rebota, el local
/// no llega a verlo.
class PagoPage extends ConsumerStatefulWidget {
  const PagoPage({super.key, required this.pedidoId});

  final String pedidoId;

  @override
  ConsumerState<PagoPage> createState() => _PagoPageState();
}

class _PagoPageState extends ConsumerState<PagoPage> {
  final _form = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _titular = TextEditingController();
  final _vence = TextEditingController();
  final _codigo = TextEditingController();
  final _documento = TextEditingController();
  final _focoCodigo = FocusNode();

  TarjetaGuardada? _guardada;
  var _guardarTarjeta = true;
  var _cuotas = 1;
  var _pagando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Al tocar el código de seguridad la tarjeta se da vuelta.
    _focoCodigo.addListener(() => setState(() {}));
    for (final c in [_numero, _titular, _vence, _codigo]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_numero, _titular, _vence, _codigo, _documento]) {
      c.dispose();
    }
    _focoCodigo.dispose();
    super.dispose();
  }

  MyMarcaTarjeta get _marca => _guardada != null
      ? MyMarcaTarjeta.deWire(_guardada!.marca)
      : MyMarcaTarjeta.deNumero(_numero.text);

  (int, int)? get _vencimiento {
    final t = _vence.text.replaceAll(RegExp(r'\D'), '');
    if (t.length < 4) return null;
    final mes = int.tryParse(t.substring(0, 2));
    final anio = int.tryParse(t.substring(2, 4));
    if (mes == null || anio == null || mes < 1 || mes > 12) return null;
    return (mes, 2000 + anio);
  }

  Future<void> _pagar(Pedido pedido) async {
    if (_guardada == null && !_form.currentState!.validate()) return;
    if (_guardada != null && _codigo.text.length < 3) {
      setState(() => _error = 'Escribí el código de seguridad de la tarjeta.');
      return;
    }
    setState(() {
      _pagando = true;
      _error = null;
    });
    try {
      final repo = ref.read(pagosRepositoryProvider);
      final r = _guardada != null
          ? await repo.pagarConTarjetaGuardada(
              pedidoId: pedido.id,
              tarjeta: _guardada!,
              codigo: _codigo.text,
              cuotas: _cuotas,
            )
          : await repo.pagarConTarjetaNueva(
              pedidoId: pedido.id,
              numero: _numero.text,
              titular: _titular.text.trim(),
              mes: _vencimiento!.$1,
              anio: _vencimiento!.$2,
              codigo: _codigo.text,
              documento: _documento.text.trim(),
              cuotas: _cuotas,
              guardar: _guardarTarjeta,
              marca: _marca.wire,
            );

      if (!mounted) return;
      if (!r.aprobado) {
        setState(() {
          _pagando = false;
          _error = r.detalle ?? 'El pago fue rechazado.';
        });
        return;
      }
      MySonidos.tocar(MySonido.pedidoConfirmado);
      await mostrarExito(
        context,
        titulo: '¡Pago aprobado!',
        mensaje: r.simulado
            ? 'Pago de prueba: todavía no están las credenciales de Mercado Pago.'
            : 'Ya le avisamos a ${pedido.comercioNombre}.',
      );
      if (mounted) context.go('/cliente/pedidos/${pedido.id}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _pagando = false;
          _error = e is ErrorModoYa ? e.mensaje : 'No se pudo completar el pago.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pedidoAsync = ref.watch(pedidoProvider(widget.pedidoId));
    final tarjetas = ref.watch(tarjetasGuardadasProvider).value ?? const <TarjetaGuardada>[];

    return MyPantallaClara(
      child: MyPagina(
        volver: () => context.go('/cliente'),
        rotulo: 'Pago seguro',
        titulo: 'Pagar con tarjeta',
        conDock: false,
        anchoMaximo: 560,
        children: [
          MyAsync(
            valor: pedidoAsync,
            onReintentar: () => ref.invalidate(pedidoProvider(widget.pedidoId)),
            datos: (pedido) {
              if (pedido == null) {
                return const MyCard(
                  child: MyEmptyState(icon: Symbols.error, title: 'No encontramos el pedido', message: ''),
                );
              }
              if (pedido.estado != EstadoPedido.pendientePago) {
                // Ya se pagó (o se canceló): no hay nada que cobrar.
                return MyCard(
                  child: MyEmptyState(
                    icon: pedido.estado == EstadoPedido.cancelado ? Symbols.cancel : Symbols.check_circle,
                    title: pedido.estado == EstadoPedido.cancelado ? 'El pedido se canceló' : 'Este pedido ya está pago',
                    message: 'Podés ver cómo viene en "Mis pedidos".',
                    action: MyBoton(
                      label: 'Ver el pedido',
                      onPressed: () => context.go('/cliente/pedidos/${pedido.id}'),
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MyTarjetaVisual(
                    numero: _numero.text,
                    ultimos4: _guardada?.ultimos4,
                    titular: _guardada?.titular ?? _titular.text,
                    vencimiento: _guardada?.vencimiento ?? _vence.text,
                    codigo: _codigo.text,
                    mostrarDorso: _focoCodigo.hasFocus,
                    marca: _guardada != null ? _marca : null,
                  ),
                  const SizedBox(height: MySpacing.lg),
                  if (tarjetas.isNotEmpty) ...[
                    _Guardadas(
                      tarjetas: tarjetas,
                      elegida: _guardada,
                      onElegir: (t) => setState(() {
                        _guardada = t;
                        _codigo.clear();
                      }),
                    ),
                    const SizedBox(height: MySpacing.md),
                  ],
                  if (_guardada == null) _formulario() else _codigoDeGuardada(),
                  const SizedBox(height: MySpacing.md),
                  _cuotasYTotal(pedido),
                  if (_error != null) ...[
                    const SizedBox(height: MySpacing.sm),
                    MyCard(
                      color: MyColors.errorContainer,
                      shadows: const [],
                      child: Row(
                        children: [
                          Icon(Symbols.error, color: MyColors.error),
                          const SizedBox(width: MySpacing.sm),
                          Expanded(child: Text(_error!, style: MyType.bodyMd.copyWith(color: MyColors.onErrorContainer))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: MySpacing.md),
                  MyBotonAccion(
                    label: _pagando ? 'Procesando...' : 'Pagar ${Formato.pesos(pedido.total)}',
                    icon: Symbols.lock,
                    onPressed: _pagando ? null : () => _pagar(pedido),
                  ),
                  const SizedBox(height: MySpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Symbols.lock, size: 14, color: MyColors.claroTextoSecundario),
                      const SizedBox(width: MySpacing.xxs),
                      Flexible(
                        child: Text(
                          'Los datos de tu tarjeta viajan cifrados y no se guardan en MODO YA.',
                          style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _formulario() => Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MyCampo(
              controller: _numero,
              label: 'Número de la tarjeta',
              icon: Symbols.credit_card,
              keyboard: TextInputType.number,
              formatos: [FilteringTextInputFormatter.digitsOnly, _EnGrupos(4, 16)],
              validar: (v) {
                final n = v.replaceAll(RegExp(r'\D'), '');
                if (n.length < 15) return 'Faltan números';
                if (!_lunt(n)) return 'Ese número no existe: revisalo';
                return null;
              },
            ),
            MyCampo(
              controller: _titular,
              label: 'Nombre como figura en la tarjeta',
              icon: Symbols.person,
              mayusculas: true,
              validar: (v) => v.trim().length < 5 ? 'Escribí el nombre completo' : null,
            ),
            Row(
              children: [
                Expanded(
                  child: MyCampo(
                    controller: _vence,
                    label: 'Vencimiento',
                    hint: 'MM/AA',
                    icon: Symbols.calendar_month,
                    keyboard: TextInputType.number,
                    formatos: [FilteringTextInputFormatter.digitsOnly, _Vencimiento()],
                    validar: (_) => _vencimiento == null ? 'MM/AA' : null,
                  ),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: MyCampo(
                    controller: _codigo,
                    label: 'Código',
                    hint: _marca == MyMarcaTarjeta.amex ? '4 dígitos' : '3 dígitos',
                    icon: Symbols.password,
                    foco: _focoCodigo,
                    keyboard: TextInputType.number,
                    formatos: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(_marca == MyMarcaTarjeta.amex ? 4 : 3),
                    ],
                    validar: (v) => v.length < 3 ? 'Falta' : null,
                  ),
                ),
              ],
            ),
            MyCampo(
              controller: _documento,
              label: 'DNI del titular',
              icon: Symbols.badge,
              keyboard: TextInputType.number,
              formatos: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              validar: (v) => v.length < 7 ? 'Escribí el DNI sin puntos' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _guardarTarjeta,
              onChanged: (v) => setState(() => _guardarTarjeta = v),
              title: Text('Guardar esta tarjeta', style: MyType.labelLg),
              subtitle: Text(
                'La próxima vez pagás con un toque. Guarda Mercado Pago, no MODO YA.',
                style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario),
              ),
            ),
          ],
        ),
      );

  Widget _codigoDeGuardada() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MyCampo(
            controller: _codigo,
            label: 'Código de seguridad',
            hint: 'El de atrás de la tarjeta',
            icon: Symbols.password,
            foco: _focoCodigo,
            keyboard: TextInputType.number,
            obligatorio: false,
            formatos: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _guardada = null;
              _codigo.clear();
            }),
            icon: Icon(Symbols.add_card, size: 18),
            label: const Text('Usar otra tarjeta'),
          ),
        ],
      );

  Widget _cuotasYTotal(Pedido pedido) => MyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Cuotas', style: MyType.labelLg)),
                DropdownButton<int>(
                  value: _cuotas,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in [1, 3, 6, 12])
                      DropdownMenuItem(
                        value: c,
                        child: Text(c == 1 ? '1 pago' : '$c cuotas', style: MyType.bodyMd),
                      ),
                  ],
                  onChanged: (v) => setState(() => _cuotas = v ?? 1),
                ),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Total', style: MyType.headlineSm)),
                Text(Formato.pesos(pedido.total), style: MyType.headlineMd.copyWith(color: MyColors.tertiary)),
              ],
            ),
            if (_cuotas > 1)
              Text(
                '$_cuotas cuotas de ${Formato.pesos((pedido.total / _cuotas).round())} (el interés lo pone tu banco)',
                style: MyType.bodySm.copyWith(color: MyColors.claroTextoSecundario),
              ),
          ],
        ),
      );

  /// Algoritmo de Luhn: el último dígito de toda tarjeta es un verificador.
  /// Evita el viaje a Mercado Pago cuando hay un número mal tipeado.
  static bool _lunt(String n) {
    var suma = 0;
    var doble = false;
    for (var i = n.length - 1; i >= 0; i--) {
      var d = int.parse(n[i]);
      if (doble && (d *= 2) > 9) d -= 9;
      suma += d;
      doble = !doble;
    }
    return suma % 10 == 0;
  }
}

class _Guardadas extends StatelessWidget {
  const _Guardadas({required this.tarjetas, required this.elegida, required this.onElegir});

  final List<TarjetaGuardada> tarjetas;
  final TarjetaGuardada? elegida;
  final ValueChanged<TarjetaGuardada?> onElegir;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tus tarjetas', style: MyType.labelLg),
        const SizedBox(height: MySpacing.xs),
        Wrap(
          spacing: MySpacing.xs,
          runSpacing: MySpacing.xs,
          children: [
            for (final t in tarjetas)
              ChoiceChip(
                selected: elegida?.id == t.id,
                onSelected: (_) => onElegir(t),
                avatar: Icon(Symbols.credit_card, size: 18),
                label: Text('${MyMarcaTarjeta.deWire(t.marca).etiqueta} ••••${t.ultimos4}'),
              ),
            ChoiceChip(
              selected: elegida == null,
              onSelected: (_) => onElegir(null),
              avatar: Icon(Symbols.add, size: 18),
              label: const Text('Otra tarjeta'),
            ),
          ],
        ),
      ],
    );
  }
}

/// "4509953566233704" -> "4509 9535 6623 3704".
class _EnGrupos extends TextInputFormatter {
  _EnGrupos(this.cada, this.maximo);

  final int cada;
  final int maximo;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue nuevo) {
    final d = nuevo.text.replaceAll(RegExp(r'\D'), '');
    final corto = d.length > maximo ? d.substring(0, maximo) : d;
    final buffer = StringBuffer();
    for (var i = 0; i < corto.length; i++) {
      if (i > 0 && i % cada == 0) buffer.write(' ');
      buffer.write(corto[i]);
    }
    final texto = buffer.toString();
    return TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
  }
}

/// "1228" -> "12/28".
class _Vencimiento extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue nuevo) {
    var d = nuevo.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 4) d = d.substring(0, 4);
    final texto = d.length <= 2 ? d : '${d.substring(0, 2)}/${d.substring(2)}';
    return TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
  }
}
