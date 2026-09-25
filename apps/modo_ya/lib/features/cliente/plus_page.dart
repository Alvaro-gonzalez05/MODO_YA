import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../comun/formulario_tarjeta.dart';

/// MODO YA Plus: el cliente paga una mensualidad y no paga envío en los
/// locales adheridos.
///
/// El envío lo pone el local desde su campaña (el rider cobra igual). Si el
/// local se queda sin fondo, el envío vuelve a cobrarse: por eso se dice
/// "en los locales adheridos" y cada local se marca en la lista.
class PlusPage extends ConsumerWidget {
  const PlusPage({super.key});

  Future<String?> _suscribir(BuildContext context, WidgetRef ref, DatosTarjeta d) async {
    try {
      final repo = ref.read(pagosRepositoryProvider);
      final r = d.guardada != null
          ? await repo.suscribirsePlusConTarjeta(d.guardada!, d.codigo)
          : await repo.suscribirsePlus(
              numero: d.numero,
              titular: d.titular,
              mes: d.mes,
              anio: d.anio,
              codigo: d.codigo,
              documento: d.documento,
              marca: d.marca,
            );

      if (!r.aprobado) return r.detalle ?? 'El pago fue rechazado.';
      if (!context.mounted) return null;

      MySonidos.tocar(MySonido.pedidoConfirmado);
      await mostrarExito(
        context,
        titulo: '¡Ya tenés MODO YA Plus!',
        mensaje: 'Durante 30 días no pagás envío en los locales adheridos.',
      );
      if (context.mounted) context.go('/cliente');
      return null;
    } catch (e) {
      return e is ErrorModoYa ? e.mensaje : 'No se pudo completar el pago.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plus = ref.watch(miPlusProvider);

    return MyPantallaClara(
      child: MyPagina(
        volver: () => context.go('/cliente'),
        rotulo: 'Beneficios',
        titulo: 'MODO YA Plus',
        conDock: false,
        anchoMaximo: 560,
        children: [
          MyAsync(
            valor: plus,
            onReintentar: () => ref.invalidate(miPlusProvider),
            datos: (estado) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Presentacion(estado: estado),
                const SizedBox(height: MySpacing.lg),
                if (estado.activo) ...[
                  MyCard(
                    child: MyEmptyState(
                      icon: Symbols.verified,
                      title: 'Ya sos Plus',
                      message: estado.hasta == null
                          ? 'Disfrutá los envíos gratis.'
                          : estado.renovar
                              ? 'Se renueva solo el ${Formato.fechaCorta(estado.hasta!)} '
                                  'con la tarjeta que dejaste guardada.'
                              : 'Lo tenés hasta el ${Formato.fechaCorta(estado.hasta!)}. '
                                  'Después no se te cobra más.',
                      action: MyBoton(
                        label: 'Ver locales',
                        icon: Symbols.storefront,
                        onPressed: () => context.go('/cliente'),
                      ),
                    ),
                  ),
                  const SizedBox(height: MySpacing.md),
                  _Renovacion(estado: estado),
                ] else
                  FormularioTarjeta(
                    etiquetaBoton: 'Suscribirme por ${Formato.pesos(estado.precio)}',
                    onPagar: (d) => _suscribir(context, ref, d),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El interruptor de la renovación automática.
///
/// Se muestra siempre que tenga Plus, no escondido en una pantalla de ajustes:
/// que se sepa que se va a volver a cobrar, y que cortarlo sea un toque, es
/// parte de no hacerle una trampa al cliente.
class _Renovacion extends ConsumerWidget {
  const _Renovacion({required this.estado});

  final EstadoPlus estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> cambiar(bool valor) async {
      try {
        await ref.read(pagosRepositoryProvider).renovarPlusAutomaticamente(valor);
        ref.invalidate(miPlusProvider);
        if (!context.mounted) return;
        mostrarAviso(
          context,
          valor ? 'Se va a renovar solo cuando se venza.' : 'No se te va a cobrar más.',
        );
      } catch (e) {
        if (context.mounted) mostrarError(context, e);
      }
    }

    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Symbols.autorenew, color: MyColors.tertiary, fill: 1),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Renovación automática', style: MyType.labelLg),
                    Text(
                      estado.renovar
                          ? 'Se cobra ${Formato.pesos(estado.precio)} cada 30 días.'
                          : 'Cuando se venza, se corta.',
                      style: MyType.bodySm.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
              Switch(value: estado.renovar, onChanged: cambiar),
            ],
          ),
          // Si la tarjeta viene rebotando, se le avisa antes de que se quede
          // sin Plus de un dia para el otro.
          if (estado.seRindio) ...[
            const SizedBox(height: MySpacing.sm),
            Row(
              children: [
                Icon(Symbols.error, size: 18, color: MyColors.error),
                const SizedBox(width: MySpacing.xs),
                Expanded(
                  child: Text(
                    'No pudimos cobrarte: ${estado.ultimoError ?? 'la tarjeta fue rechazada'} '
                    'Cargá otra tarjeta cuando se venza.',
                    style: MyType.bodySm.copyWith(color: MyColors.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Presentacion extends StatelessWidget {
  const _Presentacion({required this.estado});

  final EstadoPlus estado;

  @override
  Widget build(BuildContext context) {
    return MyCard(
      color: MyColors.dock,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.local_shipping, color: MyColors.primary, size: 30, fill: 1),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Text(
                  'Envío gratis, todas las veces que pidas',
                  style: MyType.headlineSm.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.sm),
          for (final t in const [
            'No pagás envío en los locales adheridos, sin mínimo de compra.',
            'Se renueva cada 30 días y lo cortás cuando quieras.',
            'Los locales adheridos están marcados con "Envío gratis".',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Symbols.check_circle, size: 18, color: MyColors.primary, fill: 1),
                  const SizedBox(width: MySpacing.xs),
                  Expanded(child: Text(t, style: MyType.bodyMd.copyWith(color: Colors.white70))),
                ],
              ),
            ),
          const SizedBox(height: MySpacing.sm),
          Text(
            '${Formato.pesos(estado.precio)} por mes',
            style: MyType.headlineLg.copyWith(color: MyColors.primary),
          ),
        ],
      ),
    );
  }
}
