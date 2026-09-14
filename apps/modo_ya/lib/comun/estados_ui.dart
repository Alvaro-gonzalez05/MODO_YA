import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/widgets.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Tono de pastilla para un estado de aprobación.
MyBadgeTone tonoAprobacion(EstadoAprobacion e) => switch (e) {
      EstadoAprobacion.aprobado => MyBadgeTone.success,
      EstadoAprobacion.pendiente => MyBadgeTone.ember,
      _ => MyBadgeTone.danger,
    };

/// Tono de pastilla para el estado de un envío.
MyBadgeTone tonoEnvio(EstadoEnvio e) => switch (e) {
      EstadoEnvio.borrador || EstadoEnvio.cotizado => MyBadgeTone.info,
      EstadoEnvio.buscandoRepartidor => MyBadgeTone.neutral,
      EstadoEnvio.entregado => MyBadgeTone.success,
      EstadoEnvio.cancelado || EstadoEnvio.sinRepartidor => MyBadgeTone.danger,
      _ => MyBadgeTone.ember,
    };

IconData iconoEnvio(EstadoEnvio e) => switch (e) {
      EstadoEnvio.buscandoRepartidor => Symbols.search,
      EstadoEnvio.entregado => Symbols.check_circle,
      EstadoEnvio.cancelado || EstadoEnvio.sinRepartidor => Symbols.cancel,
      _ => Symbols.sports_motorsports,
    };

/// Tono de pastilla para el estado de un pedido.
MyBadgeTone tonoPedido(EstadoPedido e) => switch (e) {
      EstadoPedido.pagado => MyBadgeTone.ember,
      EstadoPedido.entregado => MyBadgeTone.success,
      EstadoPedido.rechazado || EstadoPedido.cancelado => MyBadgeTone.danger,
      EstadoPedido.pendientePago || EstadoPedido.carrito => MyBadgeTone.neutral,
      _ => MyBadgeTone.info,
    };
