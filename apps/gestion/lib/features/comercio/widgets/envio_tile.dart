import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Tono y texto de la pastilla segun el estado del envio.
({MyBadgeTone tone, bool dot}) _estilo(EstadoEnvio estado) => switch (estado) {
      EstadoEnvio.borrador ||
      EstadoEnvio.cotizado =>
        (tone: MyBadgeTone.info, dot: false),
      EstadoEnvio.buscandoRepartidor => (tone: MyBadgeTone.neutral, dot: true),
      EstadoEnvio.asignado ||
      EstadoEnvio.enLocal ||
      EstadoEnvio.retirado ||
      EstadoEnvio.enCamino =>
        (tone: MyBadgeTone.ember, dot: false),
      EstadoEnvio.entregado => (tone: MyBadgeTone.success, dot: false),
      EstadoEnvio.cancelado ||
      EstadoEnvio.sinRepartidor =>
        (tone: MyBadgeTone.danger, dot: false),
    };

IconData _icono(EstadoEnvio estado) => switch (estado) {
      EstadoEnvio.buscandoRepartidor => Symbols.package_2,
      EstadoEnvio.entregado => Symbols.check_circle,
      EstadoEnvio.cancelado || EstadoEnvio.sinRepartidor => Symbols.cancel,
      _ => Symbols.sports_motorsports,
    };

/// Fila de un envio en el listado del comercio.
class EnvioTile extends StatelessWidget {
  const EnvioTile({super.key, required this.envio, this.onTap});

  final Envio envio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final estilo = _estilo(envio.estado);

    return MyCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MyColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(MyRadius.md),
                ),
                child: Icon(
                  _icono(envio.estado),
                  size: 23,
                  color: MyColors.primary,
                ),
              ),
              const SizedBox(width: MySpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MyOverline('Pedido #${envio.codigo}'),
                    const SizedBox(height: 2),
                    Text(
                      envio.destino.calle,
                      style: MyType.headlineSm,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MySpacing.xs),
              MyBadge(
                envio.estado.label,
                tone: estilo.tone,
                dot: estilo.dot,
              ),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          Row(
            children: [
              Text(
                'Tarifa: ',
                style: MyType.labelMd.copyWith(color: MyColors.secondary),
              ),
              Text(Formato.pesos(envio.total), style: MyType.headlineSm),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MySpacing.md,
                  vertical: MySpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: MyColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(MyRadius.full),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      envio.estado.esActivo ? 'Rastrear' : 'Detalles',
                      style: MyType.labelLg
                          .copyWith(color: MyColors.onSecondaryFixedVariant),
                    ),
                    const SizedBox(width: MySpacing.xxs),
                    Icon(
                      envio.estado.esActivo
                          ? Symbols.near_me
                          : Symbols.chevron_right,
                      size: 17,
                      color: MyColors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
