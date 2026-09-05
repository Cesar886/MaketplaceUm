/**
 * Identidad de la app móvil, tal como la ven Android e iOS al verificar los
 * App Links / Universal Links. Vive aquí y no dentro de cada handler para que
 * los dos archivos de `/.well-known/` no se puedan desincronizar entre sí.
 *
 * Estos valores TIENEN que coincidir exactamente con los del proyecto nativo:
 *   - PAQUETE_ANDROID  ↔  `applicationId` en android/app/build.gradle.kts
 *   - BUNDLE_ID_IOS    ↔  PRODUCT_BUNDLE_IDENTIFIER en Runner.xcodeproj
 * Si no coinciden, Android no verifica el dominio y los links siguen abriendo
 * el navegador, sin ningún error visible.
 */

export const PAQUETE_ANDROID = 'site.marketplaceum.app';

export const BUNDLE_ID_IOS = 'com.example.mercaditoUm';

/**
 * Huella SHA-256 del certificado con el que se FIRMA el APK que instala el
 * usuario. Formato: 32 bytes en hexadecimal separados por dos puntos.
 *
 * IMPORTANTE: si la app se distribuye por Google Play con Play App Signing
 * (lo normal), la huella correcta es la de la llave de Google, NO la del
 * keystore local — Google re-firma el APK antes de entregarlo. Se saca de:
 *   Play Console → tu app → Test and release → Setup → App signing
 *   → "App signing key certificate" → SHA-256 certificate fingerprint
 *
 * Si todavía no subes a Play, la del keystore de release:
 *   keytool -list -v -keystore <archivo.jks> -alias <alias>
 *
 * Se pueden listar VARIAS (array): conviene incluir también la del keystore de
 * upload y la de debug, para poder probar los links con un build local.
 *
 * Mientras esté vacío, el archivo se sirve igual pero Android NO verificará el
 * dominio: los links abrirán el navegador y caerán en la web, que es
 * exactamente el fallback deseado. O sea, no se rompe nada; solo falta el
 * salto directo a la app.
 */
export const HUELLAS_SHA256_ANDROID: string[] = [];

/**
 * Team ID de Apple (10 caracteres alfanuméricos). Se saca de
 * developer.apple.com → Membership details → Team ID.
 *
 * Vacío hasta que exista la cuenta de desarrollador: iOS simplemente no
 * verificará el dominio y los links abrirán Safari, igual que arriba.
 */
export const APPLE_TEAM_ID = '';
