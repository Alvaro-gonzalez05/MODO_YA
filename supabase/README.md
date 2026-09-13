# Base de datos

Proyecto Supabase: `wqahdncdqnzrusrmdyui` · región `sa-east-1` (São Paulo) · PostgreSQL 17.6 + PostGIS 3.3.7.

## Migraciones

Se aplican en orden numérico. Ninguna se edita después de aplicada: los cambios
van en una migración nueva.

| Archivo | Qué hace |
|---|---|
| `0001_extensiones_enums_y_base.sql` | PostGIS, enums, ciudades, zonas, perfiles |
| `0002_actores.sql` | comercios, repartidores, documentación |
| `0003_tarifas_y_envios.sql` | tarifario versionado, envíos, auditoría, ofertas |
| `0004_dinero_y_reclamos.sql` | pagos, suscripciones, liquidaciones, reclamos |
| `0005_funciones.sql` | cotización, máquina de estados, motor de asignación |
| `0006_rls.sql` | Row Level Security por rol |
| `0007_semilla.sql` | Malargüe, tarifario inicial, documentación exigida |
| `0008_hardening.sql` | correcciones del advisor de seguridad |
| `0009_codigos_de_error.sql` | SQLSTATE propios (ver abajo) |
| `0010_fk_de_atribucion.sql` | la auditoría no bloquea borrar una cuenta |
| `0011_politicas_sin_solapamiento.sql` | una sola política permisiva por acción |

## Decisiones de diseño

**El precio lo calcula el servidor, siempre.** `crear_envio()` recibe
direcciones, nunca importes. No hay política de `insert` ni de `update` directo
sobre `envios` para comercio ni cadete: la única vía son las funciones RPC. Una
app comprometida o vieja no puede fijarse su propia tarifa.

**El tarifario es versionado, no editable.** Cambiar una tarifa cierra la fila
vigente (`vigente_hasta`) y crea una nueva. Así un envío de hace tres meses
sigue mostrando lo que realmente se cobró y las liquidaciones cerradas no se
mueven solas.

**Los importes son `integer` en pesos enteros.** No hay centavos en el producto
y evitamos por completo los errores de punto flotante.

**La ciudad es una fila, no una constante.** Abrir una ciudad nueva es un
`insert`. Lo mismo con `tipo_servicio`: hoy solo se usa `delivery`, pero taxi y
cadetería ya tienen lugar, como pide el documento de la clienta.

**Una sola posición por cadete, no un histórico.** `repartidores.ultima_ubicacion`
se sobrescribe. Guardar cada ping de GPS infla la base sin dar nada: el
seguimiento en vivo va por Realtime Broadcast.

**El origen del envío se copia, no se referencia.** Si un comercio se muda, los
envíos viejos tienen que seguir diciendo desde dónde salieron.

## Privacidad

El documento de la clienta pide no mostrar datos completos del cliente a
repartidores no asignados. Se implementa así: mientras el envío se le está
*ofreciendo*, el cadete lo ve a través de la vista `ofertas_abiertas`, que **no
expone** `cliente_nombre`, `cliente_telefono` ni `cliente_indicaciones`. Esos
campos aparecen recién cuando acepta y el envío queda asignado.

## Códigos de error

Viajan en la respuesta de PostgREST, así que la app puede distinguirlos sin leer
el texto del mensaje.

| Código | Significado |
|---|---|
| `MY001` | transición de estado inválida |
| `MY002` | código de entrega incorrecto |
| `MY003` | la oferta ya no está disponible (venció o la tomó otro) |
| `MY004` | no existe el recurso pedido |
| `42501` | sin permiso o cuenta no aprobada (PostgREST → HTTP 403) |

> No usar la clase `P00xx`: ya está tomada por PL/pgSQL. En particular `P0004`
> es `assert_failure`, que `exception when others` **no atrapa**.

## Prueba de regresión

`tests/flujo_completo.sql` recorre el ciclo entero (crear → cotizar → buscar →
ofertar → aceptar → retirar → entregar) simulando los JWT de cada rol con
`set_config`, verifica que el precio lo ponga el servidor, que el motor elija al
cadete más cercano dentro del radio, que una transición inválida rebote y que un
código de entrega equivocado no cierre el envío. Deja la base como la encontró.

Se corre contra el proyecto con el mismo endpoint que las migraciones.

## Pendiente

- **pg_cron** para vencer ofertas automáticamente (`vencer_ofertas()` ya está
  escrita). Hay que habilitar la extensión desde el dashboard.
- **Custom Access Token Hook** para llevar el rol en el JWT. Hoy las políticas
  lo leen de `perfiles` con funciones `security definer`, que funciona bien; el
  hook ahorraría una consulta por request.
- **Realtime** en `envios` y `ofertas`.
- **Storage** para logos, fotos de producto y documentación de cadetes.
- **Zonas de cobertura**: la tabla existe, falta cargar el polígono de Malargüe
  y rechazar destinos fuera del área.
