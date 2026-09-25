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
        mensaje: 'No pagás envío en los locales adheridos. Se renueva sola todos '
            'los meses, el mismo día, y te podés dar de baja cuando quieras.',
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
                  _Suscripcion(estado: estado),
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

/// La suscripción en curso: cuándo se le vuelve a cobrar y cómo darse de baja.
///
/// No hay ningún interruptor que prender: se suscribió y se renueva sola. Lo
/// único que tiene que encontrar rápido es la baja, y por eso está acá y no
/// escondida en una pantalla de ajustes.
class _Suscripcion extends ConsumerWidget {
  const _Suscripcion({required this.estado});

  final EstadoPlus estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> cambiar(bool renovar) async {
      if (!renovar) {
        final ok = await confirmar(
          context,
          titulo: 'Darte de baja de MODO YA Plus',
          mensaje: estado.hasta == null
              ? 'No se te va a cobrar más.'
              : 'Seguís con envío gratis hasta el ${Formato.fechaLarga(estado.hasta!)}. '
                  'Después no se te cobra más.',
          aceptar: 'Darme de baja',
          peligroso: true,
        );
        if (!ok) return;
      }
      try {
        await ref.read(pagosRepositoryProvider).renovarPlusAutomaticamente(renovar);
        ref.invalidate(miPlusProvider);
        if (!context.mounted) return;
        mostrarAviso(
          context,
          renovar ? 'Listo, se vuelve a renovar sola.' : 'Listo, no se te cobra más.',
        );
      } catch (e) {
        if (context.mounted) mostrarError(context, e);
      }
    }

    final dia = estado.desde?.day ?? estado.hasta?.day;

    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MyIconoCaja(
                estado.renovar ? Symbols.verified : Symbols.event_busy,
                tamano: 48,
                circular: true,
              ),
              const SizedBox(width: MySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(estado.renovar ? 'Ya sos Plus' : 'Te diste de baja', style: MyType.headlineSm),
                    Text(
                      estado.renovar
                          ? (estado.hasta == null
                              ? 'Disfrutá los envíos gratis.'
                              : 'Se renueva sola el ${Formato.fechaLarga(estado.hasta!)}'
                                  '${dia == null ? '' : ', y así todos los $dia de cada mes'}.')
                          : estado.hasta == null
                              ? 'No se te va a cobrar más.'
                              : 'Tenés envío gratis hasta el ${Formato.fechaLarga(estado.hasta!)}. '
                                  'Después no se te cobra más.',
                      style: MyType.bodyMd.copyWith(color: MyColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          if (estado.renovar)
            MyStatRow(
              tiles: [
                MyStatTile(
                  label: 'Por mes',
                  value: Formato.pesos(estado.precio),
                  icon: Symbols.payments,
                ),
                if (estado.desde != null)
                  MyStatTile(
                    label: 'Sos Plus desde',
                    value: Formato.fechaCorta(estado.desde!),
                    icon: Symbols.calendar_month,
                  ),
              ],
            ),
          // La tarjeta viene rebotando: se le avisa antes de que se quede sin
          // Plus de un día para el otro.
          if (estado.seRindio) ...[
            const SizedBox(height: MySpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: MySpacing.md),
          // En el celular no entran los dos al lado: "Darme de baja" queda
          // cortado y una baja a medias leer no se puede.
          if (context.esMovil) ...[
            MyBoton(
              label: 'Ver locales',
              icon: Symbols.storefront,
              tipo: MyBotonTipo.secundario,
              onPressed: () => context.go('/cliente'),
            ),
            const SizedBox(height: MySpacing.xs),
            MyBoton(
              label: estado.renovar ? 'Darme de baja' : 'Volver a activarla',
              icon: estado.renovar ? Symbols.cancel : Symbols.autorenew,
              tipo: estado.renovar ? MyBotonTipo.texto : MyBotonTipo.principal,
              onPressed: () => cambiar(!estado.renovar),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: MyBoton(
                    label: 'Ver locales',
                    icon: Symbols.storefront,
                    tipo: MyBotonTipo.secundario,
                    onPressed: () => context.go('/cliente'),
                  ),
                ),
                const SizedBox(width: MySpacing.sm),
                Expanded(
                  child: MyBoton(
                    label: estado.renovar ? 'Darme de baja' : 'Volver a activarla',
                    icon: estado.renovar ? Symbols.cancel : Symbols.autorenew,
                    tipo: estado.renovar ? MyBotonTipo.texto : MyBotonTipo.principal,
                    onPressed: () => cambiar(!estado.renovar),
                  ),
                ),
              ],
            ),
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
            'Se renueva sola todos los meses, el mismo día que te suscribís.',
            'Te podés dar de baja cuando quieras, desde esta misma pantalla.',
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
