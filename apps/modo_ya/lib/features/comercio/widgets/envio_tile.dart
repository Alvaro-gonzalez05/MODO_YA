import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import '../../../comun/estados_ui.dart';

/// Fila de un envío en los listados del local.
class EnvioTile extends StatelessWidget {
  const EnvioTile({super.key, required this.envio, this.onTap});

  final Envio envio;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final activo = envio.estado.esActivo;

    return MyCard(
      onTap: onTap,
      padding: const EdgeInsets.all(MySpacing.md),
      child: Row(
        children: [
          MyIconoCaja(
            iconoEnvio(envio.estado),
            tamano: 46,
            fondo: activo ? MyColors.primaryFixed : MyColors.secondaryContainer,
            color: activo ? MyColors.primary : MyColors.onSecondaryFixedVariant,
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${envio.codigo} · ${Formato.hora(envio.creadoEn)}${envio.pedidoId != null ? ' · pedido de la app' : ''}',
                  style: MyType.labelSm.copyWith(color: MyColors.secondary),
                ),
                const SizedBox(height: 2),
                Text(envio.destino.calle, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: MySpacing.xxs),
                Wrap(
                  spacing: MySpacing.xs,
                  runSpacing: MySpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MyBadge(envio.estado.label, tone: tonoEnvio(envio.estado), dot: activo),
                    Text(Formato.pesos(envio.total), style: MyType.labelLg),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.xs),
          Icon(activo ? Symbols.near_me : Symbols.chevron_right, color: MyColors.primary, size: 22),
        ],
      ),
    );
  }
}
