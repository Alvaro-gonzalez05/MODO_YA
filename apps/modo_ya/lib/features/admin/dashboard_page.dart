import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';

/// Resumen de la operación: indicadores, mapa en vivo, lo que requiere
/// atención y los envíos en la calle.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comercios = ref.watch(todosLosComerciosProvider).value ?? const <Comercio>[];
    final riders = ref.watch(todosLosRepartidoresProvider).value ?? const <Repartidor>[];
    final activos = ref.watch(enviosActivosProvider).value ?? const <Envio>[];
    final porCobrar = ref.watch(pedidosPendientesDePagoProvider).value ?? const <Pedido>[];

    final operativos = comercios.where((c) => c.aprobacion.puedeOperar).toList();
    final abiertos = operativos.where((c) => c.abierto).length;
    final aprobados = riders.where((r) => r.aprobacion.puedeOperar).length;
    final conectados = riders.where((r) => r.conectado).toList();
    final enViaje = conectados.where((r) => r.ocupado).length;
    final libres = conectados.length - enViaje;
    final buscando = activos.where((e) => e.estado == EstadoEnvio.buscandoRepartidor).length;

    final kpis = MyGrilla(
      anchoMinimo: context.esMovil ? 150 : 230,
      children: [
        MyKpi(
          rotulo: 'Envíos en la calle',
          valor: '${activos.length}',
          icono: Symbols.route,
          detalle: buscando == 0 ? 'Todos con rider' : '$buscando buscando rider',
        ),
        MyKpi(
          rotulo: 'Locales abiertos',
          valor: '$abiertos',
          icono: Symbols.storefront,
          pastilla: 'de ${operativos.length}',
          detalle: '${comercios.length} locales en total',
          progreso: operativos.isEmpty ? 0 : abiertos / operativos.length,
        ),
        MyKpi(
          rotulo: 'Riders conectados',
          valor: '${conectados.length}',
          icono: Symbols.sports_motorsports,
          pastilla: 'de $aprobados',
          detalle: '$enViaje en viaje · $libres libres',
          progreso: aprobados == 0 ? 0 : conectados.length / aprobados,
        ),
        MyKpi(
          rotulo: 'Pedidos por cobrar',
          valor: '${porCobrar.length}',
          icono: Symbols.payments,
          detalle: porCobrar.isEmpty ? 'Nada pendiente' : 'Tocá para registrar lo cobrado',
          destacado: porCobrar.isNotEmpty,
          onTap: () => context.go('/admin/pedidos'),
        ),
      ],
    );

    final mapa = _TarjetaMapa(riders: conectados, envios: activos);
    final atencion = _RequiereAtencion(
      porCobrar: porCobrar.length,
      buscandoSinLibres: libres == 0 ? buscando : 0,
      sinUbicacion: comercios.where((c) => c.aprobacion.puedeOperar && !c.direccion.tieneCoordenadas).toList(),
      pendientes: comercios.where((c) => c.aprobacion == EstadoAprobacion.pendiente).length +
          riders.where((r) => r.aprobacion == EstadoAprobacion.pendiente).length,
    );

    return MyPagina(
      rotulo: 'Malargüe · en vivo',
      titulo: 'Resumen',
      bajada: 'Cómo viene la operación ahora',
      onRefresh: () async {
        ref.invalidate(todosLosComerciosProvider);
        ref.invalidate(todosLosRepartidoresProvider);
      },
      children: [
        kpis,
        const SizedBox(height: MySpacing.lg),
        if (context.esEscritorio)
          // Sin IntrinsicHeight: el mapa usa LayoutBuilder, que no calcula
          // alturas intrinsecas.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: mapa),
              const SizedBox(width: MySpacing.lg),
              Expanded(flex: 2, child: atencion),
            ],
          )
        else ...[
          atencion,
          const SizedBox(height: MySpacing.lg),
          mapa,
        ],
        const SizedBox(height: MySpacing.lg),
        _EnviosEnCurso(envios: activos),
      ],
    );
  }
}

class _TarjetaMapa extends StatelessWidget {
  const _TarjetaMapa({required this.riders, required this.envios});

  final List<Repartidor> riders;
  final List<Envio> envios;

  @override
  Widget build(BuildContext context) {
    final marcadores = <MyMarcador>[
      for (final r in riders)
        if (r.ubicacion?.tieneCoordenadas ?? false)
          MyMarcador(
            punto: LatLng(r.ubicacion!.lat!, r.ubicacion!.lng!),
            icono: Symbols.sports_motorsports,
            color: r.ocupado ? MyColors.primary : MyColors.success,
            etiqueta: r.nombre.split(' ').first,
          ),
      for (final e in envios)
        if (e.destino.tieneCoordenadas)
          MyMarcador(punto: LatLng(e.destino.lat!, e.destino.lng!), icono: Symbols.home, color: MyColors.dock),
    ];

    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Mapa en vivo', style: MyType.headlineSm),
              const SizedBox(width: MySpacing.xs),
              const MyBadge('En vivo', tone: MyBadgeTone.ember, dot: true),
            ],
          ),
          const SizedBox(height: MySpacing.xs),
          Wrap(
            spacing: MySpacing.md,
            runSpacing: MySpacing.xxs,
            children: [
              _Referencia(color: MyColors.success, texto: 'Rider libre'),
              _Referencia(color: MyColors.primary, texto: 'Rider en servicio'),
              _Referencia(color: MyColors.dock, texto: 'Destino de un envío'),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          MyMapaVista(
            alto: context.esMovil ? 260 : 380,
            radio: MyRadius.lg,
            interactivo: true,
            marcadores: marcadores,
          ),
        ],
      ),
    );
  }
}

class _Referencia extends StatelessWidget {
  const _Referencia({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: MySpacing.xxs),
        Text(texto, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
      ],
    );
  }
}

class _RequiereAtencion extends StatelessWidget {
  const _RequiereAtencion({
    required this.porCobrar,
    required this.buscandoSinLibres,
    required this.sinUbicacion,
    required this.pendientes,
  });

  final int porCobrar;
  final int buscandoSinLibres;
  final List<Comercio> sinUbicacion;
  final int pendientes;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (buscandoSinLibres > 0)
        _Alerta(
          urgente: true,
          icono: Symbols.warning,
          titulo: buscandoSinLibres == 1
              ? 'Un envío busca rider y no hay libres'
              : '$buscandoSinLibres envíos buscan rider y no hay libres',
          detalle: 'Conviene avisarle a algún rider que se conecte.',
          accion: 'Ver envíos',
          onTap: () => context.go('/admin/envios'),
        ),
      if (porCobrar > 0)
        _Alerta(
          icono: Symbols.payments,
          titulo: porCobrar == 1 ? 'Un pedido sin cobrar' : '$porCobrar pedidos sin cobrar',
          detalle: 'Ya los recibió el local: falta registrar la plata.',
          accion: 'Revisar',
          onTap: () => context.go('/admin/pedidos'),
        ),
      for (final c in sinUbicacion)
        _Alerta(
          icono: Symbols.location_off,
          titulo: '${c.nombre} no tiene ubicación',
          detalle: 'Sin ubicación no puede pedir riders.',
          accion: 'Ver local',
          onTap: () => context.go('/admin/locales'),
        ),
      if (pendientes > 0)
        _Alerta(
          icono: Symbols.pending_actions,
          titulo: pendientes == 1 ? 'Una cuenta en revisión' : '$pendientes cuentas en revisión',
          detalle: 'Esperan que las apruebes.',
          accion: 'Revisar',
          onTap: () => context.go('/admin/locales'),
        ),
    ];

    return MyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Symbols.notifications_active, color: MyColors.primary, size: 22),
              const SizedBox(width: MySpacing.xs),
              Expanded(child: Text('Requiere tu atención', style: MyType.headlineSm)),
              if (items.isNotEmpty) MyBadge('${items.length} pendientes', tone: MyBadgeTone.danger),
            ],
          ),
          const SizedBox(height: MySpacing.md),
          if (items.isEmpty)
            Container(
              padding: const EdgeInsets.all(MySpacing.lg),
              decoration: BoxDecoration(
                color: MyColors.successContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(MyRadius.lg),
              ),
              child: Row(
                children: [
                  Icon(Symbols.task_alt, color: MyColors.success),
                  const SizedBox(width: MySpacing.sm),
                  Expanded(
                    child: Text(
                      'Todo en orden. Si pasa algo que necesite tu intervención, aparece acá.',
                      style: MyType.bodyMd.copyWith(color: MyColors.success),
                    ),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: MySpacing.sm),
              items[i],
            ],
        ],
      ),
    );
  }
}

class _Alerta extends StatelessWidget {
  const _Alerta({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.accion,
    required this.onTap,
    this.urgente = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final String accion;
  final VoidCallback onTap;
  final bool urgente;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MySpacing.md),
      decoration: BoxDecoration(
        color: urgente ? MyColors.errorContainer.withValues(alpha: 0.55) : MyColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MyRadius.lg),
      ),
      child: Row(
        children: [
          MyIconoCaja(
            icono,
            fondo: urgente ? MyColors.surfaceContainerLowest : MyColors.primary,
            color: urgente ? MyColors.error : MyColors.onPrimary,
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: MyType.labelLg),
                Text(detalle, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.xs),
          MyBoton(
            label: accion,
            onPressed: onTap,
            tipo: urgente ? MyBotonTipo.principal : MyBotonTipo.oscuro,
          ),
        ],
      ),
    );
  }
}

class _EnviosEnCurso extends StatelessWidget {
  const _EnviosEnCurso({required this.envios});

  final List<Envio> envios;

  @override
  Widget build(BuildContext context) {
    if (envios.isEmpty) {
      return const MyCard(
        child: MyEmptyState(
          icon: Symbols.route,
          title: 'No hay envíos en la calle',
          message: 'Cuando un local pida un rider o acepte un pedido, aparece acá en vivo.',
        ),
      );
    }

    if (context.esMovil) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Envíos en curso', style: MyType.headlineMd),
          const SizedBox(height: MySpacing.sm),
          for (final e in envios) ...[
            MyCard(
              padding: const EdgeInsets.all(MySpacing.md),
              onTap: () => context.go('/admin/envios'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(e.codigo, style: MyType.labelLg.copyWith(color: MyColors.tertiary)),
                      const Spacer(),
                      MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: true),
                    ],
                  ),
                  const SizedBox(height: MySpacing.xs),
                  Text(e.comercioNombre, style: MyType.headlineSm),
                  Text(
                    '${e.destino.calle} · ${e.repartidorNombre ?? 'sin rider'}',
                    style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MySpacing.sm),
          ],
        ],
      );
    }

    return MyTabla(
      titulo: 'Envíos en curso',
      acciones: [const MyBadge('En vivo', tone: MyBadgeTone.ember, dot: true)],
      columnas: const [
        MyColumna('Envío'),
        MyColumna('Hora'),
        MyColumna('Local', flex: 2),
        MyColumna('Rider', flex: 2),
        MyColumna('Destino', flex: 2),
        MyColumna('Total', alDerecha: true),
        MyColumna('Estado', flex: 2, alDerecha: true),
      ],
      filas: [
        for (final e in envios)
          MyFila(
            onTap: () => context.go('/admin/envios'),
            celdas: [
              Text(e.codigo, style: MyType.labelLg.copyWith(color: MyColors.tertiary)),
              Text(Formato.hora(e.creadoEn), style: MyType.bodyMd),
              Text(e.comercioNombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                e.repartidorNombre ?? 'Buscando…',
                style: MyType.bodyMd.copyWith(color: e.repartidorNombre == null ? MyColors.secondary : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(e.destino.calle, style: MyType.bodyMd, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(Formato.pesos(e.total), style: MyType.labelLg),
              MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: true),
            ],
          ),
      ],
    );
  }
}
