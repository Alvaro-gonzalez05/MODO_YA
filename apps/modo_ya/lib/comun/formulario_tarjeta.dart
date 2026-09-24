import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Lo que cargó la persona para pagar: una tarjeta nueva o una guardada.
class DatosTarjeta {
  const DatosTarjeta({
    required this.marca,
    required this.cuotas,
    this.guardada,
    this.numero = '',
    this.titular = '',
    this.mes = 0,
    this.anio = 0,
    this.codigo = '',
    this.documento = '',
    this.guardar = true,
  });

  /// Si viene, se paga con esta (y solo hace falta el código).
  final TarjetaGuardada? guardada;

  final String numero;
  final String titular;
  final int mes;
  final int anio;
  final String codigo;
  final String documento;
  final bool guardar;
  final String marca;
  final int cuotas;
}

/// Formulario de tarjeta con la tarjeta dibujada arriba: se completa mientras
/// se escribe y se da vuelta al tocar el código de seguridad.
///
/// Lo usan la pantalla de pagar un pedido y la de MODO YA Plus. Los datos de la
/// tarjeta nunca salen de acá: los manda el repositorio directo a Mercado Pago.
class FormularioTarjeta extends ConsumerStatefulWidget {
  const FormularioTarjeta({
    super.key,
    required this.etiquetaBoton,
    required this.onPagar,
    this.cuotas = false,
    this.debajoDelTotal,
  });

  /// "Pagar $12.500", "Suscribirme".
  final String etiquetaBoton;

  /// Devuelve el mensaje de error, o null si salió bien.
  final Future<String?> Function(DatosTarjeta) onPagar;

  /// Mostrar el selector de cuotas (un pedido sí, la suscripción no).
  final bool cuotas;

  /// Para meter el resumen del total entre el formulario y el botón.
  final Widget? debajoDelTotal;

  @override
  ConsumerState<FormularioTarjeta> createState() => _FormularioTarjetaState();
}

class _FormularioTarjetaState extends ConsumerState<FormularioTarjeta> {
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
  var _procesando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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

  Future<void> _enviar() async {
    if (_guardada == null && !_form.currentState!.validate()) return;
    if (_guardada != null && _codigo.text.length < 3) {
      setState(() => _error = 'Escribí el código de seguridad de la tarjeta.');
      return;
    }
    setState(() {
      _procesando = true;
      _error = null;
    });
    final error = await widget.onPagar(
      _guardada != null
          ? DatosTarjeta(guardada: _guardada, codigo: _codigo.text, marca: _guardada!.marca, cuotas: _cuotas)
          : DatosTarjeta(
              numero: _numero.text,
              titular: _titular.text.trim(),
              mes: _vencimiento!.$1,
              anio: _vencimiento!.$2,
              codigo: _codigo.text,
              documento: _documento.text.trim(),
              guardar: _guardarTarjeta,
              marca: _marca.wire,
              cuotas: _cuotas,
            ),
    );
    if (!mounted) return;
    setState(() {
      _procesando = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tarjetas = ref.watch(tarjetasGuardadasProvider).value ?? const <TarjetaGuardada>[];

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
          Text('Tus tarjetas', style: MyType.labelLg),
          const SizedBox(height: MySpacing.xs),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xs,
            children: [
              for (final t in tarjetas)
                ChoiceChip(
                  selected: _guardada?.id == t.id,
                  onSelected: (_) => setState(() {
                    _guardada = t;
                    _codigo.clear();
                  }),
                  avatar: Icon(Symbols.credit_card, size: 18),
                  label: Text('${MyMarcaTarjeta.deWire(t.marca).etiqueta} ••••${t.ultimos4}'),
                ),
              ChoiceChip(
                selected: _guardada == null,
                onSelected: (_) => setState(() {
                  _guardada = null;
                  _codigo.clear();
                }),
                avatar: Icon(Symbols.add, size: 18),
                label: const Text('Otra tarjeta'),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
        ],
        if (_guardada == null) _formulario() else _soloCodigo(),
        if (widget.cuotas) ...[
          const SizedBox(height: MySpacing.xs),
          Row(
            children: [
              Expanded(child: Text('Cuotas', style: MyType.labelLg)),
              DropdownButton<int>(
                value: _cuotas,
                underline: const SizedBox.shrink(),
                items: [
                  for (final c in [1, 3, 6, 12])
                    DropdownMenuItem(value: c, child: Text(c == 1 ? '1 pago' : '$c cuotas', style: MyType.bodyMd)),
                ],
                onChanged: (v) => setState(() => _cuotas = v ?? 1),
              ),
            ],
          ),
        ],
        if (widget.debajoDelTotal != null) ...[
          const SizedBox(height: MySpacing.sm),
          widget.debajoDelTotal!,
        ],
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
          label: _procesando ? 'Procesando...' : widget.etiquetaBoton,
          icon: Symbols.lock,
          onPressed: _procesando ? null : _enviar,
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
                if (!_luhn(n)) return 'Ese número no existe: revisalo';
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

  Widget _soloCodigo() => Column(
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

  /// Algoritmo de Luhn: el último dígito de toda tarjeta es un verificador.
  /// Evita el viaje a Mercado Pago cuando hay un número mal tipeado.
  static bool _luhn(String n) {
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
