import 'package:flutter/foundation.dart';
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

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isLoading => _loading;

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

  // ─── Registro ──────────────────────────────────────────────

  Future<int> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    required AccountType userType,
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
        name: name,
        email: email,
        phone: phone,
        password: password,
        userType: dbType,
      );

      // Auto-login después de registro
      final user = await _db.getUserById(userId);
      _currentUser = user;
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
    String? locationDescription,
    String? schedule,
  }) async {
    await _db.createBusinessProfile(
      userId: userId,
      businessName: businessName,
      businessType: businessType,
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

  // ─── Login / Logout ────────────────────────────────────────

  Future<bool> login(String email, String password) async {
    _loading = true;
    notifyListeners();

    try {
      final user = await _db.login(email, password);
      if (user != null) {
        _currentUser = user;
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

  void logout() {
    _currentUser = null;
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
}
