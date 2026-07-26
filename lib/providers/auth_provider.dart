import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/db_helper.dart';

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

  /// Sincroniza el usuario local con el backend:
  /// llama a POST /api/auth/register (idempotente), guarda el token JWT
  /// y el sellerId del backend.
  Future<void> _syncBackend() async {
    if (_currentUser == null) return;
    try {
      final result = await ApiService.registerBackendUser(
        name: _currentUser!['name'] as String,
        email: _currentUser!['email'] as String,
        userType: _currentUser!['user_type'] as String,
        phone: _currentUser!['phone'] as String?,
      );
      _backendToken = result['token'] as String;
      _backendSellerId = result['seller']['id'] as String;

      // Configurar el token en ApiService para futuros requests autenticados
      ApiService.setToken(_backendToken!);

      // Persistir token y sellerId
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backend_token', _backendToken!);
      await prefs.setString('backend_seller_id', _backendSellerId!);
    } catch (_) {
      // Si falla la sincronización, el usuario aún puede usar la app offline
      // pero deberá sincronizar después para publicar productos
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
  }) async {
    _loading = true;
    notifyListeners();

    try {
      final dbType = switch (userType) {
        AccountType.estudiante => 'estudiante',
        AccountType.particular => 'particular',
        AccountType.negocio => 'negocio',
      };

      final userId = await _db.registerUser(
        name: businessName ?? name,
        email: email,
        phone: phone,
        password: password,
        userType: dbType,
      );

      // Si es negocio, crear perfil de negocio inmediatamente
      if (userType == AccountType.negocio && businessType != null) {
        await _db.createBusinessProfile(
          userId: userId,
          businessName: businessName ?? name,
          businessType: businessType,
          responsibleName: responsibleName,
          businessDescription: businessDescription,
          logoPath: logoPath,
        );
      }

      // Auto-login después de registro
      final user = await _db.getUserById(userId);
      _currentUser = user;
      await _saveSession(userId);

      // Sincronizar con backend (crear vendedor y obtener JWT)
      await _syncBackend();

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
    if (userId == null) return false;

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

    // Sincronizar teléfono (y otros datos) con el backend en segundo plano
    _syncBackend();

    return true;
  }

  // ─── Login / Logout ────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _loading = true;
    notifyListeners();

    try {
      final user = await _db.login(email, password);
      if (user != null) {
        _currentUser = user;
        await _saveSession(user['id'] as int);

        // Sincronizar con backend (obtener JWT y sellerId)
        await _syncBackend();

        _loading = false;
        notifyListeners();
        return true;
      }
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _loading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
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

  /// Obtiene el perfil de negocio si aplica
  Future<Map<String, dynamic>?> getBusinessProfile() async {
    if (accountType != AccountType.negocio) return null;
    return await _db.getBusinessProfile(userId);
  }

  /// Asegura que exista un token de backend válido.
  /// Si no hay token, reintenta la sincronización con el backend.
  /// Devuelve `true` si hay token disponible después del intento.
  Future<bool> ensureBackendSync() async {
    if (_backendToken != null) return true;
    if (_currentUser == null) return false;
    try {
      await _syncBackend();
      return _backendToken != null;
    } catch (_) {
      return false;
    }
  }
}
