# Salir a producción

Lo que falta para publicar MODO YA en serio, en el orden en que conviene
hacerlo. El código ya está preparado para cada paso: lo que queda son cuentas,
claves y configuración, que tiene que hacer alguien con acceso (no se pueden
crear cuentas ni cargar claves desde el código).

---

## 1. Un dominio y la web publicada

**Hecho el 26/10/2026:** el dominio es `modoya.app` (Namecheap) y la web está
en Vercel, proyecto `modo_ya-landing`, carpeta `landing/` de este repo. Se
publica sola con cada push a `main`. `modoya.app` redirige a
`https://www.modoya.app`, que es la dirección que tiene Supabase para los links
de los mails. DNS en Namecheap: `A @ 216.150.1.1` y `CNAME www` al host que da
Vercel. Falta lo de "Verify contacts" en Namecheap: si no se confirma el email
del dueño, el registrador suspende el dominio.

Lo que sigue de este paso es para referencia.

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

**Hecho el 26/10/2026.** Resend (cuenta modoya.codea@gmail.com, región São
Paulo) manda desde `MODO YA <no-responder@modoya.app>`; el dominio está
verificado con DKIM (`resend._domainkey`), dos CNAME (`send`, `rsend`) y DMARC
en Namecheap. La integración de Resend cargó el SMTP en Supabase, y
`configurar_auth.ps1 -Sitio https://www.modoya.app -ExigirConfirmacion` dejó las
plantillas en castellano y la confirmación de email obligatoria.
`MY_CORREO_ACTIVO` ya está en `true` en `env/publico.json`: la próxima versión
muestra "¿Olvidaste tu contraseña?".

Lo que sigue de este paso es para referencia.

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

**Elegido: Geoapify** (revisado el 27/10/2026). Es el único con plan gratis
que permite uso comercial, sin tarjeta, y da baldosas **y** rutas con la misma
cuenta:

| Proveedor | Costo | Nota |
|---|---|---|
| [Geoapify](https://www.geoapify.com/pricing) | Gratis hasta 3.000 créditos por día; después USD 59/mes (10.000 por día) | Una baldosa = 0,25 créditos (12.000 baldosas por día); una ruta = 1 crédito. Exige "Powered by Geoapify" y OpenStreetMap al pie del mapa |
| [MapTiler](https://www.maptiler.com/cloud/pricing/) Flex | USD 30/mes | 500.000 pedidos por mes. El gratis es solo para uso no comercial y se corta al pasarse |
| Baldosas propias (Protomaps, `.pmtiles`) | Gratis | Un archivo con Malargüe en un hosting estático. Lo más barato a largo plazo, pero hay que pasar el mapa a vectorial |

En el celular las baldosas quedan guardadas en el teléfono (flutter_map 8.2+
las cachea solo), así que el rider o el local que miran siempre la misma zona
casi no gastan. Si el uso crece, Geoapify avisa por mail antes del tope.

**Pasos** (con la cuenta de MODO YA, modoya.codea@gmail.com):

1. Crear la cuenta en [myprojects.geoapify.com](https://myprojects.geoapify.com),
   un proyecto "MODO YA" y **dos claves**: una para el mapa y otra para las
   rutas. La del mapa viaja dentro de la app y cualquiera la puede ver; la de
   las rutas queda en el servidor. Si alguien abusa de la del mapa, se cambia
   esa sola.
2. La del mapa, con el script (la pide tapada, prueba una baldosa de Malargüe
   y recién ahí escribe `env/publico.json` y `env/dev.json`):

   ```powershell
   .\supabase\scripts\configurar_mapas.ps1
   ```

3. La de las rutas, como secreto (anda al instante, sin sacar versión):

   ```powershell
   .\supabase\scripts\guardar_secreto.ps1 RUTAS_GEOAPIFY_KEY
   ```

4. Sacar una versión nueva: las baldosas se fijan al compilar, así que los
   instaladores que ya están en la calle siguen con el mapa viejo hasta
   actualizar.

Para volver al mapa público (solo desarrollo): `configurar_mapas.ps1 -Volver`.

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
