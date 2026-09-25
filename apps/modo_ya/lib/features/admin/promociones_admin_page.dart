import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

/// Las promociones de todos los locales, para la administración.
///
/// Es solo para mirar: el descuento lo pone y lo saca cada local. Sirve para
/// saber quién está empujando y con cuánto, y para entender una liquidación
/// que vino más flaca de lo esperado.
class AdminPromocionesPage extends ConsumerStatefulWidget {
  const AdminPromocionesPage({super.key});

  @override
  ConsumerState<AdminPromocionesPage> createState() => _AdminPromocionesPageState();
}

enum _Filtro { vigentes, todas }

class _AdminPromocionesPageState extends ConsumerState<AdminPromocionesPage> {
  _Filtro _filtro = _Filtro.vigentes;

  @override
  Widget build(BuildContext context) {
    final promos = ref.watch(promocionesDeTodosProvider);

    return MyPagina(
      volver: () => context.go('/admin/locales'),
      rotulo: 'Locales',
      titulo: 'Promociones',
      bajada: 'Los descuentos que cada local puso en su menú. Los pone y los saca el local.',
      children: [
        MyAsync(
          valor: promos,
          onReintentar: () => ref.invalidate(promocionesDeTodosProvider),
          datos: (lista) {
            final visibles = _filtro == _Filtro.vigentes
                ? lista.where((p) => p.vigente).toList()
                : lista;

            final filtros = MyFiltros<_Filtro>(
              seleccionado: _filtro,
              onChanged: (f) => setState(() => _filtro = f),
              opciones: [
                (_Filtro.vigentes, 'Rigiendo hoy', lista.where((p) => p.vigente).length),
                (_Filtro.todas, 'Todas', lista.length),
              ],
            );

            if (visibles.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  filtros,
                  const SizedBox(height: MySpacing.md),
                  MyCard(
                    child: MyEmptyState(
                      icon: Symbols.sell,
                      title: _filtro == _Filtro.vigentes
                          ? 'Hoy no hay ninguna promoción activa'
                          : 'Todavía ningún local armó promociones',
                      message: 'Cada local las arma desde su panel, en Menú → Promos. '
                          'El descuento lo absorbe el local: no afecta la comisión del envío.',
                    ),
                  ),
                ],
              );
            }

            // Agrupadas por local: es la pregunta que se hace de verdad
            // ("¿qué está haciendo tal local?"), no una lista plana.
            final porLocal = <String, List<Promocion>>{};
            for (final p in visibles) {
              porLocal.putIfAbsent(p.comercioNombre, () => []).add(p);
            }
            final nombres = porLocal.keys.toList()..sort();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filtros,
                const SizedBox(height: MySpacing.lg),
                for (final nombre in nombres) ...[
                  MySectionHeader(
                    title: nombre.isEmpty ? 'Local dado de baja' : nombre,
                    subtitle: _resumen(porLocal[nombre]!),
                  ),
                  const SizedBox(height: MySpacing.sm),
                  for (final p in porLocal[nombre]!) ...[
                    _FilaPromocion(promocion: p),
                    const SizedBox(height: MySpacing.xs),
                  ],
                  const SizedBox(height: MySpacing.lg),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static String _resumen(List<Promocion> promos) {
    final vigentes = promos.where((p) => p.vigente).toList();
    if (vigentes.isEmpty) return 'Ninguna rigiendo hoy';
    final mayor = vigentes.map((p) => p.porcentaje).reduce((a, b) => a > b ? a : b);
    return vigentes.length == 1
        ? 'Hoy descuenta hasta $mayor%'
        : '${vigentes.length} promociones, hasta $mayor%';
  }
}

class _FilaPromocion extends StatelessWidget {
  const _FilaPromocion({required this.promocion});

  final Promocion promocion;

  @override
  Widget build(BuildContext context) {
    final p = promocion;
    return MyCard(
      padding: const EdgeInsets.all(MySpacing.sm),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.vigente ? MyColors.primary : MyColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(MyRadius.card),
              border: Border.all(color: p.vigente ? MyColors.primary : MyColors.outlineVariant),
            ),
            child: Text(
              '${p.porcentaje}%',
              style: MyType.labelLg.copyWith(
                color: p.vigente ? MyColors.onPrimary : MyColors.secondary,
              ),
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre, style: MyType.labelLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  '${p.detalle} · ${p.cuando}'
                  '${p.hasta == null ? '' : ' · hasta el ${Formato.fechaCorta(p.hasta!)}'}',
                  style: MyType.bodySm.copyWith(color: MyColors.secondary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: MySpacing.sm),
          MyBadge(
            p.vigente
                ? 'Rigiendo'
                : !p.activa
                    ? 'Pausada'
                    : 'No rige hoy',
            tone: p.vigente
                ? MyBadgeTone.success
                : !p.activa
                    ? MyBadgeTone.neutral
                    : MyBadgeTone.info,
            dot: true,
          ),
        ],
      ),
    );
  }
}
