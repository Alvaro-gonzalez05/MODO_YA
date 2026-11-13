# Política de Privacidad de MODO YA

**Última actualización:** [COMPLETAR: fecha de publicación]

> **Borrador técnico, no un documento legal terminado.** Describe con exactitud
> qué datos guarda el sistema hoy, verificado contra la base de datos real.
> Necesita revisión profesional antes de publicarse, y hay que **mantenerlo
> actualizado**: si la app empieza a recolectar algo nuevo, este documento
> cambia. Google Play y la App Store comparan lo que declarás acá con lo que la
> app realmente hace.

---

## 1. Quién trata tus datos

- **Responsable:** [COMPLETAR: razón social o nombre completo]
- **CUIT o CUIL:** [COMPLETAR] *(si no está registrada en AFIP, va el CUIL; la
  norma pide identificar al responsable, no que sea una empresa)*
- **Domicilio:** [COMPLETAR]
- **Contacto para temas de privacidad:** [COMPLETAR: email]

## 2. Qué datos recolectamos

### De todos los usuarios

| Dato | Para qué |
| --- | --- |
| Nombre | Identificarte en la app y ante las otras partes del pedido |
| Teléfono | Que el comercio o el repartidor puedan ubicarte por el pedido |
| Correo electrónico | Iniciar sesión y recuperar la cuenta |
| Contraseña | Se guarda cifrada; nadie en MODO YA puede verla |

### De los clientes

| Dato | Para qué |
| --- | --- |
| Direcciones de entrega, con referencias y coordenadas | Cotizar el envío y que el repartidor llegue |
| Historial de pedidos | Mostrártelo, liquidar al comercio y al repartidor, y atender reclamos |
| Identificador de cliente de Mercado Pago | Poder cobrarte y devolverte |
| Últimos cuatro dígitos de la tarjeta guardada | Que reconozcas con cuál estás pagando |

### De los repartidores

| Dato | Para qué |
| --- | --- |
| Tipo de vehículo | Saber qué envíos ofrecerte y qué documentación pedirte |
| Documentación (licencia, seguro y la que corresponda) | Verificar que estás habilitado para repartir |
| **Ubicación en tiempo real, mientras estás conectado** | Ofrecerte los envíos cercanos y mostrarle al cliente dónde viene su pedido |
| Historial de envíos y de descuentos | Liquidarte lo que cobrás |

### De los comercios

| Dato | Para qué |
| --- | --- |
| Nombre, rubro, teléfono, dirección y coordenadas | Mostrarte en la app y calcular los envíos |
| Catálogo, precios y horarios | Que el cliente pueda comprarte |
| Historial de ventas y descuentos | Liquidarte |

### Datos técnicos

| Dato | Para qué |
| --- | --- |
| Identificador del dispositivo para notificaciones | Mandarte avisos de tus pedidos |
| Registros técnicos de uso y errores | Que la app funcione y poder diagnosticar fallas |

## 3. Lo que NO guardamos

**No guardamos el número de tu tarjeta, su vencimiento ni su código de
seguridad.** Nunca pasan por nuestros servidores: los datos de la tarjeta viajan
desde tu teléfono directamente a Mercado Pago, que nos devuelve un código que
solo sirve para cobrar esa compra. Si guardás una tarjeta, lo que queda
almacenado es un identificador de Mercado Pago y los últimos cuatro dígitos.

No recolectamos datos de salud, biométricos, ideología, religión, afiliación
sindical ni ningún otro dato sensible en los términos de la Ley 25.326.

## 4. La ubicación, en detalle

Es el dato más sensible que maneja la plataforma, así que lo explicamos aparte.

**Del repartidor.** Mientras está conectado y disponible, la app envía su
ubicación periódicamente. Se usa para ofrecerle los envíos más cercanos y para
mostrarle al cliente del pedido en curso dónde viene su repartidor.
El repartidor puede dejar de compartirla desconectándose. Guardamos la última
ubicación conocida, no un rastro histórico de sus recorridos.

**Del cliente.** Guardamos las direcciones que cargás, con sus coordenadas, para
cotizar y entregar. La app puede pedirte tu ubicación para ayudarte a marcar una
dirección nueva; podés negarte y escribirla a mano.

## 5. Quién ve qué

El sistema limita por diseño qué puede ver cada parte:

- **El repartidor no ve los datos del cliente hasta que acepta el envío.** Una
  vez que lo acepta ve el nombre, el teléfono y la dirección de entrega, porque
  los necesita para entregar.
- **El comercio ve** los datos del pedido que le llega y los del cliente que se
  lo hizo. **No ve** tu libreta de direcciones ni tu historial con otros
  comercios.
- **El cliente ve**, mientras el pedido está en curso, el nombre de pila del
  repartidor y su ubicación aproximada en el mapa. No ve su teléfono ni su
  documentación.
- **La administración de MODO YA** accede a lo necesario para operar: resolver
  reclamos, liquidar y controlar el servicio.

Estas restricciones están implementadas en la base de datos, no solamente en la
pantalla.

## 6. Con quién compartimos datos

Compartimos lo mínimo necesario con proveedores que nos prestan servicios:

| Proveedor | Para qué | Qué recibe |
| --- | --- | --- |
| **Mercado Pago** | Cobrar y devolver | Los datos de tu tarjeta (que van directo a ellos), tu correo y el monto |
| **Supabase** | Alojar la base de datos y los archivos | Todo lo descripto arriba, almacenado |
| **Google Firebase** | Enviar notificaciones | El identificador de tu dispositivo |
| **OpenStreetMap** | Mostrar los mapas | Las coordenadas que se dibujan |

No vendemos tus datos. No los cedemos con fines publicitarios de terceros.

Podemos entregarlos a una autoridad judicial o administrativa competente cuando
una norma nos obligue.

[COMPLETAR: confirmar si alguno de estos proveedores aloja datos fuera de la
Argentina y, si corresponde, declarar la transferencia internacional.]

## 7. Cuánto tiempo los guardamos

- **Tu cuenta y tus datos personales:** mientras la cuenta esté activa.
- **Pedidos, envíos y liquidaciones:** aunque elimines tu cuenta, los
  conservamos por el plazo que exige la normativa comercial e impositiva
  (actualmente diez años). Se conservan **disociados de tu identidad** en lo que
  sea posible: quedan los montos, las fechas y los conceptos, no tu nombre ni tu
  teléfono.
- **Documentación de repartidores:** mientras esté vinculado a la plataforma y
  el plazo legal posterior que corresponda.
- **Registros técnicos:** [COMPLETAR: plazo].

## 8. Tus derechos

Según la Ley 25.326 de Protección de Datos Personales, podés:

- **Acceder** a los datos que tenemos sobre vos.
- **Rectificarlos** si están mal o desactualizados.
- **Actualizarlos.**
- **Pedir que se supriman**, con los límites del punto 7.

Para ejercerlos escribí a [COMPLETAR: email]. Tenemos diez días corridos para
responder un pedido de acceso y cinco días hábiles para uno de rectificación o
supresión.

> La **Agencia de Acceso a la Información Pública**, órgano de control de la Ley
> 25.326, tiene la atribución de atender las denuncias y reclamos que
> interpongan quienes resulten afectados en sus derechos por incumplimiento de
> las normas vigentes en materia de protección de datos personales.

*(Este párrafo es el texto que la normativa exige incluir. Confirmar su
redacción vigente con el abogado.)*

## 9. Cómo eliminar tu cuenta

Podés eliminarla desde la app, en "Mi cuenta", o desde
[COMPLETAR: URL de la página de eliminación], sin necesidad de escribirnos.

**Qué se elimina:** tu nombre, tu teléfono, tu correo, tus direcciones, tus
tarjetas guardadas, tu suscripción y el identificador de tu dispositivo.

**Qué se conserva, y por qué:** los registros contables de pedidos y pagos, por
el plazo impositivo y comercial obligatorio, disociados de tu identidad. Si
tenés una suscripción activa, se da de baja; si tenés un pedido en curso, la
eliminación se procesa cuando termina.

La eliminación es definitiva y no se puede deshacer.

## 10. Menores de edad

MODO YA es para mayores de 18 años. No recolectamos datos de menores a
sabiendas. Si detectamos una cuenta de un menor, la damos de baja.

## 11. Seguridad

Las contraseñas se almacenan cifradas. El acceso a los datos está restringido a
nivel de base de datos según el rol de cada usuario. La documentación que suben
los repartidores se guarda en almacenamiento privado, accesible solo con
enlaces temporales. Las comunicaciones viajan cifradas.

Ningún sistema es infalible. Si ocurriera un incidente que comprometa datos
personales, lo comunicaremos conforme a la normativa aplicable.

## 12. Cambios

Si modificamos esta política, publicamos la versión nueva con su fecha y, cuando
el cambio sea relevante, lo avisamos en la app.
