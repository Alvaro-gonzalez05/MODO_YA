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
| `0012_catalogo.sql` | clientes, rubros, menús, productos, opciones, horarios |
| `0013_pedidos.sql` | pedidos, renglones, máquina de estados, sincronía con el envío |
| `0014_rls_marketplace.sql` | RLS del catálogo y de los pedidos |
| `0015_politicas_catalogo.sql` | mismo arreglo que 0011, sobre el catálogo |

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

## Pedido y envío son cosas distintas

El sistema cubre dos productos que conviven:

- **Cadetería** — el comercio pide un cadete. Genera un `envio` sin `pedido_id`.
- **Marketplace** — el cliente arma un carrito. Genera un `pedido`, y cuando el
  comercio lo acepta nace el `envio` que lo lleva (`envios.pedido_id`).

Modelarlos por separado es lo que permite que la cadetería siga funcionando sola
sin arrastrar el catálogo, y que el marketplace reutilice entero el motor de
asignación que ya existía.

Dos detalles que importan:

**La cotización del envío se congela en el pedido.** El cliente paga $3.500 de
envío al comprar; media hora después el comercio acepta y el envío se crea con
*esos* $3.500, no con una cotización nueva. Por eso `pedidos` guarda
`envio_tarifario_id`, `envio_ganancia_repartidor` y `envio_comision`.

**Se busca cadete recién cuando el pedido está listo**, no cuando se acepta. No
tiene sentido tener a alguien esperando en la puerta mientras se prepara la
comida.

**El estado del envío arrastra al del pedido.** Cuando el cadete marca
"retirado", el pedido pasa solo a `en_camino`; al confirmar la entrega, queda
`entregado`. Lo hace un trigger, así el cliente ve un estado coherente sin que
nadie lo sincronice a mano.

## Privacidad

El documento de la clienta pide no mostrar datos completos del cliente a
repartidores no asignados. Se implementa en tres capas:

1. **Antes de aceptar**, el cadete ve el envío por la vista `ofertas_abiertas`,
   que **no expone** `cliente_nombre`, `cliente_telefono` ni
   `cliente_indicaciones`. Esos campos aparecen recién cuando acepta.
2. **El cadete nunca ve el pedido.** Qué productos pidió el cliente y cuánto
   pagó no le hace falta para entregar. `pedidos` y `pedido_items` no le
   devuelven ni una fila.
3. **La libreta de direcciones es del cliente.** Ni el comercio ni el cadete la
   ven: a ellos les llega copiada, en el pedido y en el envío, solo la dirección
   de esa entrega.

Las tres están verificadas en `tests/flujo_marketplace.sql`.

## Códigos de error

Viajan en la respuesta de PostgREST, así que la app puede distinguirlos sin leer
el texto del mensaje.

| Código | Significado |
|---|---|
| `MY001` | transición de estado inválida |
| `MY002` | código de entrega incorrecto |
| `MY003` | la oferta ya no está disponible (venció o la tomó otro) |
| `MY004` | no existe el recurso pedido |
| `MY005` | el comercio está cerrado |
| `MY006` | datos inválidos (cantidad, opción que no corresponde) |
| `42501` | sin permiso o cuenta no aprobada (PostgREST → HTTP 403) |

> No usar la clase `P00xx`: ya está tomada por PL/pgSQL. En particular `P0004`
> es `assert_failure`, que `exception when others` **no atrapa**.

## Pruebas de regresión

Las dos dejan la base como la encontraron y se corren contra el proyecto con el
mismo endpoint que las migraciones.

**`tests/flujo_completo.sql`** — cadetería. Crear → cotizar → buscar → ofertar →
aceptar → retirar → entregar. Verifica que el precio lo ponga el servidor, que
el motor elija al cadete más cercano *dentro del radio* (hay un segundo cadete a
9 km que debe quedar afuera), que una transición inválida rebote y que un código
de entrega equivocado no cierre el envío.

**`tests/flujo_marketplace.sql`** — marketplace. Carrito con opciones → pago →
aceptación → preparación → entrega. Además de los precios y la sincronía entre
pedido y envío, comprueba las tres reglas de privacidad de arriba.

> **Ojo al escribir pruebas de RLS.** Estos scripts corren como `postgres`, que
> es dueño de las tablas y **saltea RLS por completo**. Cualquier comprobación
> de políticas necesita `set local role authenticated` (y volver con
> `reset role` antes de escribir en la tabla temporal de resultados, que
> `authenticated` no puede tocar). Sin eso, un test de RLS pasa siempre y no
> prueba nada. `flujo_completo.sql` ejercita las RPC, que validan por dentro,
> pero **no** verifica RLS; el de marketplace sí.

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
