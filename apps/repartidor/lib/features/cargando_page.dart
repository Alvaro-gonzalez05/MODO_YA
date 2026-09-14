import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:my_core/my_core.dart';
import 'package:my_ui/my_ui.dart';

class CargandoPage extends ConsumerWidget {
  const CargandoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionActualProvider);
    return Scaffold(
      body: Center(
        child: sesion.hasError
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MyEmptyState(icon: Symbols.cloud_off, title: 'No pudimos conectarnos', message: '${sesion.error}'),
                  FilledButton(
                    onPressed: () => ref.invalidate(sesionActualProvider),
                    child: const Text('Reintentar'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
