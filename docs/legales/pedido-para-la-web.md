# Lo que hay que agregar en la web de MODO YA

Este documento está escrito para reenviarlo tal cual a quien maneja el sitio.
Son **tres páginas públicas**. Sin ellas Google Play no aprueba la aplicación.

---

## Por qué hace falta

Google Play exige que toda app que permite crear una cuenta ofrezca una forma
de eliminarla, y que esa forma esté disponible **también desde la web**, no solo
dentro de la app. Además pide que los términos y la política de privacidad
tengan una dirección pública y estable.

La revisión de Google abre esas direcciones con un navegador común, sin sesión
iniciada. Si piden iniciar sesión, si tardan en cargar o si dan error, rechazan
la publicación.

---

## Página 1 — Eliminación de cuenta (la más importante)

**Dirección sugerida:** `https://[el-dominio]/eliminar-cuenta`

### Requisitos que Google verifica

1. **Tiene que abrirse sin iniciar sesión.** Nada de login, nada de muro.
2. **Tiene que nombrar la aplicación** de forma explícita: "MODO YA".
3. **Tiene que decir qué datos se eliminan y cuáles se conservan**, y por cuánto
   tiempo se conservan los que quedan.
4. **Tiene que ofrecer una forma concreta de pedir la eliminación**: un
   formulario o una dirección de correo visible.
5. **Tiene que ser una dirección estable**, que no cambie con el tiempo.

### Contenido exacto de la página

> # Eliminar tu cuenta de MODO YA
>
> Podés eliminar tu cuenta de MODO YA cuando quieras, y hay dos formas de
> hacerlo.
>
> ## Desde la aplicación
>
> Entrá a **Mi cuenta** y elegí **Eliminar mi cuenta**. Es inmediato y no hace
> falta que nos escribas.
>
> ## Desde acá
>
> Si no tenés la aplicación instalada o no podés entrar, completá este
> formulario con el correo electrónico con el que te registraste. Te vamos a
> pedir que confirmes desde ese mismo correo, para asegurarnos de que la cuenta
> es tuya.
>
> [FORMULARIO: campo de correo electrónico + campo de texto opcional "motivo" +
> botón "Pedir la eliminación"]
>
> También podés escribirnos a **[COMPLETAR: correo de contacto]** desde la
> casilla con la que te registraste.
>
> Procesamos los pedidos dentro de los **[COMPLETAR: 5] días hábiles**.
>
> ## Qué se elimina
>
> - Tu nombre, tu teléfono y tu correo electrónico
> - Tus direcciones de entrega
> - Las tarjetas que hayas guardado
> - Tu suscripción a MODO YA Plus, si tenés una
> - El registro de tu dispositivo para notificaciones
>
> ## Qué se conserva, y por qué
>
> Los registros de pedidos, pagos y facturación se conservan por el plazo que
> exige la normativa comercial e impositiva argentina (actualmente **diez
> años**), **disociados de tu identidad**: quedan los montos, las fechas y los
> conceptos, pero no tu nombre ni tu teléfono.
>
> ## Antes de eliminarla, tené en cuenta
>
> - Si tenés un pedido en curso, la eliminación se procesa cuando termina.
> - Si tenés MODO YA Plus activo, se da de baja y no se vuelve a cobrar. El mes
>   ya pagado no se reintegra.
> - **La eliminación es definitiva y no se puede deshacer.** Si volvés a usar
>   MODO YA, vas a tener que crear una cuenta nueva.

### Nota técnica para quien la programe

El formulario puede simplemente mandar un correo a la casilla de
administración. **No hace falta que se conecte con la base de datos**: la
eliminación la ejecuta la administración desde el panel. Lo que Google evalúa es
que la página exista, sea pública y explique bien.

Si se quiere evitar spam, basta con un captcha. Conviene **no** usar uno que
bloquee o complique el acceso, porque el revisor de Google va a entrar.

---

## Página 2 — Términos y Condiciones

**Dirección sugerida:** `https://[el-dominio]/terminos`

El texto está en `docs/legales/terminos-y-condiciones.md`.
**Todavía no está aprobado por un abogado**, así que no lo publiquen hasta que
vuelva revisado.

Requisitos: pública, sin login, dirección estable, y que muestre visible la
**fecha de última actualización**.

---

## Página 3 — Política de Privacidad

**Dirección sugerida:** `https://[el-dominio]/privacidad`

El texto está en `docs/legales/politica-de-privacidad.md`. Misma advertencia:
pendiente de revisión profesional.

Requisitos: los mismos que la anterior, más uno importante — **el contenido
tiene que coincidir con lo que la app realmente hace**. Google compara esta
página con el formulario de "Seguridad de los datos" que se completa en Play
Console. Si no coinciden, rechazan.

---

## Resumen para pedirlo en una línea

> Necesito tres páginas públicas en el sitio: `/eliminar-cuenta`, `/terminos` y
> `/privacidad`. Tienen que abrirse sin iniciar sesión y tener direcciones
> estables. La de eliminación lleva un formulario que mande un correo a
> administración. Los textos se los paso yo.

---

## Lo que queda de nuestro lado

- Poner los enlaces a las tres páginas dentro de la app.
- Agregar la opción **"Eliminar mi cuenta"** en la pantalla de Mi cuenta.
- Completar el formulario de "Seguridad de los datos" en Play Console, haciéndolo
  coincidir con la política de privacidad.
- Completar los `[COMPLETAR]` de los dos documentos legales.
