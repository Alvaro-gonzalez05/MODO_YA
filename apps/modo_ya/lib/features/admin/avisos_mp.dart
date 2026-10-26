import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Los avisos que mandó Mercado Pago, tal como llegaron.
///
/// La tabla existe desde 0044 con el comentario "los mira la administración",
/// pero no había pantalla: lo que se guardaba no lo veía nadie. Esto es solo
/// mirar — el que actúa sobre el pago es el cron `procesar-avisos-mp` (0068), y
/// lo que hizo con cada aviso queda en la nota.
///
/// Va como panel sobre la pantalla de cobros y no como sección del menú: se
/// mira cuando un cobro no cerró y se quiere saber qué dijo Mercado Pago.
Future<void> mostrarAvisosDeMercadoPago(BuildContext context) =>
    mostrarHojaLateral(context, titulo: 'Avisos de Mercado Pago', builder: (_) => const _Avisos());

class _Avisos extends ConsumerWidget {
  const _Avisos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosMercadoPagoProvider);

    return MyAsync(
      valor: avisos,
      onReintentar: () => ref.invalidate(avisosMercadoPagoProvider),
      datos: (lista) {
        if (lista.isEmpty) {
          return const MyEmptyState(
            icon: Symbols.inbox,
            title: 'Todavía no llegó ningún aviso',
            message: 'Mercado Pago avisa acá cuando le pasa algo a un pago después del cobro: '
                'se aprobó uno que estaba en revisión, se devolvió, entró un contracargo.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Se guardan tal como llegan y se resuelven solos cada minuto. La nota dice '
              'qué se hizo con cada uno; el que no la tiene todavía no se procesó.',
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
            const SizedBox(height: MySpacing.md),
            for (final a in lista) ...[
              _Aviso(aviso: a),
              const SizedBox(height: MySpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _Aviso extends StatefulWidget {
  const _Aviso({required this.aviso});

  final AvisoMercadoPago aviso;

  @override
  State<_Aviso> createState() => _AvisoState();
}

class _AvisoState extends State<_Aviso> {
  var _abierto = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.aviso;

    return MyCard(
      padding: const EdgeInsets.all(MySpacing.md),
      onTap: () => setState(() => _abierto = !_abierto),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(a.accion ?? a.tipo ?? 'Aviso', style: MyType.labelLg),
              ),
              Text(
                Formato.fechaHora(a.recibidoEn),
                style: MyType.bodySm.copyWith(color: MyColors.secondary),
              ),
              const SizedBox(width: MySpacing.xxs),
              Icon(_abierto ? Symbols.expand_less : Symbols.expand_more, size: 20),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Wrap(
            spacing: MySpacing.xs,
            runSpacing: MySpacing.xxs,
            children: [
              if (a.estado != null) MyBadge(a.estado!, tone: MyBadgeTone.neutral),
              // La firma es lo que distingue un aviso de Mercado Pago de uno
              // que mandó cualquiera: si no está, no hay que creerle.
              switch (a.firmaValida) {
                true => const MyBadge('Firma verificada', tone: MyBadgeTone.success, icon: Symbols.verified),
                false => const MyBadge('Firma inválida', tone: MyBadgeTone.danger, icon: Symbols.warning),
                _ => const MyBadge('Sin clave para verificar', tone: MyBadgeTone.info),
              },
            ],
          ),
          if (a.recursoId != null) ...[
            const SizedBox(height: MySpacing.xs),
            SelectableText(
              a.recursoId!,
              style: MyType.bodySm.copyWith(color: MyColors.secondary),
            ),
          ],
          if (a.nota != null) ...[
            const SizedBox(height: MySpacing.xxs),
            Text(a.nota!, style: MyType.bodySm),
          ],
          if (_abierto) ...[
            const SizedBox(height: MySpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MySpacing.sm),
              decoration: BoxDecoration(
                color: MyColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(MyRadius.md),
              ),
              // JSON crudo: con ancho fijo se lee, con la tipografía de la app
              // no.
              child: SelectableText(
                a.cuerpoLegible,
                style: MyType.bodySm.copyWith(fontFamily: 'monospace', height: 1.4),
              ),
            ),
            const SizedBox(height: MySpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: MyBoton(
                label: 'Copiar',
                icon: Symbols.content_copy,
                tipo: MyBotonTipo.texto,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: a.cuerpoLegible));
                  if (context.mounted) mostrarAviso(context, 'Aviso copiado.');
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
