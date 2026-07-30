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

import 'dart:io' show Platform;

import 'package:flutter/material.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Instancia global del plugin de notificaciones locales.
///
/// Se usa tanto para crear el canal Android como para mostrar
/// notificaciones locales cuando la app está en foreground.
final FlutterLocalNotificationsPlugin localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// ID del canal de notificación principal de Mercadito UM.
///
/// Debe coincidir con el `channelId` que el backend envía en
/// el payload FCM android.notification.channelId.
const String kNotificationChannelId = 'mercadito_um_default';

/// Nombre visible del canal en la configuración del sistema Android.
const String kNotificationChannelName = 'Mercadito UM';

/// Descripción del canal en la configuración del sistema Android.
const String kNotificationChannelDescription =
    'Notificaciones de Mercadito UM';

/// Crea el canal de notificación principal para Android e inicializa
/// el plugin de notificaciones locales.
///
/// Debe llamarse antes de que FCM intente mostrar una notificación
/// (idealmente en el [initialize] de [PushService]).
///
/// Si no es Android, la función es no-op.
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
