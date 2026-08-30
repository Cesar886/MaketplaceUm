# Iniciar sesión / registrarse con Google

Todo el código está escrito y probado. **Falta solo pegar credenciales**: no
hay que tocar lógica para activarlo.

Mientras las credenciales estén vacías:

- la app muestra el botón deshabilitado con la nota "todavía no está
  disponible" (login) o directamente lo oculta (elección de tipo de cuenta);
- el backend responde `503 GOOGLE_NO_CONFIGURADO` en `POST /api/auth/google`;
- **el login por correo y contraseña funciona exactamente igual que antes.**

---

## Datos del proyecto que vas a necesitar

| Dato | Valor actual |
|---|---|
| `applicationId` de Android | `com.example.mercadito_um` |
| Bundle Identifier de iOS | `com.example.mercaditoUm` |
| Proyecto de Firebase ya existente | `mercadoum` (nº 483335034495) |
| Keystore de release | `android/upload-keystore.jks`, alias `upload` |

> El `applicationId` sigue siendo `com.example.…`. Si piensas cambiarlo antes
> de publicar en Play, **cámbialo ANTES** de crear las credenciales: el
> cliente OAuth de Android queda atado al nombre de paquete y habría que
> rehacerlo. (Cambiarlo también obliga a regenerar `google-services.json` y
> rompe la actualización de las instalaciones existentes.)

---

## Checklist para mañana

### 1. Google Cloud Console / Firebase

El proyecto de Firebase `mercadoum` ya existe (lo usa FCM) y trae un proyecto
de Google Cloud detrás. **Usa ese**, no crees uno nuevo: así el
`google-services.json` sigue sirviendo para las dos cosas.

1. **Pantalla de consentimiento OAuth** →
   `console.cloud.google.com` → proyecto `mercadoum` → *APIs & Services* →
   *OAuth consent screen*.
   - Tipo: **External**, estado *Testing* basta para probar.
   - Nombre de la app, correo de soporte, logo y correo del desarrollador.
   - Scopes: los que ya trae por defecto (`email`, `profile`, `openid`). No
     hace falta ninguno más.
   - En *Test users* agrega tu propio correo mientras esté en *Testing*.

2. **Huella SHA-1 del keystore** (Android la exige):

   ```bash
   # Firma de release (la que usan los APK que repartes)
   keytool -list -v -keystore android/upload-keystore.jks -alias upload
   # Firma de debug (para probar desde el celular con `flutter run`)
   keytool -list -v -keystore ~/.android/debug.keystore \
       -alias androiddebugkey -storepass android -keypass android
   ```

   Copia **las dos** SHA-1. Regístralas en Firebase → *Configuración del
   proyecto* → app de Android → *Agregar huella digital*. Sin la de debug, el
   botón falla en tus pruebas locales con un genérico "cancelado".

3. **Credenciales OAuth** → *APIs & Services* → *Credentials* →
   *Create credentials* → *OAuth client ID*. Crea **tres**:

   | Tipo | Datos que pide | Para qué sirve |
   |---|---|---|
   | **Android** | package `com.example.mercadito_um` + SHA-1 (una por huella) | Identifica a la app en el dispositivo. **No se pega en ningún archivo.** |
   | **iOS** | bundle `com.example.mercaditoUm` | Abrir la pantalla de Google en iOS. |
   | **Web** | (sin datos extra) | **El más importante:** es el `aud` del idToken que verifica el backend. |

   > Si creas la app de Android desde Firebase con la SHA-1, Firebase genera
   > el cliente Android y el Web automáticamente; solo tendrías que crear el
   > de iOS a mano. Revisa la lista de *Credentials* antes de duplicarlos.

### 2. Pegar los valores

| Dónde | Qué pegar |
|---|---|
| `lib/config/google_auth_config.dart` → `serverClientId` | El **Web client ID** (`…apps.googleusercontent.com`) |
| `lib/config/google_auth_config.dart` → `iosClientId` | El **iOS client ID** (solo si vas a compilar para iOS) |
| `backend/.env` → `GOOGLE_CLIENT_IDS` | Los **tres** Client ID separados por coma (ver `backend/.env.example`) |
| `android/app/google-services.json` | Descárgalo otra vez de Firebase tras registrar las SHA-1 y **reemplaza el archivo**. El actual trae `"oauth_client": []`, señal de que aún no hay huellas registradas. |
| `ios/Runner/GoogleService-Info.plist` | Descárgalo de Firebase (hoy no existe) y agrégalo al target *Runner* en Xcode. |
| `ios/Runner/Info.plist` | Sustituye `com.googleusercontent.apps.PEGAR_AQUI_REVERSED_CLIENT_ID` por el `REVERSED_CLIENT_ID` del plist anterior. |

No hace falta **Client Secret** en ninguna parte: el backend no intercambia
códigos de autorización, solo verifica idToken contra las claves públicas de
Google.

### 3. Reiniciar y probar

```bash
flutter pub get && flutter run          # app
cd backend && npm install && pm2 restart mercadito-backend --update-env
```

Prueba los dos caminos:

1. **Cuenta nueva** → el botón lleva a elegir tipo de cuenta y al formulario
   ya prellenado (correo bloqueado, sin campos de contraseña) → al terminar,
   sesión iniciada y pantalla de verificación, igual que el registro normal.
2. **Cuenta existente** (regístrate por correo y luego entra con el mismo
   correo por Google) → entra directo, sin crear una cuenta duplicada. La
   contraseña anterior **sigue funcionando**: vincular Google añade una
   puerta, no cierra la otra.

---

## Restringir a correos institucionales (opcional, apagado)

`backend/.env` → `GOOGLE_ALLOWED_DOMAINS`.

- Vacío (**actual**): entra cualquier cuenta de Google.
- `GOOGLE_ALLOWED_DOMAINS=um.edu.mx,alumno.um.edu.mx`: solo comunidad UM.

**Recomendación: dejarlo apagado.** El marketplace acepta negocios y
particulares, que por definición no tienen correo UM; encenderlo los dejaría
fuera del login con Google. Lo institucional ya se comprueba donde importa —
en la verificación por OTP al correo `@um.edu.mx` / `@alumno.um.edu.mx`, que
es lo que da la insignia. Se puede encender y apagar sin tocar código ni
recompilar la app: cambiar la variable y reiniciar el backend.

---

## Cómo funciona (para cuando haya que tocarlo)

```
app                          backend                    Google
 │ authenticate()  ──────────────────────────────────────▶ │
 │ ◀───────────────────────────────────── idToken firmado  │
 │ POST /api/auth/google {idToken} ──▶ │                    │
 │                                     │ verifyIdToken ────▶│
 │                                     │◀─── firma, aud, exp│
 │                                     │
 │  ◀── 200 {token, seller}            │ (la cuenta existe)
 │  ◀── 404 GOOGLE_ACCOUNT_NOT_FOUND   │ (hay que registrarse)
 │ POST /api/auth/google {idToken, registro} ──▶ 201 {token, seller}
```

- La app **nunca** es autoridad de identidad: manda el idToken y el servidor
  decide. El correo de la cuenta sale siempre del token, nunca del cliente.
- La respuesta es idéntica a la de `/api/auth/login` (`token` + `seller`), y
  la app la procesa con el mismo código (`AuthProvider._aplicarSesionBackend`),
  para que no existan dos definiciones de "qué pasa después de entrar".
- Hace falta un segundo paso con `registro` porque un idToken trae correo,
  nombre y foto, pero el registro de este marketplace exige además tipo de
  cuenta, teléfono y método de pago.

### Archivos

| Archivo | Qué hace |
|---|---|
| `lib/config/google_auth_config.dart` | Client ID (los placeholders) |
| `lib/services/google_sign_in_service.dart` | Consigue el idToken del SDK |
| `lib/services/api_service.dart` → `authGoogle` | Llama al backend y traduce sus tres respuestas |
| `lib/providers/auth_provider.dart` | `signInWithGoogle`, `registrarConGoogle` |
| `lib/widgets/google_sign_in_button.dart` | Botón y logo |
| `lib/screens/auth/google_auth_flow.dart` | Qué hacer con cada resultado |
| `backend/src/services/googleAuth.js` | Verifica el idToken contra Google |
| `backend/src/routes/authGoogle.js` | `POST /api/auth/google` |
| `test/google_auth_test.dart`, `backend/src/routes/authGoogle.test.js` | Pruebas |
