import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

import 'admin_shell.dart';
import 'comercios_page.dart';
import 'encoger.dart';
import 'envios_page.dart';
import 'preinscripciones.dart';
import 'repartidores_page.dart';

/// Resumen de la operación: indicadores, mapa en vivo, lo que requiere
/// atención y los envíos en la calle.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenAdminProvider);

    return MyPagina(
      rotulo: 'Malargüe · en vivo',
      titulo: 'Resumen',
      bajada: 'Cómo viene la operación ahora',
      onRefresh: () async => refrescarResumenAdmin(ref),
      children: [
        // Sin esto el panel mostraba ceros y "Todo en orden" cuando una
        // consulta fallaba: la administración creía que no pasaba nada.
        MyAsync(
          valor: resumen,
          onReintentar: () => refrescarResumenAdmin(ref),
          datos: (datos) => _Resumen(datos: datos),
        ),
      ],
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.datos});

  final ResumenAdmin datos;

  @override
  Widget build(BuildContext context) {
    final comercios = datos.comercios;
    final riders = datos.riders;
    final activos = datos.enviosActivos;
    final preinscriptos = datos.preinscripciones
        .where((p) => p.estado == EstadoPreinscripcion.pendiente)
        .toList();

    final operativos = comercios.where((c) => c.aprobacion.puedeOperar).toList();
    final abiertos = operativos.where((c) => c.abierto).length;
    final aprobados = riders.where((r) => r.aprobacion.puedeOperar).length;
    final conectados = riders.where((r) => r.conectado).toList();
    final enViaje = conectados.where((r) => r.ocupado).length;
    final libres = conectados.length - enViaje;
    final buscando = activos.where((e) => e.estado == EstadoEnvio.buscandoRepartidor).length;

    final kpis = MyGrilla(
      anchoMinimo: context.esMovil ? 150 : 230,
      maxColumnas: 3,
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
      ],
    );

    final mapa = _TarjetaMapa(riders: conectados, envios: activos);
    final atencion = _RequiereAtencion(
      buscandoSinLibres: libres == 0 ? buscando : 0,
      sinUbicacion: comercios.where((c) => c.aprobacion.puedeOperar && !c.direccion.tieneCoordenadas).toList(),
      localesPendientes: comercios.where((c) => c.aprobacion == EstadoAprobacion.pendiente).toList(),
      ridersPendientes: riders.where((r) => r.aprobacion == EstadoAprobacion.pendiente).toList(),
      localesWeb: preinscriptos.where((p) => p.tipo == TipoPreinscripcion.local).length,
      ridersWeb: preinscriptos.where((p) => p.tipo == TipoPreinscripcion.rider).length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Flexible(
                child: Text('Mapa en vivo', style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
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

/// Lo que espera una decisión. Cada aviso abre lo suyo **en el lugar** cuando
/// es una sola cosa (la ficha de ese local, de ese rider, las
/// pre-inscripciones): antes todos llevaban a otra sección y había que volver a
/// buscar de qué se hablaba. Cuando son varios, sí lleva a la lista.
class _RequiereAtencion extends StatelessWidget {
  const _RequiereAtencion({
    required this.buscandoSinLibres,
    required this.sinUbicacion,
    required this.localesPendientes,
    required this.ridersPendientes,
    required this.localesWeb,
    required this.ridersWeb,
  });

  final int buscandoSinLibres;
  final List<Comercio> sinUbicacion;
  final List<Comercio> localesPendientes;
  final List<Repartidor> ridersPendientes;

  /// Pre-inscripciones de la página web que nadie contactó todavía.
  final int localesWeb;
  final int ridersWeb;

  @override
  Widget build(BuildContext context) {
    void verPreinscripciones(TipoPreinscripcion tipo) => mostrarHojaLateral(
          context,
          titulo: 'Pre-inscripciones',
          builder: (_) => PreinscripcionesWeb(tipo: tipo),
        );

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
      for (final c in sinUbicacion)
        _Alerta(
          icono: Symbols.location_off,
          titulo: '${c.nombre} no tiene ubicación',
          detalle: 'Sin ubicación no puede pedir riders.',
          accion: 'Ver local',
          onTap: () => mostrarFichaLocal(context, c.id),
        ),
      if (localesPendientes.isNotEmpty)
        _Alerta(
          icono: Symbols.pending_actions,
          titulo: localesPendientes.length == 1
              ? '${localesPendientes.single.nombre} espera que lo apruebes'
              : '${localesPendientes.length} locales esperan que los apruebes',
          detalle: 'Mirá sus datos y decidí si puede vender.',
          accion: 'Revisar',
          onTap: () => localesPendientes.length == 1
              ? mostrarFichaLocal(context, localesPendientes.single.id)
              : context.go('/admin/locales'),
        ),
      if (ridersPendientes.isNotEmpty)
        _Alerta(
          icono: Symbols.pending_actions,
          titulo: ridersPendientes.length == 1
              ? '${ridersPendientes.single.nombre} espera que lo apruebes'
              : '${ridersPendientes.length} riders esperan que los apruebes',
          detalle: 'Mirá su documentación y decidí si puede repartir.',
          accion: 'Revisar',
          onTap: () => ridersPendientes.length == 1
              ? mostrarFichaRider(context, ridersPendientes.single.id)
              : context.go('/admin/riders'),
        ),
      if (localesWeb > 0)
        _Alerta(
          icono: Symbols.add_business,
          titulo: localesWeb == 1 ? 'Un local se anotó en la web' : '$localesWeb locales se anotaron en la web',
          detalle: 'Esperan que los contactes por WhatsApp.',
          accion: 'Ver',
          onTap: () => verPreinscripciones(TipoPreinscripcion.local),
        ),
      if (ridersWeb > 0)
        _Alerta(
          icono: Symbols.sports_motorsports,
          titulo: ridersWeb == 1 ? 'Un rider se anotó en la web' : '$ridersWeb riders se anotaron en la web',
          detalle: 'Esperan que los contactes por WhatsApp.',
          accion: 'Ver',
          onTap: () => verPreinscripciones(TipoPreinscripcion.rider),
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
    final boton = MyBoton(
      label: accion,
      onPressed: onTap,
      tipo: urgente ? MyBotonTipo.principal : MyBotonTipo.oscuro,
    );
    final caja = MyIconoCaja(
      icono,
      fondo: urgente ? MyColors.surfaceContainerLowest : MyColors.primary,
      color: urgente ? MyColors.error : MyColors.onPrimary,
    );
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: MyType.labelLg, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text(detalle, style: MyType.bodySm.copyWith(color: MyColors.secondary)),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(MySpacing.md),
      decoration: BoxDecoration(
        color: urgente ? MyColors.errorContainer.withValues(alpha: 0.55) : MyColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(MyRadius.lg),
      ),
      // Se decide por el ancho del aviso y no por el de la pantalla: en la
      // compu va en una columna angosta al lado del mapa, y con el botón al
      // costado al título le quedaban dos palabras por renglón.
      child: MyResponsivo(
        builder: (context, _, ancho) {
          if (ancho < 380) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    caja,
                    const SizedBox(width: MySpacing.sm),
                    Expanded(child: textos),
                  ],
                ),
                const SizedBox(height: MySpacing.sm),
                Align(alignment: Alignment.centerRight, child: boton),
              ],
            );
          }
          return Row(
            children: [
              caja,
              const SizedBox(width: MySpacing.sm),
              Expanded(child: textos),
              const SizedBox(width: MySpacing.xs),
              boton,
            ],
          );
        },
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

    // La tabla tiene siete columnas: en una tableta, con la barra lateral, a
    // cada una le tocan 80 px y no se lee nada. Hasta la compu van tarjetas,
    // de a dos cuando entran.
    if (!context.esEscritorio) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Envíos en curso', style: MyType.headlineMd),
          const SizedBox(height: MySpacing.sm),
          MyGrilla(
            anchoMinimo: 300,
            maxColumnas: 2,
            espacio: MySpacing.sm,
            children: [
              for (final e in envios)
                MyCard(
                  padding: const EdgeInsets.all(MySpacing.md),
                  onTap: () => mostrarFichaEnvio(context, e.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.codigo,
                              style: MyType.labelLg.copyWith(color: MyColors.tertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: MySpacing.xs),
                          Flexible(
                            flex: 3,
                            child: Encoger(child: MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: true)),
                          ),
                        ],
                      ),
                      const SizedBox(height: MySpacing.xs),
                      Text(e.nombreRetiro, style: MyType.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${e.destino.calle} · ${e.repartidorNombre ?? 'sin rider'}',
                        style: MyType.bodySm.copyWith(color: MyColors.secondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
        MyColumna('Estado', flex: 3, alDerecha: true),
      ],
      filas: [
        for (final e in envios)
          MyFila(
            onTap: () => mostrarFichaEnvio(context, e.id),
            celdas: [
              Text(e.codigo, style: MyType.labelLg.copyWith(color: MyColors.tertiary)),
              Text(Formato.hora(e.creadoEn), style: MyType.bodyMd),
              Text(e.nombreRetiro, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                e.repartidorNombre ?? 'Buscando…',
                style: MyType.bodyMd.copyWith(color: e.repartidorNombre == null ? MyColors.secondary : null),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(e.destino.calle, style: MyType.bodyMd, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(Formato.pesos(e.total), style: MyType.labelLg),
              Encoger(child: MyBadge(e.estado.label, tone: tonoEnvio(e.estado), dot: true)),
            ],
          ),
      ],
    );
  }
}
