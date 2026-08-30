/// Credenciales de OAuth para "Continuar con Google".
///
/// ─── LO ÚNICO QUE HAY QUE TOCAR MAÑANA ──────────────────────
///
/// Todo el flujo (botón, pantallas, servicio, endpoint del backend) ya está
/// escrito. Falta solo pegar aquí los Client ID que genera Google Cloud
/// Console y los valores equivalentes en el backend y en los proyectos
/// nativos. Ver la checklist completa en `docs/google_sign_in.md`.
///
/// Mientras [serverClientId] siga vacío, el botón de Google aparece
/// deshabilitado con un mensaje de "no disponible" y el login por correo y
/// contraseña sigue funcionando exactamente igual que hoy.
///
/// ─── Por qué hay tres Client ID distintos ───────────────────
///
/// Google emite un Client ID por plataforma, pero el `idToken` que la app
/// manda al backend NO va dirigido al Client ID de Android o iOS: va
/// dirigido al **Web client ID** (eso es lo que significa "server" en
/// `serverClientId`). Por eso:
///
///   - [serverClientId] (Web) → obligatorio en Android y iOS. Es el `aud`
///     del idToken y lo que el backend verifica.
///   - [iosClientId] (iOS) → obligatorio solo en iOS/macOS, para abrir la
///     pantalla de Google. En Android se deja null: allí la identidad de la
///     app se comprueba por `applicationId` + huella SHA-1, que se registran
///     en la consola, no en el código.
///
/// El Client ID de Android NO se escribe en ningún lado de este repo: solo
/// se registra en Google Cloud Console / Firebase.
library;

class GoogleAuthConfig {
  const GoogleAuthConfig._();

  /// **Web client ID** del proyecto de Google Cloud.
  ///
  /// Formato: `483335034495-xxxxxxxxxxxxxxxx.apps.googleusercontent.com`
  ///
  /// TODO(credenciales): pegar aquí el Web client ID. Es el MISMO valor que
  /// va en `backend/.env` → `GOOGLE_CLIENT_IDS` (ahí van los tres, separados
  /// por coma). Si no coinciden, el backend rechaza el token con
  /// GOOGLE_TOKEN_INVALIDO.
  static const String serverClientId =
      '483335034495-pi4d0putd9cq5d1elrad8kqls4ttlejv.apps.googleusercontent.com';

  /// **iOS client ID**. Dejar vacío mientras no se publique en iOS.
  ///
  /// TODO(credenciales): pegar aquí el iOS client ID (el mismo valor que el
  /// campo `CLIENT_ID` de `ios/Runner/GoogleService-Info.plist`).
  static const String iosClientId =
      '483335034495-n6hcca3lh9k2t50vfc16go5odt15ou27.apps.googleusercontent.com';

  /// ¿Hay credenciales suficientes para intentar el flujo de Google?
  ///
  /// Se comprueba en la app (además de en el servidor) para no mandar al
  /// usuario a una pantalla de Google que va a fallar con un error críptico
  /// de la plataforma: sin esto, en Android el SDK devuelve `canceled`, que
  /// es indistinguible de "el usuario cerró la ventana".
  static bool get estaConfigurado => serverClientId.isNotEmpty;

  /// El valor que espera `GoogleSignIn.initialize`, que quiere `null` (no
  /// cadena vacía) cuando no aplica.
  static String? get serverClientIdOrNull =>
      serverClientId.isEmpty ? null : serverClientId;

  static String? get iosClientIdOrNull =>
      iosClientId.isEmpty ? null : iosClientId;
}
