# Publicar en Google Play y en la App Store

Son dos apps en cada tienda: **MODO YA** (clientes, locales y administración) y
**MODO YA Rider**. Hoy se distribuyen como APK desde GitHub Releases; esto es lo
que falta para las tiendas.

## Antes de cualquiera de las dos

| | Estado |
|---|---|
| Web con privacidad, términos y eliminar cuenta | Hechas en `landing/`; falta el dominio y publicarlas (`docs/salir-a-produccion.md`, paso 1) |
| Eliminar la cuenta desde la app | **Hecho** (0073): Mi cuenta → Eliminar mi cuenta. Las bajas que piden por la web las hace la administración desde su menú → "Dar de baja a un cliente" |
| Correo de contacto real en `landing/` | Falta (buscar `COMPLETAR`) |
| Íconos y capturas | Íconos hechos (`flutter_launcher_icons`); faltan las capturas de cada tienda |

**El nombre del paquete es para siempre.** Una vez subida a una tienda, la app
no puede cambiarlo. Hoy son `com.modoya.app` y `com.modoya.modo_ya_repartidor`.
Si se quiere uno más prolijo para el rider (por ejemplo `com.modoya.rider`), es
ahora o nunca. El costo: los riders que tienen el APK instalado tendrían que
instalar la app nueva una vez.

## Google Play

1. **Cuenta de desarrollador**: [play.google.com/console/signup](https://play.google.com/console/signup),
   USD 25 una sola vez. Hay dos caminos y el costo de cada uno es distinto:
   - **A nombre del negocio (organización)**: pide número **D-U-N-S**, que es
     gratis pero tarda unos días y necesita una entidad registrada. Google
     **no da excepciones**: sin D-U-N-S no habilita la cuenta de organización
     (la única salvedad son organismos de gobierno). A cambio, se publica
     derecho, sin prueba previa.
   - **A nombre de una persona (personal)**: nombre legal, domicilio, teléfono
     y un documento de identidad. El costo es que a las cuentas personales
     creadas después del 13/11/2023 Google les exige una **prueba cerrada con
     12 testers durante 14 días corridos** antes de habilitar producción.

   **El CUIT no es requisito de Google en ninguno de los dos casos.** Los datos
   impositivos aparecen en el perfil de pagos solo si la app cobra con la
   facturación de Google, y MODO YA cobra por fuera, con Mercado Pago. Para la
   cuenta personal alcanza el DNI.

   **No conviene usar el CUIT ni la identidad de un familiar.** La cuenta, las
   dos apps, los términos y la responsabilidad quedan a nombre de esa persona
   para siempre, y la cuenta de Mercado Pago que cobra es de Carolina: los dos
   nombres tienen que ser el mismo o queda una inconsistencia que miran tanto
   Google como AFIP.
2. **Firma**: la clave de los APK (`D:\dev\claves\modoya\`, secretos de GitHub)
   sirve como clave de subida. Al crear la app, aceptar **Play App Signing**.
3. **Formato**: Play pide **AAB**, no APK. Agregar al workflow de release
   `flutter build appbundle --release` (las dos apps) y subir los `.aab`.
4. **Ficha de cada app**: descripción, capturas, ícono 512×512, gráfico
   destacado 1024×500, categoría (Comida y bebida / Mapas y navegación).
5. **Contenido de la app**: política de privacidad (URL), eliminación de cuenta
   (URL de `/eliminar-cuenta`), **Seguridad de los datos** (ubicación, nombre,
   email, teléfono, datos de pago procesados por Mercado Pago), clasificación
   de contenido, público objetivo (mayores de 18).
6. **Solo la app del rider**: declaración de **ubicación en segundo plano**, con
   un video de 30 segundos que muestre el aviso de "Tu ubicación mientras estás
   conectado", el permiso "Permitir todo el tiempo" y la notificación fija.
7. Subir primero a **prueba interna**, después a producción.

Además, **las dos apps** declaran `REQUEST_INSTALL_PACKAGES` (la
autoactualización desde GitHub). Play no permite usarlo para que una app se
actualice sola: en la versión de la tienda hay que sacar ese permiso y el aviso
de actualización, y dejar que actualice Play.

## App Store

1. **Apple Developer Program**: [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/),
   USD 99 por año. Como organización pide también D-U-N-S.
2. **El proyecto de iOS no existe todavía**: no hay carpeta `ios/` en ninguna de
   las dos apps. Se crea con `flutter create --platforms=ios .` en cada una.
3. **Hace falta una Mac** con Xcode para compilar y firmar, o un servicio que
   compile en la nube (Codemagic, o GitHub Actions con `macos-latest`).
4. En el `Info.plist` de la app del rider: `NSLocationWhenInUseUsageDescription`,
   `NSLocationAlwaysAndWhenInUseUsageDescription` y `UIBackgroundModes` con
   `location`. El código ya pide "siempre" y manda la ubicación en segundo
   plano en iOS; sin esas tres claves iOS no lo deja.
5. En **App Store Connect**: crear las dos apps, ficha, capturas (iPhone 6,9" y
   6,5"), **privacidad de la app** (los mismos datos que en Play), y subir con
   Xcode o Transporter.
6. **Revisión**: Apple prueba la app con cuentas que hay que darle (un cliente y
   un rider de prueba) y pregunta por qué el rider necesita la ubicación siempre.
   Los pagos con Mercado Pago están permitidos porque son bienes y servicios
   físicos (comida, envíos). MODO YA Plus conviene explicarlo en las notas de
   revisión como lo que es: envío gratis, un servicio físico.
