import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;

import 'fcm/android_notification_channel.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NotificationCleaner — borrar las notificaciones ya entregadas de un chat
//
// Al abrir una conversación, las notificaciones que anunciaban esos mensajes
// dejan de tener sentido y deben desaparecer de la barra del sistema.
//
// El problema a resolver es de *identificación*: las notificaciones de un chat
// llegan por dos caminos distintos y ninguno de los dos deja, por sí solo, un
// identificador que la app pueda reconstruir después:
//
//   - App en foreground → las pinta flutter_local_notifications con un id
//     numérico que antes era `message.hashCode`, imposible de derivar del
//     conversationId.
//   - App en background o cerrada → las pinta el sistema operativo a partir
//     del payload `notification` de FCM; la app nunca elige su id.
//
// La solución es que ambos caminos etiqueten la notificación con un `tag`
// (Android) / `thread-id` (iOS) que empiece con `chat_<conversationId>_`, y
// que aquí se recorran las notificaciones activas cancelando las que casen con
// ese prefijo. Se usa prefijo y no un tag fijo por chat porque un tag repetido
// hace que Android *reemplace* la notificación anterior, y el apilado de
// varios mensajes seguidos es un comportamiento que queremos conservar.
//
// El prefijo lo genera también el backend (backend/src/push.js); los dos lados
// tienen que coincidir, de ahí que la construcción viva en [tagDeConversacion].
// ═══════════════════════════════════════════════════════════════════════════

/// Prefijo común a todas las notificaciones de una conversación.
String prefijoConversacion(String conversationId) => 'chat_$conversationId';

/// Tag único para una notificación concreta de una conversación.
///
/// Comparte prefijo con las demás del mismo chat (para poder cancelarlas en
/// bloque) pero es único (para que se apilen en vez de reemplazarse).
String tagDeConversacion(String conversationId) =>
    '${prefijoConversacion(conversationId)}_'
    '${DateTime.now().millisecondsSinceEpoch}';

/// Cancela todas las notificaciones ya entregadas que pertenezcan a [conversationId].
///
/// Es mejor-esfuerzo: si el plugin no puede enumerar las notificaciones
/// activas (Android < 6, o iOS con notificaciones remotas), no lanza — abrir el
/// chat nunca debe fallar por no poder limpiar la bandeja.
Future<void> limpiarNotificacionesDeConversacion(String conversationId) async {
  if (conversationId.isEmpty) return;
  final prefijo = prefijoConversacion(conversationId);

  try {
    final activas = await localNotificationsPlugin.getActiveNotifications();
    var canceladas = 0;

    for (final n in activas) {
      // En Android el `tag` viene poblado tanto para las notificaciones del
      // plugin como para las que puso FCM, porque getActiveNotifications()
      // consulta al NotificationManager del sistema, que las ve todas.
      // En iOS el plugin no expone el thread-id, así que ahí este filtro solo
      // alcanza a las locales (ver nota de limitación más abajo).
      final coincide =
          (n.tag != null && n.tag!.startsWith(prefijo)) ||
          (n.groupKey != null && n.groupKey!.contains(prefijo));
      if (!coincide) continue;

      await localNotificationsPlugin.cancel(n.id ?? 0, tag: n.tag);
      canceladas++;
    }

    debugPrint(
      '🧹 Notificaciones limpiadas para $conversationId: '
      '$canceladas de ${activas.length} activas',
    );

    // ─── Limitación conocida en iOS ─────────────────────────────────
    // UNUserNotificationCenter sí permite borrar entregadas por identifier,
    // pero flutter_local_notifications solo devuelve en getActiveNotifications
    // las que él mismo publicó; las remotas de APNs traen un identifier UUID
    // que el plugin no mapea. Mientras eso siga así, en iOS las notificaciones
    // recibidas con la app cerrada se agrupan por thread-id (eso ya lo manda
    // el backend) pero no se pueden borrar selectivamente desde Dart. Cuando
    // haga falta, la salida es un MethodChannel propio a
    // removeDeliveredNotifications(withIdentifiers:).
    if (Platform.isIOS && canceladas == 0 && activas.isNotEmpty) {
      debugPrint(
        'ℹ️  [iOS] Ninguna notificación activa coincidió por tag: '
        'probablemente son remotas (limitación conocida del plugin).',
      );
    }
  } catch (e) {
    debugPrint('⚠️  No se pudieron limpiar las notificaciones del chat: $e');
  }
}
