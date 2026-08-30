import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/google_auth_config.dart';

/// El SDK de Google falló por algo que no es una cancelación del usuario.
///
/// Se separa de la cancelación a propósito: cancelar no es un error y no
/// debe pintar nada rojo en pantalla, mientras que esto sí necesita un
/// mensaje.
class GoogleSignInFallo implements Exception {
  GoogleSignInFallo(this.mensaje, {this.codigo});

  final String mensaje;
  final String? codigo;

  @override
  String toString() => 'GoogleSignInFallo($codigo): $mensaje';
}

/// Envoltura del plugin `google_sign_in`.
///
/// Su única responsabilidad es conseguir un **idToken** firmado por Google.
/// La app no decide nada de identidad con él: se lo manda al backend
/// (`POST /api/auth/google`), que es quien lo verifica contra las claves
/// públicas de Google y emite la sesión. Un idToken que no pasa por el
/// servidor no autentica a nadie.
class GoogleSignInService {
  const GoogleSignInService._();

  /// `initialize` solo puede llamarse una vez por proceso, así que se
  /// guarda el Future y se reutiliza. Si falla se borra, para que el
  /// siguiente intento pueda reintentar en vez de quedar atrapado en un
  /// Future ya completado con error.
  static Future<void>? _inicializacion;

  /// Permite que los tests sustituyan la obtención del idToken sin tocar el
  /// plugin (que necesita canales de plataforma y no corre en `flutter
  /// test`). En producción vale null y se usa el flujo real.
  @visibleForTesting
  static Future<String?> Function()? obtenerIdTokenDePrueba;

  @visibleForTesting
  static void restaurar() {
    obtenerIdTokenDePrueba = null;
    _inicializacion = null;
  }

  /// ¿La app tiene Client ID pegado? Ver [GoogleAuthConfig].
  static bool get estaConfigurado =>
      obtenerIdTokenDePrueba != null || GoogleAuthConfig.estaConfigurado;

  static Future<void> _asegurarInicializado() {
    return _inicializacion ??= GoogleSignIn.instance
        .initialize(
          // En Android va null: allí Google identifica a la app por
          // `applicationId` + SHA-1 registrados en la consola.
          clientId: GoogleAuthConfig.iosClientIdOrNull,
          // El `aud` del idToken que va a verificar el backend.
          serverClientId: GoogleAuthConfig.serverClientIdOrNull,
        )
        .catchError((Object e) {
          _inicializacion = null;
          throw GoogleSignInFallo('No se pudo inicializar Google Sign-In: $e');
        });
  }

  /// Abre la pantalla de Google y devuelve el idToken del usuario.
  ///
  /// Devuelve `null` si el usuario canceló — no es un error y quien llama
  /// debe limitarse a no hacer nada.
  ///
  /// Lanza [GoogleSignInFallo] si Google respondió con cualquier otro
  /// problema, o si faltan credenciales en [GoogleAuthConfig].
  static Future<String?> obtenerIdToken() async {
    final deTest = obtenerIdTokenDePrueba;
    if (deTest != null) return deTest();

    if (!GoogleAuthConfig.estaConfigurado) {
      throw GoogleSignInFallo(
        'Falta el Client ID de Google en lib/config/google_auth_config.dart.',
        codigo: 'SIN_CONFIGURAR',
      );
    }

    await _asegurarInicializado();

    // `authenticate()` no existe en la web (allí Google exige su propio
    // botón renderizado por el SDK). La app es móvil, pero se comprueba para
    // fallar con una frase entendible en vez de con un
    // UnsupportedError si algún día se compila a web.
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw GoogleSignInFallo(
        'Esta plataforma no soporta el inicio de sesión con Google.',
        codigo: 'NO_SOPORTADO',
      );
    }

    final GoogleSignInAccount cuenta;
    try {
      cuenta = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      // Ojo al depurar en Android: el SDK de Credential Manager también
      // devuelve `canceled` cuando la configuración está mal (SHA-1 sin
      // registrar, Client ID equivocado). Es indistinguible de que el
      // usuario cerrara la ventana — está documentado por el plugin.
      throw GoogleSignInFallo(
        e.description ?? 'Google rechazó el inicio de sesión.',
        codigo: e.code.name,
      );
    }

    final idToken = cuenta.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      // Pasa cuando `serverClientId` no es un Web client ID válido: Google
      // autentica al usuario pero no emite token para el servidor.
      throw GoogleSignInFallo(
        'Google no devolvió un idToken. Revisa el Web client ID '
        '(serverClientId) en lib/config/google_auth_config.dart.',
        codigo: 'SIN_ID_TOKEN',
      );
    }
    return idToken;
  }

  /// Cierra la sesión de Google en el dispositivo.
  ///
  /// Se llama al hacer logout para que el siguiente "Continuar con Google"
  /// vuelva a preguntar con qué cuenta entrar, en vez de reentrar solo con
  /// la última. Nunca propaga errores ni tarda: fallar aquí no puede impedir
  /// un logout.
  ///
  /// El tope de tiempo no es decorativo. `AuthProvider.logout()` se espera
  /// antes de navegar al login (ver `_cerrarSesionExpirada` en main.dart), y
  /// esto habla con un canal de plataforma: si el SDK de Google se quedara
  /// colgado, el usuario se quedaría atrapado en una sesión ya muerta sin
  /// poder salir. Que la sesión de Google siga abierta es un mal mucho menor.
  static Future<void> cerrarSesion() async {
    if (obtenerIdTokenDePrueba != null) return;
    if (!GoogleAuthConfig.estaConfigurado) return;
    try {
      await _asegurarInicializado()
          .then((_) => GoogleSignIn.instance.signOut())
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Silencio deliberado: ver doc arriba.
    }
  }
}
