import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../models/verification_requirement.dart';
import '../services/anonymous_id.dart';
import '../services/anon_session.dart';
import '../services/api_service.dart';
import '../services/chat_socket_service.dart';
import '../services/db_helper.dart';
import '../services/google_sign_in_service.dart';
import '../services/push_service.dart';

enum AccountType { estudiante, particular, negocio }

/// Desenlace de pulsar "Continuar con Google".
///
/// Es un tipo cerrado (y no un bool o un enum suelto) porque los tres casos
/// llevan a pantallas distintas y uno de ellos arrastra datos: la pantalla
/// que llama tiene que tratarlos todos, y el compilador se lo recuerda.
sealed class ResultadoGoogle {
  const ResultadoGoogle();
}

/// El usuario ya tenía cuenta: la sesión quedó iniciada, igual que con
/// correo y contraseña. Toca navegar al shell principal.
class GoogleSesionIniciada extends ResultadoGoogle {
  const GoogleSesionIniciada();
}

/// El usuario cerró la ventana de Google. No hay nada que hacer ni nada
/// que mostrar — no es un error.
class GoogleCancelado extends ResultadoGoogle {
  const GoogleCancelado();
}

/// La cuenta de Google es válida pero no existe en el marketplace: hay que
/// completar el registro. Lleva lo que Google sí sabe (para prellenar el
/// formulario) y el [idToken], que es lo que prueba ante el backend que ese
/// correo es de quien dice.
class GoogleRegistroPendiente extends ResultadoGoogle {
  const GoogleRegistroPendiente({
    required this.idToken,
    required this.email,
    required this.nombre,
    this.foto,
  });

  final String idToken;
  final String email;
  final String nombre;
  final String? foto;
}

/// Tipos de negocio permitidos
const businessTypes = [
  'Comida',
  'Papelería',
  'Servicios',
  'Ropa',
  'Electrónicos',
  'Otro',
];

/// Extensión para convertir strings de la DB a enums
extension UserTypeParse on String {
  AccountType? get toAccountType {
    switch (this) {
      case 'estudiante':
        return AccountType.estudiante;
      case 'particular':
        return AccountType.particular;
      case 'negocio':
        return AccountType.negocio;
      default:
        return null;
    }
  }
}

/// Provider de autenticación que gestiona la sesión local del usuario.
class AuthProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper();

  Map<String, dynamic>? _currentUser;
  bool _loading = false;

  // ─── Sincronización con backend ─────────────────────────────
  String? _backendToken;
  String? _backendSellerId;

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _loading;
  String? get backendToken => _backendToken;
  String? get backendSellerId => _backendSellerId;

  int get userId => _currentUser!['id'] as int;

  /// Tipo de cuenta. Se prefiere el que reporta el backend (columna
  /// `sellers.tipo_cuenta`, la fuente canónica) sobre el de la caché local,
  /// que al iniciar sesión en un dispositivo nuevo se deduce de isBusiness y
  /// major y puede quedar mal.
  AccountType get accountType =>
      _tipoCuentaBackend?.toAccountType ??
      (_currentUser!['user_type'] as String).toAccountType!;

  // ─── Estado de verificación (autoridad: backend) ───────────
  //
  // Antes esto vivía en la caché local de sqflite (`is_verified`), donde solo
  // podía cambiarlo un admin que nunca existió. Ahora lo resuelve el backend
  // automáticamente y aquí solo se refleja.

  bool _verificado = false;
  String _estadoVerificacion = 'pendiente';
  String? _tipoCuentaBackend;
  String? _motivoRechazo;
  String? _campoRechazado;
  bool _identidadConfirmada = false;
  int _puedeReintentarEn = 0;
  List<VerificationRequirement> _requisitos = const [];

  /// Checklist de verificación tal como lo evalúa el backend. La app lo
  /// pinta, no lo calcula: ver [VerificationRequirement].
  List<VerificationRequirement> get requisitos => _requisitos;

  /// Requisitos que todavía no se cumplen.
  List<VerificationRequirement> get requisitosPendientes =>
      _requisitos.where((r) => !r.cumplido).toList();

  bool get isVerified => _verificado;
  String get estadoVerificacion => _estadoVerificacion;

  /// Mensaje del backend explicando por qué la verificación no se completó.
  String? get motivoRechazo => _motivoRechazo;

  /// Campo concreto que hay que corregir. 'mercadopago' significa que lo
  /// único que falta es conectar la cuenta de cobros.
  String? get campoRechazado => _campoRechazado;

  /// El OTP ya se confirmó (o el negocio ya pasó la comprobación del link).
  /// Junto con [campoRechazado] == 'mercadopago' es lo que permite retomar la
  /// verificación en el paso de conectar en vez de empezar de cero.
  bool get identidadConfirmada => _identidadConfirmada;

  /// Solo falta conectar la cuenta de cobros para quedar verificado.
  bool get soloFaltaConectarCobros =>
      !_verificado && _identidadConfirmada && _campoRechazado == 'mercadopago';

  /// Minutos que faltan para poder pedir otro código, o 0 si puede pedirlo ya.
  int get puedeReintentarEn => _puedeReintentarEn;

  /// Label que describe el tipo de cuenta
  String get accountTypeLabel {
    switch (accountType) {
      case AccountType.estudiante:
        return 'Estudiante';
      case AccountType.particular:
        return 'Particular';
      case AccountType.negocio:
        return 'Negocio';
    }
  }

  // ─── Sincronización con backend ────────────────────────────
  //
  // El backend es la autoridad real de credenciales (email + password real,
  // verificado con bcrypt server-side). El SQLite local (DBHelper) es solo
  // una caché offline y el lugar donde vive accountType/verificationStatus
  // (eso último todavía no se sincroniza al backend). Antes, el login
  // verificaba el password SOLO contra esta caché local, así que una cuenta
  // registrada en otro dispositivo/instalación nunca podía loguearse aquí
  // aunque el password fuera el correcto — ver AuthProvider.login.

  /// Aplica el resultado de POST /api/auth/register o /api/auth/login:
  /// guarda el token JWT y el sellerId, y los persiste para la próxima vez
  /// que se abra la app (ver tryAutoLogin).
  Future<void> _applyBackendAuthResult(Map<String, dynamic> result) async {
    _backendToken = result['token'] as String;
    _backendSellerId = result['seller']['id'] as String;
    ApiService.setToken(_backendToken!);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_token', _backendToken!);
    await prefs.setString('backend_seller_id', _backendSellerId!);

    await _registerPushDevice();
  }

  /// Refleja localmente una cuenta ya autenticada por el backend: si el
  /// email no existe en este dispositivo (p. ej. login desde una
  /// instalación nueva) crea la fila; si existe, actualiza su hash de
  /// password para que el login local siga funcionando en este mismo
  /// dispositivo. Deja `_currentUser` listo con los campos que solo viven
  /// localmente (accountType, verificationStatus).
  ///
  /// [password] llega en null cuando la sesión la abrió Google: esas cuentas
  /// no tienen contraseña. Entonces NO se toca el hash de una fila que ya
  /// existía — sería borrarle la contraseña real a quien sí la tenga — y una
  /// fila nueva se crea con un secreto aleatorio que nadie conoce ni
  /// necesita: la tabla local exige un hash, pero desde hace tiempo el login
  /// se valida siempre contra el backend, nunca contra este hash.
  Future<void> _mirrorLocalUser({
    required String name,
    required String email,
    required String phone,
    required String? password,
    required String dbType,
  }) async {
    final existing = await _db.getUserByEmail(email);
    if (existing != null) {
      if (password != null) {
        await _db.updatePasswordHash(existing['id'] as int, password);
      }
      if (phone.isNotEmpty && phone != existing['phone']) {
        await _db.updateUserFields(existing['id'] as int, phone: phone);
      }
      _currentUser = await _db.getUserById(existing['id'] as int);
    } else {
      final userId = await _db.registerUser(
        name: name,
        email: email,
        phone: phone,
        password: password ?? _secretoLocalAleatorio(),
        userType: dbType,
      );
      _currentUser = await _db.getUserById(userId);
    }
  }

  /// Contraseña de relleno para la fila local de una cuenta de Google.
  /// `Random.secure()` y no `Random()`: no hace falta que nadie la adivine,
  /// pero tampoco cuesta nada que sea imposible.
  static String _secretoLocalAleatorio() {
    final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
    return base64Url.encode(bytes);
  }

  // ─── Google Sign-In ────────────────────────────────────────
  //
  // El flujo tiene dos pasos porque un idToken de Google trae correo, nombre
  // y foto, y el registro de este marketplace exige además tipo de cuenta,
  // teléfono y método de pago. Así que:
  //
  //   1. [signInWithGoogle] consigue el idToken y se lo manda al backend.
  //      Si la cuenta ya existe, la sesión queda abierta y aquí se acaba.
  //   2. Si no existe, devuelve [GoogleRegistroPendiente] y la pantalla
  //      lleva al formulario de registro normal, prellenado. Al enviarlo se
  //      llama a [registrarConGoogle] con el mismo idToken.
  //
  // Lo que pasa DESPUÉS de autenticarse (guardar token, espejo local,
  // sesión, estado de verificación) es exactamente el mismo código que usa
  // el login por correo: [_aplicarSesionBackend].

  /// Pasos comunes a login y registro, con o sin Google: guarda el JWT,
  /// refleja la cuenta en la caché local, persiste la sesión y lee el estado
  /// de verificación.
  ///
  /// [email] existe para el login por correo, que ya lo tiene tecleado; sin
  /// él se usa el que devuelve el backend.
  Future<void> _aplicarSesionBackend(
    Map<String, dynamic> result, {
    required String? password,
    String? email,
  }) async {
    await _applyBackendAuthResult(result);

    final seller = result['seller'] as Map<String, dynamic>;
    final dbType = (seller['isBusiness'] as bool? ?? false)
        ? 'negocio'
        : (seller['major'] == 'Estudiante' ? 'estudiante' : 'particular');
    await _mirrorLocalUser(
      name: seller['name'] as String? ?? '',
      email: email ?? seller['email'] as String? ?? '',
      phone: seller['phone'] as String? ?? '',
      password: password,
      dbType: dbType,
    );
    await _saveSession(_currentUser!['id'] as int);
    await refrescarEstadoVerificacion();
  }

  /// Abre el flujo de Google y, según lo que conteste el backend, deja la
  /// sesión iniciada o pide completar el registro. Ver [ResultadoGoogle].
  ///
  /// Lanza [GoogleSignInFallo] (problema del SDK de Google) o
  /// [GoogleAuthException] (rechazo del backend) — la pantalla los pinta
  /// como mensaje; una cancelación NO es ninguna de las dos cosas y llega
  /// como [GoogleCancelado].
  Future<ResultadoGoogle> signInWithGoogle() async {
    _loading = true;
    notifyListeners();

    try {
      final idToken = await GoogleSignInService.obtenerIdToken();
      if (idToken == null) return const GoogleCancelado();

      final deviceId = await AnonymousId.get();
      try {
        final result = await ApiService.authGoogle(
          idToken: idToken,
          deviceId: deviceId,
        );
        await _aplicarSesionBackend(result, password: null);
        return const GoogleSesionIniciada();
      } on GoogleRegistroRequeridoException catch (e) {
        return GoogleRegistroPendiente(
          idToken: idToken,
          email: e.email,
          nombre: e.nombre,
          foto: e.foto,
        );
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Segundo paso: crea la cuenta con los datos del formulario + el idToken.
  ///
  /// El correo NO viaja: el backend lo saca del idToken, que es la única
  /// fuente en la que puede confiar. Devuelve el id local, igual que
  /// [registerUser].
  Future<int> registrarConGoogle({
    required String idToken,
    required String name,
    required String phone,
    required AccountType userType,
    required List<String> paymentMethods,
    String? businessName,
    String? businessType,
    String? responsibleName,
    String? businessDescription,
    String? logoPath,
    Map<int, BusinessHoursRange>? businessHours,
  }) async {
    _loading = true;
    notifyListeners();

    try {
      final dbType = switch (userType) {
        AccountType.estudiante => 'estudiante',
        AccountType.particular => 'particular',
        AccountType.negocio => 'negocio',
      };
      final effectiveName = businessName ?? name;

      final registro = <String, dynamic>{
        'name': effectiveName,
        'userType': dbType,
        'phone': phone,
        'paymentMethods': paymentMethods,
        if (businessHours != null)
          'businessHours': businessHoursToJson(businessHours),
      };

      final deviceId = await AnonymousId.get();
      Map<String, dynamic> result;
      try {
        result = await ApiService.authGoogle(
          idToken: idToken,
          deviceId: deviceId,
          registro: registro,
        );
      } on GoogleAuthException catch (e) {
        // Los idToken de Google duran ~1 hora. Si el usuario tardó más en
        // llenar el formulario que lo que vivió el token, se pide otro en
        // silencio en vez de tirarle el registro a la basura. Solo se
        // reintenta una vez, y solo por token caducado.
        if (!e.tokenInvalido) rethrow;
        final nuevo = await GoogleSignInService.obtenerIdToken();
        if (nuevo == null) rethrow;
        result = await ApiService.authGoogle(
          idToken: nuevo,
          deviceId: deviceId,
          registro: registro,
        );
      }

      await _aplicarSesionBackend(result, password: null);

      // Mismos remates que el registro por correo: rubro/descripción viven
      // en el backend (los lee "Editar perfil") y el perfil de negocio local
      // guarda el logo y el responsable.
      if (userType == AccountType.negocio &&
          (businessDescription != null || businessType != null)) {
        try {
          await ApiService.updateSellerProfile(
            sellerId: _backendSellerId!,
            businessDescription: businessDescription,
            businessCategory: businessType,
          );
        } catch (_) {
          // No bloquea el registro: se puede completar desde el perfil.
        }
      }

      final userId = _currentUser!['id'] as int;
      if (userType == AccountType.negocio && businessType != null) {
        await _db.createBusinessProfile(
          userId: userId,
          businessName: effectiveName,
          businessType: businessType,
          responsibleName: responsibleName,
          businessDescription: businessDescription,
          logoPath: logoPath,
        );
        _currentUser = await _db.getUserById(userId);
      }

      return userId;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─── Registro ──────────────────────────────────────────────

  Future<int> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    required AccountType userType,
    // Campos específicos para negocio
    String? businessName,
    String? businessType,
    String? responsibleName,
    String? businessDescription,
    String? logoPath,
    Map<int, BusinessHoursRange>? businessHours,
    required List<String> paymentMethods,
  }) async {
    _loading = true;
    notifyListeners();

    try {
      final dbType = switch (userType) {
        AccountType.estudiante => 'estudiante',
        AccountType.particular => 'particular',
        AccountType.negocio => 'negocio',
      };
      final effectiveName = businessName ?? name;

      // El backend valida/crea la cuenta primero (con el password real).
      // Si el email ya existe en el backend con OTRO password, esto lanza
      // una excepción con el mensaje real del servidor (409) — no se
      // silencia como antes.
      final deviceId = await AnonymousId.get();
      final result = await ApiService.registerBackendUser(
        name: effectiveName,
        email: email,
        userType: dbType,
        password: password,
        phone: phone,
        deviceId: deviceId,
        businessHours: businessHours,
        paymentMethods: paymentMethods,
      );
      await _applyBackendAuthResult(result);

      // Sincronizar descripción/rubro del negocio con el backend: son los
      // mismos campos que EditProfileScreen lee de ahí (GET /api/sellers/:id).
      // Sin este paso quedaban solo en la caché local (_db.createBusinessProfile
      // abajo) y "Editar perfil" los mostraba vacíos aunque el usuario ya los
      // hubiera capturado aquí durante el registro.
      if (userType == AccountType.negocio &&
          (businessDescription != null || businessType != null)) {
        try {
          await ApiService.updateSellerProfile(
            sellerId: _backendSellerId!,
            businessDescription: businessDescription,
            businessCategory: businessType,
          );
        } catch (_) {
          // No bloquea el registro: el usuario podrá completarlos después
          // desde "Editar perfil".
        }
      }

      // Espejo local (caché offline + accountType/verificationStatus)
      await _mirrorLocalUser(
        name: effectiveName,
        email: email,
        phone: phone,
        password: password,
        dbType: dbType,
      );
      final userId = _currentUser!['id'] as int;
      await _saveSession(userId);

      // Si es negocio, crear perfil de negocio inmediatamente
      if (userType == AccountType.negocio && businessType != null) {
        await _db.createBusinessProfile(
          userId: userId,
          businessName: effectiveName,
          businessType: businessType,
          responsibleName: responsibleName,
          businessDescription: businessDescription,
          logoPath: logoPath,
        );
        _currentUser = await _db.getUserById(userId);
      }

      // Deja el estado listo para la pantalla de verificación que viene a
      // continuación en el registro.
      await refrescarEstadoVerificacion();

      return userId;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─── Verificación ──────────────────────────────────────────

  /// Relee el estado de verificación desde el backend. Es la única forma de
  /// enterarse de que la cuenta quedó verificada (o rechazada), porque la
  /// decisión la toma el servidor.
  Future<void> refrescarEstadoVerificacion() async {
    if (_backendToken == null) return;
    try {
      final estado = await ApiService.getEstadoVerificacion();
      _aplicarEstadoVerificacion(estado);
      notifyListeners();
    } catch (_) {
      // Sin conexión se conserva el último estado conocido: no poder
      // confirmar la verificación no es motivo para quitarle la insignia a
      // alguien que sí está verificado.
    }
  }

  void _aplicarEstadoVerificacion(Map<String, dynamic> estado) {
    _verificado = estado['verificado'] as bool? ?? false;
    _estadoVerificacion = estado['estado'] as String? ?? 'pendiente';
    _tipoCuentaBackend = estado['tipo_cuenta'] as String?;
    _motivoRechazo = estado['motivo_rechazo'] as String?;
    _campoRechazado = estado['campo_rechazado'] as String?;
    _identidadConfirmada = estado['identidad_confirmada'] as bool? ?? false;
    _puedeReintentarEn = (estado['puede_reintentar_en'] as num?)?.toInt() ?? 0;
    final requisitos = VerificationRequirement.listaDeJson(
      estado['requisitos'],
    );
    // Una respuesta sin `requisitos` (backend viejo) conserva la última lista
    // conocida en vez de vaciar el checklist: pintar cero requisitos se
    // leería como "no falta nada", que es justo lo contrario.
    if (requisitos.isNotEmpty) _requisitos = requisitos;
  }

  /// Envía el código OTP al correo institucional del estudiante.
  /// Devuelve el código cuando el backend corre en modo dev (sin proveedor
  /// SMTP configurado), para poder probar el flujo sin recibir el correo.
  Future<String?> solicitarVerificacionEstudiante({
    required String correoInstitucional,
    required String tipo,
    String? carrera,
  }) async {
    final res = await ApiService.solicitarVerificacionEstudiante(
      correoInstitucional: correoInstitucional,
      tipo: tipo,
      carrera: carrera,
    );
    return res['codigo_dev'] as String?;
  }

  /// Confirma el código del estudiante. Devuelve true si la cuenta quedó
  /// verificada.
  ///
  /// Un false NO significa que el código estuviera mal (eso llega como
  /// excepción): significa que el código era correcto y falta un requisito,
  /// hoy siempre conectar la cuenta de cobros. El motivo queda en
  /// [motivoRechazo] / [campoRechazado].
  Future<bool> confirmarVerificacionEstudiante(String codigo) async {
    final res = await ApiService.confirmarVerificacionEstudiante(codigo);
    await refrescarEstadoVerificacion();
    return res['verificado'] == true;
  }

  /// Verifica un negocio en una sola llamada. Devuelve true si quedó
  /// verificado; si fue rechazado devuelve false y deja el motivo y el campo
  /// a corregir en [motivoRechazo] / [campoRechazado].
  Future<bool> verificarNegocio({
    required String nombreNegocio,
    required double lat,
    required double lng,
    required String linkRedSocial,
  }) async {
    final res = await ApiService.verificarNegocio(
      nombreNegocio: nombreNegocio,
      lat: lat,
      lng: lng,
      linkRedSocial: linkRedSocial,
    );
    await refrescarEstadoVerificacion();
    return res['estado'] == 'verificado';
  }

  Future<String?> solicitarVerificacionExterno(String telefono) async {
    final res = await ApiService.solicitarVerificacionExterno(telefono);
    return res['codigo_dev'] as String?;
  }

  /// Igual que [confirmarVerificacionEstudiante], por SMS.
  Future<bool> confirmarVerificacionExterno(String codigo) async {
    final res = await ApiService.confirmarVerificacionExterno(codigo);
    await refrescarEstadoVerificacion();
    return res['verificado'] == true;
  }

  Future<void> createBusinessProfile({
    required String businessName,
    required String businessType,
    String? responsibleName,
    String? businessDescription,
    String? logoPath,
    String? locationDescription,
    String? schedule,
  }) async {
    await _db.createBusinessProfile(
      userId: userId,
      businessName: businessName,
      businessType: businessType,
      responsibleName: responsibleName,
      businessDescription: businessDescription,
      logoPath: logoPath,
      locationDescription: locationDescription,
      schedule: schedule,
    );
    notifyListeners();
  }

  // ─── Persistencia de sesión ────────────────────────────────

  static const _sessionKey = 'logged_user_id';

  Future<void> _saveSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey, userId);
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove('backend_token');
    await prefs.remove('backend_seller_id');
  }

  /// Intenta restaurar la sesión desde shared_preferences.
  /// Devuelve true si se pudo restaurar.
  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_sessionKey);
    if (userId == null) {
      // Usuario anónimo: registrar su token FCM para poder recibir pushes sin login
      _registerAnonymousPushDevice();
      return false;
    }

    final user = await _db.getUserById(userId);
    if (user == null) {
      // El usuario fue eliminado de la DB — limpiar sesión
      await _clearSession();
      return false;
    }

    _currentUser = user;

    // Restaurar token de backend si existe
    _backendToken = prefs.getString('backend_token');
    _backendSellerId = prefs.getString('backend_seller_id');
    if (_backendToken != null) {
      ApiService.setToken(_backendToken!);
    }

    notifyListeners();

    // El token ya se restauró de SharedPreferences arriba — solo falta
    // re-registrar el device de push, no hay nada que re-sincronizar contra
    // el backend (no hay password disponible para eso, y no hace falta).
    if (_backendSellerId != null) {
      _registerPushDevice();
      // No se espera: la insignia aparece en cuanto responda, sin retrasar
      // el arranque de la app.
      refrescarEstadoVerificacion();
    }

    return true;
  }

  // ─── Login / Logout ────────────────────────────────────────

  /// Autentica contra el backend (única autoridad real de credenciales) y,
  /// si es correcto, refleja la cuenta en la caché local de este
  /// dispositivo. Así una cuenta registrada en otro dispositivo/instalación
  /// puede loguearse aquí con el mismo email/password.
  Future<bool> login(String email, String password) async {
    _loading = true;
    notifyListeners();

    try {
      final deviceId = await AnonymousId.get();
      final result = await ApiService.loginBackend(
        email: email,
        password: password,
        deviceId: deviceId,
      );
      if (result == null) {
        // Credenciales incorrectas (401 real del backend)
        return false;
      }

      // Los mismos pasos que corre el inicio de sesión con Google — una sola
      // definición de "qué pasa después de autenticarse".
      await _aplicarSesionBackend(result, password: password, email: email);

      return true;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    // Desregistrar solo el token de ESTE dispositivo en el backend
    // (No usa unregisterAllDevices para no apagar push en otros dispositivos
    //  donde el usuario tenga sesión activa)
    try {
      await PushService.instance.unregisterDevice();
    } catch (_) {}

    // Sin esto, el siguiente "Continuar con Google" reentraría solo con la
    // última cuenta usada, sin preguntar — que es justo lo que alguien no
    // espera después de cerrar sesión (p. ej. en un teléfono prestado).
    try {
      await GoogleSignInService.cerrarSesion();
    } catch (_) {}

    _currentUser = null;
    _backendToken = null;
    _backendSellerId = null;
    _verificado = false;
    _estadoVerificacion = 'pendiente';
    _tipoCuentaBackend = null;
    _motivoRechazo = null;
    _campoRechazado = null;
    _puedeReintentarEn = 0;
    // Volver a ser invitado, no quedarse sin identidad: si no, el chat
    // dejaría de funcionar tras cerrar sesión hasta reiniciar la app.
    // Sustituye al `clearToken()` a secas — `restaurarTrasLogout` lo hace y
    // acto seguido deja puesto el token de invitado.
    try {
      await AnonSession.restaurarTrasLogout();
    } catch (_) {
      ApiService.clearToken();
    }
    // Cerrar el socket marca al usuario como desconectado del lado del
    // servidor en el acto, y `forgetUser` evita que una reconexión lo vuelva
    // a encender con las credenciales de la sesión que acaba de terminar.
    ChatSocketService.instance.forgetUser();
    ChatSocketService.instance.disconnect();
    await _clearSession();
    notifyListeners();
  }

  /// Recarga el usuario actual desde la DB (útil después de aprobación admin)
  Future<void> refreshUser() async {
    if (_currentUser == null) return;
    final user = await _db.getUserById(_currentUser!['id'] as int);
    _currentUser = user;
    notifyListeners();
  }

  /// Edita nombre, teléfono y/o foto de perfil, sincronizando backend y DB local.
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? logoPath,
    String? businessDescription,
    String? businessCategory,
    Map<int, BusinessHoursRange>? businessHours,
    double? locationLat,
    double? locationLng,
    List<String>? paymentMethods,
    String? facebookUrl,
    String? instagramUrl,
    String? whatsappNumber,
    String? tiktokUrl,
    String? twitterUrl,
  }) async {
    if (logoPath != null && _backendSellerId != null) {
      await ApiService.uploadBusinessLogo(
        sellerId: _backendSellerId!,
        imagePath: logoPath,
      );
    }
    final hasProfileFields =
        name != null ||
        phone != null ||
        businessDescription != null ||
        businessCategory != null ||
        businessHours != null ||
        (locationLat != null && locationLng != null) ||
        paymentMethods != null ||
        facebookUrl != null ||
        instagramUrl != null ||
        whatsappNumber != null ||
        tiktokUrl != null ||
        twitterUrl != null;
    if (hasProfileFields && _backendSellerId != null) {
      await ApiService.updateSellerProfile(
        sellerId: _backendSellerId!,
        name: name,
        phone: phone,
        businessDescription: businessDescription,
        businessCategory: businessCategory,
        businessHours: businessHours,
        locationLat: locationLat,
        locationLng: locationLng,
        paymentMethods: paymentMethods,
        facebookUrl: facebookUrl,
        instagramUrl: instagramUrl,
        whatsappNumber: whatsappNumber,
        tiktokUrl: tiktokUrl,
        twitterUrl: twitterUrl,
      );
    }
    if (name != null || phone != null) {
      await _db.updateUserFields(userId, name: name, phone: phone);
      if (name != null) _currentUser!['name'] = name;
      if (phone != null) _currentUser!['phone'] = phone;
    }
    notifyListeners();
  }

  /// Obtiene el perfil de negocio si aplica
  Future<Map<String, dynamic>?> getBusinessProfile() async {
    if (accountType != AccountType.negocio) return null;
    return await _db.getBusinessProfile(userId);
  }

  /// Registra el dispositivo para notificaciones push.
  /// Envía el FCM token actual al backend para que el usuario reciba notificaciones.
  Future<void> _registerPushDevice() async {
    if (_backendSellerId == null) return;
    try {
      await PushService.instance.registerDevice();
    } catch (_) {}
  }

  /// Registra el token FCM usando el ID anónimo del dispositivo (sin login).
  Future<void> _registerAnonymousPushDevice() async {
    try {
      final anonymousId = await AnonymousId.get();
      if (anonymousId.isNotEmpty) {
        await PushService.instance.registerAnonymousDevice(anonymousId);
      }
    } catch (_) {}
  }

  /// Verifica que exista un token de backend válido para poder publicar.
  /// Ya no se puede "reintentar" un re-registro sin password (el backend
  /// ya no acepta re-sincronizar credenciales sin verificarlas) — si no hay
  /// token, la cuenta quedó sin sincronizar (p. ej. una cuenta local previa
  /// a este fix) y hay que volver a iniciar sesión para obtener uno real.
  Future<bool> ensureBackendSync() async {
    return _backendToken != null;
  }
}
