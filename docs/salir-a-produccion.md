# Salir a producción

Lo que falta para publicar MODO YA en serio, en el orden en que conviene
hacerlo. El código ya está preparado para cada paso: lo que queda son cuentas,
claves y configuración, que tiene que hacer alguien con acceso (no se pueden
crear cuentas ni cargar claves desde el código).

---

## 1. Un dominio y la web publicada

**Bloquea todo lo demás.** Sin dominio no hay correo propio, y Google Play y
Apple piden una dirección pública para la política de privacidad y para
eliminar la cuenta.

1. Comprar el dominio. `modoya.com.ar` se compra en [NIC Argentina](https://nic.ar)
   con clave fiscal; un `.com` en cualquier registrador.
2. Publicar la carpeta `landing/` (es un sitio estático). Cloudflare Pages,
   Netlify o GitHub Pages lo hacen gratis: se conecta el repo, carpeta
   `landing`, sin comando de build, y se apunta el dominio.
3. Buscar `COMPLETAR` en `landing/` y poner el correo de contacto real.

Páginas que tienen que abrir sin iniciar sesión: `/`, `/terminos`,
`/privacidad`, `/eliminar-cuenta`, y las dos que usan los mails: `/confirmar`
y `/nueva-clave`.

## 2. Correo real

Hoy Supabase manda los mails con su servicio de prueba: como mucho dos por
hora y **solo a los miembros del proyecto**. Por eso la confirmación de email
está apagada y la app no ofrece "¿Olvidaste tu contraseña?".

Con [Resend](https://resend.com) (3.000 mails por mes gratis, alcanza de sobra
para empezar):

1. Crear la cuenta en Resend.
2. **Domains → Add domain**: el dominio del paso 1 (o un subdominio como
   `correo.modoya.com.ar`). Resend muestra registros DNS para cargar en el
   registrador; en 5 a 10 minutos queda verificado.
3. **Integrations → Supabase → Connect**: elegir el proyecto de MODO YA y el
   dominio. Resend carga el SMTP en Supabase solo, sin que la clave pase por
   ningún archivo ni por el chat.
4. Con eso andando, desde la carpeta del proyecto:

   ```powershell
   .\supabase\scripts\configurar_auth.ps1 -Sitio https://modoya.com.ar -ExigirConfirmacion
   ```

   Carga las plantillas de los mails en castellano (`supabase/correo/`), hace
   que los links lleven a la web y exige confirmar el email al registrarse.
5. En `env/publico.json`, `"MY_CORREO_ACTIVO": true`, y sacar una versión: la
   app muestra "¿Olvidaste tu contraseña?".

Los locales y los riders tienen emails inventados (`@modoya.com`) que no
reciben nada: si se olvidan la contraseña, la administración les genera una
nueva desde su ficha, como hasta ahora.

## 3. Mapas y rutas

Hoy salen de servidores públicos (OpenStreetMap para las baldosas, OSRM para el
camino del rider) que **no permiten uso productivo**: con tráfico real pueden
bloquear la app sin aviso.

**Las baldosas** se eligen en `env/publico.json`, sin tocar código:

```json
"MY_MAPA_BALDOSAS": "https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=CLAVE",
"MY_MAPA_ATRIBUCION": "© MapTiler © OpenStreetMap"
```

| Proveedor | Costo | Nota |
|---|---|---|
| [MapTiler](https://www.maptiler.com/cloud/pricing/) Flex | USD 25/mes | 500.000 baldosas por mes. El plan gratis es solo para uso no comercial |
| [Geoapify](https://www.geoapify.com/pricing) | Gratis, o USD 59/mes | El gratis permite uso comercial limitado, con atribución. Da baldosas **y** rutas con la misma clave |
| Baldosas propias (Protomaps, `.pmtiles`) | Gratis | Un archivo con Malargüe en un hosting estático. Es lo más barato a largo plazo, pero hay que cambiar el dibujo del mapa a vectorial |

La clave de las baldosas viaja en la app (como la de Mercado Pago): en el panel
del proveedor hay que restringirla al paquete de la app y al dominio.

**La ruta** ya no la pide la app sino la Edge Function `ruta`, así que se
cambia sin sacar versión, cargando un secreto:

```powershell
.\supabase\scripts\guardar_secreto.ps1 RUTAS_GEOAPIFY_KEY
```

Sin secreto sigue usando el OSRM público. Con un OSRM propio (un servidor
chico con el extracto de Cuyo), el secreto es `RUTAS_OSRM_URL`.

## 4. Supabase

| | Estado |
|---|---|
| Contraseñas de al menos 8 caracteres | **Hecho** (la app ya lo decía; la base pedía 6) |
| Confirmar el email al registrarse | Paso 2 |
| Plantillas de los mails en castellano | Paso 2 (Supabase no deja cambiarlas sin SMTP propio) |
| Rechazar contraseñas filtradas | Necesita el plan Pro |
| Copias de seguridad diarias | Necesita el plan Pro |

**El plan Pro (USD 25/mes) conviene antes de cobrar de verdad:** el gratis no
hace copias de seguridad, pausa el proyecto si pasa una semana sin uso (lo
evita `mantener-viva.yml`) y no deja rechazar contraseñas filtradas. Con el Pro,
después correr de nuevo `configurar_auth.ps1`.

## 5. La ubicación del rider

**Hecho en la app.** El rider no se puede conectar sin "Permitir todo el
tiempo", y si lo saca estando conectado lo desconecta. Antes de pedir el
permiso le muestra el aviso que exige Google Play ("divulgación destacada").

Para la tienda: Google Play pide completar la **declaración de ubicación en
segundo plano** de la app del rider, con un video corto que muestre el aviso,
el permiso y la notificación fija de "Conectado".

## 6. Las tiendas

Ver `docs/publicar-en-las-tiendas.md`.
