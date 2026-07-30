// ---------------------------------------------------------------------------
// Android Notification Channel
//
// En Android 8+ (Oreo, API 26+) es obligatorio crear un canal de
// notificación para que los mensajes FCM se muestren correctamente.
// Sin canal, las notificaciones se silencian o se agrupan en un canal
// por defecto sin personalización.
//
// Este archivo concentra TODO lo Android-specific de notificaciones.
// Cuando se agregue iOS/APNs, las APIs de UNUserNotificationCenter
// irán en un archivo separado (ios_notification_channel.dart).
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../push_service.dart';

/// Instancia global del plugin de notificaciones locales.
final FlutterLocalNotificationsPlugin localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const String kNotificationChannelId = 'mercadito_um_default';
const String kNotificationChannelName = 'Mercadito UM';
const String kNotificationChannelDescription =
    'Notificaciones de Mercadito UM';

Future<void> createAndroidNotificationChannel() async {
  if (!Platform.isAndroid) return;

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  await localNotificationsPlugin.initialize(
    const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null && response.payload!.isNotEmpty) {
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          PushService.instance.onNotificationTap?.call(data);
        } catch (e) {
          debugPrint('Error parseando payload de notificación: $e');
        }
      }
    },
  );

  // Crear el canal de notificación Android explícitamente.
  // El backend envía notificaciones con channelId 'mercadito_um_default',
  // así que debemos crear ese canal para que las notificaciones en
  // background se muestren con la importancia/configuración deseada.
  const androidChannel = AndroidNotificationChannel(
    kNotificationChannelId,
    kNotificationChannelName,
    description: kNotificationChannelDescription,
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  await localNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  debugPrint('📱 [Android] Canal de notificación "$kNotificationChannelId" creado');
}
