import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'fcm/android_notification_channel.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// PushService — Notificaciones push
//
// Soporte actual:  ✅ Android FCM
// Planeado:        ⏳ iOS APNs (vía Firebase Cloud Messaging también)
//
// Cada sección específica de plataforma está aislada en su propio archivo
// dentro de lib/services/fcm/ o (futuro) lib/services/apns/.
// ═══════════════════════════════════════════════════════════════════════════════

/// Servicio para gestionar notificaciones push con Firebase Cloud Messaging (FCM).
///
/// Se encarga de:
/// - Inicializar Firebase Messaging
/// - Solicitar permisos de notificación
/// - Obtener y renovar el token FCM del dispositivo
/// - Registrar/desregistrar el token en el backend
/// - Escuchar mensajes en foreground, background y terminated state
/// - Manejar taps en notificaciones para navegación
///
/// ## Android FCM (funcionando)
///   - Canal de notificación creado automáticamente por FCM SDK.
///   - Handler de background con Firebase re-inicializado (isolate propio).
///
/// ## iOS APNs (futuro)
///   - Agregar [FirebaseOptions] con GoogleService-Info.plist en [initialize].
///   - Crear [ios_notification_channel.dart] para UNUserNotificationCenter.
///   - El resto del flujo (token, registro, handlers) es el mismo
///     porque Firebase Messaging abstrae APNs.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  bool _initialized = false;
  String? _fcmToken;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Callback que se dispara cuando el usuario toca una notificación.
  /// Recibe los datos adicionales de la notificación (custom data payload).
  void Function(Map<String, dynamic> data)? onNotificationTap;

  /// Inicializa Firebase Messaging.
  ///
  /// - Solicita permisos de notificación
  /// - Obtiene el token FCM del dispositivo
  /// - Configura listeners para mensajes foreground, background y tap
  Future<void> initialize() async {
    if (_initialized) return;

    // ─── Android: canal de notificación ───────────────────────────
    // En Android 8+ se necesita un canal para que las notificaciones
    // se muestren. FCM crea uno por defecto automáticamente al recibir
    // el primer mensaje, pero lo invocamos explícitamente para tener
    // control futuro (sonido personalizado, importancia, etc.).
    await createAndroidNotificationChannel();

    // ─── iOS APNs (futuro) ────────────────────────────────────────
    // Configurar FirebaseOptions con GoogleService-Info.plist:
    //   await Firebase.initializeApp(
    //     options: DefaultFirebaseOptions.currentPlatform,
    //   );
    // Crear canal de notificaciones iOS:
    //   await createIOSNotificationChannel();

    // ─── Solicitar permisos de notificación ──────────────────────
    // En iOS muestra el diálogo nativo de sistema;
    // en Android `requestPermission` no muestra nada (los permisos
    // de notificación no existen como runtime permission en Android 13-).
    // En Android 13+ el sistema pide permiso automáticamente al crear
    // el canal o al recibir la primera notificación.
    final notificationSettings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (notificationSettings.authorizationStatus == AuthorizationStatus.denied) {
      // El usuario denegó permisos (solo posible en iOS).
      // En Android esto no ocurre — los permisos de notificación
      // se conceden por defecto en <13 y se piden automáticamente en 13+.
      debugPrint(
          '⚠️  Permisos de notificación denegados (solo aplica en iOS)');
    }

    // ─── Obtener token FCM ───────────────────────────────────────
    // El token identifica este dispositivo ante Firebase Cloud Messaging.
    // Es el mismo concepto tanto en Android como en iOS (FCM abstrae APNs).
    try {
      _fcmToken = await _messaging.getToken();
      if (_fcmToken != null) {
        debugPrint('📱 Token FCM obtenido: ${_fcmToken!.length} chars');
      }
    } catch (e) {
      debugPrint('❌ Error al obtener token FCM: $e');
    }

    // ─── Escuchar refresco de token ──────────────────────────────
    // Firebase renueva periódicamente el token (seguridad).
    // También se renueva si la app se restaura en un dispositivo nuevo.
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 Token FCM renovado');
      _fcmToken = newToken;
      // El re-registro en el backend lo gestiona AuthProvider
      // cuando detecta sesión activa (vía _registerPushDevice).
    });

    // ─── Mensajes en foreground ──────────────────────────────────
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Mensaje FCM en foreground: ${message.messageId}');

      final title = message.notification?.title ?? message.data['title'];
      final body = message.notification?.body ?? message.data['body'];

      if (title == null && body == null) return;

      localNotificationsPlugin.show(
        message.hashCode,
        title ?? 'Mercadito UM',
        body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            kNotificationChannelId,
            kNotificationChannelName,
            channelDescription: kNotificationChannelDescription,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
      );
    });

    // ─── Tap en notificación (app en background → foreground) ────
    // Se dispara cuando el usuario toca la notificación mientras la
    // app está en segundo plano (no terminada).
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });

    // ─── App abierta desde notificación (app estaba terminada) ───
    await _checkInitialMessage();

    _initialized = true;
  }

  /// Revisa si la app fue abierta desde una notificación cuando estaba terminada.
  Future<void> _checkInitialMessage() async {
    try {
      final RemoteMessage? initialMessage =
          await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      debugPrint('❌ Error al obtener mensaje inicial FCM: $e');
    }
  }

  /// Extrae los datos de la notificación y dispara el callback de navegación.
  void _handleNotificationTap(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    if (data.isNotEmpty && onNotificationTap != null) {
      onNotificationTap!(data);
    }
  }

  /// Obtiene el token FCM actual del dispositivo.
  String? get fcmToken => _fcmToken;

  // ─── Registro en backend ──────────────────────────────────────────
  // Tanto Android FCM como iOS APNs usan el mismo token Firebase
  // para identificar el dispositivo. El endpoint del backend es el mismo.

  /// Registra el dispositivo en el backend asociándolo al usuario autenticado.
  ///
  /// Envía el token FCM actual al endpoint POST /api/notifications/register-push.
  /// Si el token es null (permiso denegado o error), falla silenciosamente.
  Future<bool> registerDevice() async {
    if (_fcmToken == null) return false;
    try {
      await ApiService.registerPushToken(_fcmToken!);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Desregistra el token FCM actual del backend.
  Future<bool> unregisterDevice() async {
    if (_fcmToken == null) return false;
    try {
      await ApiService.unregisterPushToken(_fcmToken!);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Desregistra todos los dispositivos del usuario actual en el backend.
  Future<bool> unregisterAllDevices() async {
    try {
      await ApiService.unregisterAllPushTokens();
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Background handler — Android FCM
//
// Firebase Messaging en Android ejecuta este handler en un **isolate
// separado** cuando la app está en background o terminada.
//
// ⚠️  Por estar en otro isolate, Firebase NO está inicializado aquí.
//     Hay que llamar [Firebase.initializeApp()] dentro del handler.
//
// iOS usa el mismo callback pero en el mismo isolate principal,
// así que [Firebase.initializeApp()] es redundante pero inofensivo
// (retorna la instancia existente).
// ═══════════════════════════════════════════════════════════════════════════════

/// Handler de nivel superior para mensajes en background.
///
/// Firebase requiere que esta función sea:
/// 1. Top-level (no método de clase)
/// 2. Anotada con `@pragma('vm:entry-point')` para preservarla del tree-shaking
/// 3. Que acepte un único parámetro `RemoteMessage`
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // ─── Inicializar Firebase (requerido en Android, inofensivo en iOS) ──
  // Android ejecuta este handler en un isolate separado, donde Firebase
  // aún no está inicializado. Sin esto, cualquier acceso a Firestore,
  // Analytics, etc. dentro del handler fallaría.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Si ya fue inicializada (iOS), Firebase.initializeApp() es seguro.
  }

  // ─── Crear canal de notificación Android ────────────────────────────
  // Aunque FCM crea un canal por defecto, asegurarnos de que el canal
  // exista antes de mostrar la notificación evita race conditions.
  await createAndroidNotificationChannel();

  // ─── Procesar mensaje ───────────────────────────────────────────────
  // Los mensajes FCM con payload "notification" son mostrados
  // automáticamente por el sistema operativo (tanto en Android como iOS).
  // Los mensajes con solo "data" requieren manejo manual.
  //
  // Si se necesita lógica personalizada al recibir un mensaje en background
  // (ej. actualizar contador de notificaciones, guardar en DB local),
  // se agrega aquí.
  debugPrint(
      '📩 [Background] Mensaje FCM recibido: ${message.messageId} '
      '(${Platform.isAndroid ? "Android" : Platform.isIOS ? "iOS" : "Otro"})');
}
