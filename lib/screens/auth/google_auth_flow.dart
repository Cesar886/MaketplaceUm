import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/accent_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/google_sign_in_service.dart';
import '../../main.dart' show abrirInicio;
import 'register_type_screen.dart';

/// Lo que hace el botón "Continuar con Google", desde cualquier pantalla.
///
/// Vive aquí y no en cada pantalla porque el botón aparece en dos (login y
/// registro) y hace lo mismo en las dos: si la cuenta existe entra, y si no
/// lleva a completar el registro. Duplicarlo era garantizar que un día
/// dejaran de comportarse igual.
///
/// No devuelve nada: navega o muestra el error por su cuenta.
Future<void> continuarConGoogle(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  final navegador = Navigator.of(context);
  final mensajero = ScaffoldMessenger.of(context);
  final accent = context.read<AccentProvider>();

  ResultadoGoogle resultado;
  try {
    resultado = await auth.signInWithGoogle();
  } on GoogleSignInFallo catch (e) {
    // Falló el SDK de Google en el dispositivo (configuración incompleta,
    // Play Services, sin red…). El detalle real —que nombra archivos y
    // claves del proyecto— solo se enseña en depuración: es justo lo que
    // hace falta mientras se terminan de pegar las credenciales, y justo lo
    // que no tiene por qué leer un usuario en producción.
    debugPrint('[google] $e');
    mensajero.showSnackBar(
      SnackBar(
        content: Text(kDebugMode ? e.mensaje : 'auth.google_failed'.tr()),
      ),
    );
    return;
  } on GoogleAuthException catch (e) {
    mensajero.showSnackBar(
      SnackBar(
        content: Text(
          e.faltaConfigurar ? 'auth.google_unavailable'.tr() : e.mensaje,
        ),
      ),
    );
    return;
  } catch (_) {
    mensajero.showSnackBar(SnackBar(content: Text('auth.google_failed'.tr())));
    return;
  }

  switch (resultado) {
    case GoogleCancelado():
      // El usuario cerró la ventana de Google. No es un error: no se pinta
      // nada y se queda donde estaba.
      return;

    case GoogleSesionIniciada():
      // Mismo remate que el login por correo: el color de acento lo manda el
      // servidor, no lo que dejó la sesión anterior en este teléfono.
      final sellerId = auth.backendSellerId;
      if (sellerId != null) accent.sincronizarDesdeBackend(sellerId);
      abrirInicio(navegador, sesionRecienIniciada: true);

    case final GoogleRegistroPendiente pendiente:
      // Google confirmó quién es, pero falta lo que un idToken no puede
      // traer: tipo de cuenta, teléfono y métodos de pago. Va al mismo
      // registro de siempre, ya prellenado y sin pedir contraseña.
      navegador.push(
        MaterialPageRoute<void>(
          builder: (_) => RegisterTypeScreen(google: pendiente),
        ),
      );
  }
}
