/// Dominio de MODO YA: modelos, sesion, acceso a Supabase y providers.
///
/// Lo comparten la app MODO YA (cliente, local y administracion) y la app
/// MODO YA Rider.
library;

export 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

export 'src/backend.dart';
export 'src/config/entorno.dart';
export 'src/formato.dart';
export 'src/models/estados.dart';
export 'src/models/marketplace.dart';
export 'src/models/models.dart';
export 'src/providers.dart';
export 'src/repositories/campanias_repository.dart';
export 'src/repositories/carteles_repository.dart';
export 'src/repositories/catalogo_repository.dart';
export 'src/repositories/comercios_repository.dart';
export 'src/repositories/cuentas_repository.dart';
export 'src/repositories/envios_repository.dart';
export 'src/repositories/liquidaciones_repository.dart';
export 'src/repositories/pagos_repository.dart';
export 'src/repositories/pedidos_repository.dart';
export 'src/repositories/repartidores_repository.dart';
export 'src/repositories/tarifas_repository.dart';
export 'src/sesion.dart';
