# MODO YA · Preguntas abiertas

Cosas que hay que cerrar con la clienta. Están ordenadas por **cuánto bloquean
el desarrollo**: las primeras cambian cómo está construido el sistema, las
últimas son números que se cargan desde el panel y se pueden cambiar cualquier
día sin tocar código.

Última actualización: 13/09/2026.

---

## Bloqueantes

Estas tres cambian el modelo de datos o el flujo. Cuanto más tarde se decidan,
más caro sale cambiarlas.

### 1. ¿El envío se paga en efectivo o de forma digital?

**Por qué importa:** es la decisión más grande que queda. Define si hace falta
integrar una pasarela de pago, cómo se rinde la plata y qué tan trazable es cada
operación.

Hoy los documentos se contradicen:

- El documento MVP (sección 8) dice: *"El MVP se plantea sin efectivo para
  mantener trazabilidad"*.
- La pantalla del repartidor (B3) dice: *"Ganancia neta garantizada · Cobro en
  mano en efectivo"*.

**Opciones:**

| | Cómo funciona | A favor | En contra |
|---|---|---|---|
| **Efectivo** | El cadete cobra en mano y después rinde la comisión de MODO YA | Arranca ya, sin integrar nada | La trazabilidad depende de que el cadete rinda. Hay que llevarle cuenta corriente |
| **Digital** | Todo pasa por una pasarela (ej. Mercado Pago) | Trazabilidad total, la plata entra sola | Comisión de la pasarela, y la dueña factura el volumen completo |
| **Los dos** | El comercio elige por envío | Flexible para el piloto | Hay que construir y conciliar las dos vías desde el principio |

> **Nota para la clienta:** si se elige digital, hay que hablar con el contador
> antes de arrancar. Toda la facturación pasa por ella (ARCA, Ingresos Brutos
> Mendoza), aunque después le transfiera a comercios y cadetes.

**Respuesta:**

---

### 2. ¿Qué documentación se le exige a un cadete?

**Por qué importa:** define qué tiene que subir cada cadete antes de poder
trabajar y qué revisa la administración para aprobarlo.

Supuesto de trabajo cargado hoy en el sistema (se cambia en dos minutos desde el
panel):

- **Moto y auto:** DNI, licencia de conducir, cédula verde, seguro del vehículo
- **Bicicleta y a pie:** DNI

**A confirmar:** ¿hace falta seguro propio? ¿Se le pide antecedentes penales?
¿Constancia de monotributo?

**Respuesta:**

---

### 3. Política de cancelaciones y pedidos no entregados

**Por qué importa:** define qué pasa con la plata y con la reputación cuando algo
sale mal. Hoy el sistema registra la cancelación y el motivo, pero no decide nada.

Casos a cubrir:

- El comercio cancela **después** de que un cadete aceptó y ya está yendo.
  ¿Se le paga algo al cadete?
- El cadete acepta y después no aparece. ¿Qué pasa con su reputación?
- El cliente no está en el domicilio. ¿Cuánto espera el cadete? ¿Quién paga?
- El cadete no puede entregar. ¿Devuelve el pedido al comercio? ¿Cobra igual?

**Respuesta:**

---

## Importantes, pero no bloquean

Se cargan desde el panel de administración y se pueden cambiar en cualquier
momento sin publicar una versión nueva de la app. Conviene definirlas antes del
piloto, pero se puede empezar a desarrollar sin ellas.

### 4. Tarifa por kilómetro adicional

Hoy está en **$0**: un envío de 8 km sale lo mismo que uno de 2 km. Se puso en
cero a propósito para no inventar un cobro que nadie definió.

- Precio base hasta 2 km: **$3.500** ($3.000 cadete + $500 MODO YA)
- Kilómetro adicional: **a definir**

¿El km adicional lo cobra entero el cadete, o también se lleva comisión MODO YA?

**Respuesta:**

---

### 5. Radio de búsqueda y tiempo para aceptar

Valores de arranque cargados hoy:

- **Radio:** 3 km alrededor del comercio
- **Tiempo para aceptar:** 30 segundos antes de pasar al siguiente cadete

Son los dos números que más conviene ajustar durante el piloto midiendo cuánto
tarda un cadete en aceptar de verdad.

**Respuesta:**

---

### 6. Suscripción mensual del comercio

- **Precio:** a definir
- ¿Hay período de prueba gratis para los primeros comercios del piloto?
- ¿Qué pasa si un comercio no paga? ¿Se le corta el servicio o queda avisado?
- ¿Cómo se cobra? (link de pago, transferencia, débito automático)

**Respuesta:**

---

### 7. Liquidación al cadete

Ya está decidido que **MODO YA cobra y liquida cada cierto tiempo**. Falta:

- **Cada cuánto:** ¿semanal, quincenal, a pedido del cadete?
- **Por qué medio:** ¿transferencia, Mercado Pago, efectivo?
- ¿Hay un mínimo para poder retirar?

**Respuesta:**

---

## Legales, antes de salir a producción

No los podemos definir nosotros: necesitan asesoramiento profesional. Pero sin
esto no se puede publicar en Google Play ni en la App Store.

- **Términos y condiciones** y **política de privacidad** (las tiendas las
  exigen, y tiene que haber una web pública donde vivan).
- **Página de eliminación de cuenta** accesible desde la web. Google Play la pide
  expresamente.
- **Relación con los cadetes:** ¿son autónomos? ¿Hace falta que facturen? Esto
  tiene implicancias laborales serias, conviene consultarlo con un abogado antes
  del piloto y no después.
- **Seguros:** ¿qué pasa si un cadete choca durante un envío?
- **Datos personales:** el sistema ya limita qué ve cada uno (un cadete no ve los
  datos del cliente hasta que acepta el envío), pero hay que declararlo en la
  política de privacidad.

---

## Decisión de alcance ya tomada

**El grupo D de pantallas entra en el proyecto.** Es decir, además de la
cadetería (el comercio pide un cadete), la app va a tener también:

- Catálogo de productos por comercio
- Carrito y checkout para el cliente final
- Una app propia para el cliente

Vale aclarar que esto **excede lo que describe el documento MVP**, que en su
sección 13 excluye explícitamente *"marketplace de comida o catálogo de
productos"* y *"app independiente para el cliente final"*. Conviene dejarlo por
escrito con la clienta para que no haya sorpresas de alcance ni de plazos.
