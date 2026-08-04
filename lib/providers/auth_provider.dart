import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';
import '../services/anonymous_id.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';
import '../services/push_service.dart';

enum AccountType { estudiante, particular, negocio }

enum VerificationStatus { noIniciada, pendiente, aprobada, rechazada }

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

  VerificationStatus get toVerificationStatus {
    switch (this) {
      case 'pendiente':
        return VerificationStatus.pendiente;
      case 'aprobada':
        return VerificationStatus.aprobada;
      case 'rechazada':
        return VerificationStatus.rechazada;
      default:
        return VerificationStatus.noIniciada;
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
  AccountType get accountType =>
      (_currentUser!['user_type'] as String).toAccountType!;
  VerificationStatus get verificationStatus =>
      (_currentUser!['verification_status'] as String).toVerificationStatus;
  bool get isVerified => _currentUser!['is_verified'] == 1;

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
  Future<void> _mirrorLocalUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String dbType,
  }) async {
    final existing = await _db.getUserByEmail(email);
    if (existing != null) {
      await _db.updatePasswordHash(existing['id'] as int, password);
      if (phone.isNotEmpty && phone != existing['phone']) {
        await _db.updateUserFields(existing['id'] as int, phone: phone);
      }
      _currentUser = await _db.getUserById(existing['id'] as int);
    } else {
      final userId = await _db.registerUser(
        name: name,
        email: email,
        phone: phone,
        password: password,
        userType: dbType,
      );
      _currentUser = await _db.getUserById(userId);
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

      return userId;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─── Verificación ──────────────────────────────────────────

  Future<void> submitStudentVerification({
    required String matricula,
    String? carrera,
    required String credentialPhotoPath,
  }) async {
    await _db.submitStudentVerification(
      userId: userId,
      matricula: matricula,
      carrera: carrera,
      credentialPhotoPath: credentialPhotoPath,
    );
    _currentUser!['verification_status'] = 'pendiente';
    notifyListeners();
  }

  Future<void> submitParticularVerification({
    required String fullNameOnId,
    required String idDocumentPath,
  }) async {
    await _db.submitParticularVerification(
      userId: userId,
      fullNameOnId: fullNameOnId,
      idDocumentPath: idDocumentPath,
    );
    _currentUser!['verification_status'] = 'pendiente';
    notifyListeners();
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
    _currentUser!['verification_status'] = 'pendiente';
    notifyListeners();
  }

  Future<void> skipVerification() async {
    await _db.skipVerification(userId);
    _currentUser!['verification_status'] = 'no_iniciada';
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

      await _applyBackendAuthResult(result);

      final seller = result['seller'] as Map<String, dynamic>;
      final dbType = (seller['isBusiness'] as bool? ?? false)
          ? 'negocio'
          : (seller['major'] == 'Estudiante' ? 'estudiante' : 'particular');
      await _mirrorLocalUser(
        name: seller['name'] as String? ?? '',
        email: email,
        phone: seller['phone'] as String? ?? '',
        password: password,
        dbType: dbType,
      );
      await _saveSession(_currentUser!['id'] as int);

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

    _currentUser = null;
    _backendToken = null;
    _backendSellerId = null;
    ApiService.clearToken();
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
        paymentMethods != null;
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
