// db_helper.dart
// Base de datos local (SQLite) para Mercadito UM usando el paquete sqflite.
//
// Dependencias (en pubspec.yaml):
//   sqflite: ^2.3.0
//   path: ^1.9.0
//   bcrypt: ^1.2.0     // para hashear contraseñas

import 'package:bcrypt/bcrypt.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'mercadito_um.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Tabla principal de usuarios (aplica para los 3 tipos de cuenta)
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        phone TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        user_type TEXT NOT NULL CHECK(user_type IN ('estudiante', 'particular', 'negocio')),
        is_verified INTEGER NOT NULL DEFAULT 0,
        verification_status TEXT NOT NULL DEFAULT 'no_iniciada'
          CHECK(verification_status IN ('no_iniciada', 'pendiente', 'aprobada', 'rechazada')),
        profile_photo_path TEXT,
        rating REAL DEFAULT 0.0,
        total_ratings INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // Datos específicos de verificación de ESTUDIANTE
    await db.execute('''
      CREATE TABLE student_verification (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        matricula TEXT NOT NULL,
        carrera TEXT,
        credential_photo_path TEXT NOT NULL,
        submitted_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // Datos específicos de verificación de PARTICULAR (externo)
    await db.execute('''
      CREATE TABLE particular_verification (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        full_name_on_id TEXT NOT NULL,
        id_document_path TEXT NOT NULL,
        submitted_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // Perfil de NEGOCIO (puestos dentro o cerca del campus)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_profiles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        business_name TEXT NOT NULL,
        business_type TEXT NOT NULL, -- ej. 'comida', 'papeleria', 'servicios'
        responsible_name TEXT,
        business_description TEXT,
        logo_path TEXT,
        location_description TEXT,   -- ej. 'Puesto 4, patio central'
        schedule TEXT,               -- ej. 'Lun-Vie 8am-4pm'
        admin_confirmed INTEGER NOT NULL DEFAULT 0, -- verificación manual del admin, no documento
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE business_profiles ADD COLUMN responsible_name TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE business_profiles ADD COLUMN business_description TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE business_profiles ADD COLUMN logo_path TEXT');
      } catch (_) {}
    }
  }

  // ---------- Utilidad: hash de contraseña con bcrypt ----------
  String _hashPassword(String password) {
    return BCrypt.hashpw(password, BCrypt.gensalt());
  }

  // ---------- REGISTRO ----------

  /// Registra un usuario base. Devuelve el id generado.
  /// userType debe ser 'estudiante', 'particular' o 'negocio'.
  Future<int> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String userType,
  }) async {
    final db = await database;

    final existing = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
    if (existing.isNotEmpty) {
      throw Exception('Ya existe una cuenta con este correo.');
    }

    return await db.insert('users', {
      'name': name,
      'email': email,
      'phone': phone,
      'password_hash': _hashPassword(password),
      'user_type': userType,
      'is_verified': 0,
      'verification_status': 'no_iniciada',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Envía datos de verificación de ESTUDIANTE (queda pendiente de aprobación).
  Future<void> submitStudentVerification({
    required int userId,
    required String matricula,
    String? carrera,
    required String credentialPhotoPath,
  }) async {
    final db = await database;

    await db.insert('student_verification', {
      'user_id': userId,
      'matricula': matricula,
      'carrera': carrera,
      'credential_photo_path': credentialPhotoPath,
      'submitted_at': DateTime.now().toIso8601String(),
    });

    await db.update(
      'users',
      {'verification_status': 'pendiente'},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Envía datos de verificación de PARTICULAR (queda pendiente de aprobación).
  Future<void> submitParticularVerification({
    required int userId,
    required String fullNameOnId,
    required String idDocumentPath,
  }) async {
    final db = await database;

    await db.insert('particular_verification', {
      'user_id': userId,
      'full_name_on_id': fullNameOnId,
      'id_document_path': idDocumentPath,
      'submitted_at': DateTime.now().toIso8601String(),
    });

    await db.update(
      'users',
      {'verification_status': 'pendiente'},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// Crea el perfil de NEGOCIO. No requiere documento personal;
  /// admin_confirmed se actualiza manualmente por el admin más adelante.
  Future<void> createBusinessProfile({
    required int userId,
    required String businessName,
    required String businessType,
    String? responsibleName,
    String? businessDescription,
    String? logoPath,
    String? locationDescription,
    String? schedule,
  }) async {
    final db = await database;

    await db.insert('business_profiles', {
      'user_id': userId,
      'business_name': businessName,
      'business_type': businessType,
      'responsible_name': responsibleName,
      'business_description': businessDescription,
      'logo_path': logoPath,
      'location_description': locationDescription,
      'schedule': schedule,
      'admin_confirmed': 0,
    });

    await db.update(
      'users',
      {'verification_status': 'pendiente'},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  /// El usuario decide NO verificarse. Se queda como está, sin bloquear su cuenta.
  Future<void> skipVerification(int userId) async {
    final db = await database;
    await db.update(
      'users',
      {'verification_status': 'no_iniciada'},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // ---------- APROBACIÓN (uso del admin) ----------

  /// El admin aprueba o rechaza una verificación pendiente.
  Future<void> resolveVerification({
    required int userId,
    required bool approved,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {
        'is_verified': approved ? 1 : 0,
        'verification_status': approved ? 'aprobada' : 'rechazada',
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // ---------- LOGIN ----------

  Future<Map<String, dynamic>?> login(String email, String password) async {
    final db = await database;

    // Buscar usuario por correo
    final result = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (result.isEmpty) return null;

    final user = result.first;
    final storedHash = user['password_hash'] as String;

    // Verificar contraseña con bcrypt
    if (!BCrypt.checkpw(password, storedHash)) return null;

    return user;
  }

  // ---------- CONSULTAS ÚTILES ----------

  Future<Map<String, dynamic>?> getUserById(int userId) async {
    final db = await database;
    final result = await db.query('users', where: 'id = ?', whereArgs: [userId]);
    return result.isEmpty ? null : result.first;
  }

  /// Actualiza nombre y/o teléfono del usuario local, en sync con el backend.
  Future<void> updateUserFields(int userId, {String? name, String? phone}) async {
    final db = await database;
    final values = <String, dynamic>{};
    if (name != null) values['name'] = name;
    if (phone != null) values['phone'] = phone;
    if (values.isEmpty) return;
    await db.update(
      'users',
      values,
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingVerifications() async {
    final db = await database;
    return await db.query(
      'users',
      where: 'verification_status = ?',
      whereArgs: ['pendiente'],
    );
  }

  Future<Map<String, dynamic>?> getBusinessProfile(int userId) async {
    final db = await database;
    final result = await db.query(
      'business_profiles',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return result.isEmpty ? null : result.first;
  }
}
