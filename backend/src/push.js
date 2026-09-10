const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

// ─── Configuración de Firebase Admin SDK ──────────────────────────
// El backend acepta dos variables de entorno para las credenciales:
//
//   Opción A (desarrollo local):
//     FIREBASE_SERVICE_ACCOUNT_PATH=ruta/al/service-account.json
//
//   Opción B (producción/Docker, el JSON completo inline):
//     FIREBASE_SERVICE_ACCOUNT_JSON='{"type": "service_account", ...}'
//
// En ambos casos se necesita FIREBASE_PROJECT_ID como respaldo.
// ───────────────────────────────────────────────────────────────────

let initialized = false;
function ensureInitialized() {
  if (initialized) return;
  let serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const projectId = process.env.FIREBASE_PROJECT_ID;

  // Fallback automático al archivo service account en la raíz si no hay env var
  if (!serviceAccountPath && !serviceAccountJson) {
    const rootPath = path.resolve(__dirname, '..', '..', 'mercadoum-firebase-adminsdk-fbsvc-6c500851ae.json');
    if (fs.existsSync(rootPath)) {
      serviceAccountPath = rootPath;
    }
  }
  if (!serviceAccountPath && !serviceAccountJson && !projectId) {
    console.warn('⚠️  Firebase no configurado. Define FIREBASE_SERVICE_ACCOUNT_PATH o FIREBASE_SERVICE_ACCOUNT_JSON');
    return;
  }
  try {
    let serviceAccount;
    if (serviceAccountPath) {
      const resolvedPath = path.resolve(serviceAccountPath);
      const raw = fs.readFileSync(resolvedPath, 'utf-8');
      serviceAccount = JSON.parse(raw);
    } else if (serviceAccountJson) {
      serviceAccount = JSON.parse(serviceAccountJson);
    }
    const credential = serviceAccount ? admin.credential.cert(serviceAccount) : admin.credential.applicationDefault();
    admin.initializeApp({
      credential,
      projectId: projectId || (serviceAccount ? serviceAccount.project_id : undefined)
    });
    initialized = true;
    console.log('🔥 Firebase Admin SDK inicializado');
  } catch (err) {
    console.error('❌ Error al inicializar Firebase Admin SDK:', err.message);
  }
}

/**
 * Envía una notificación push vía Firebase Cloud Messaging (FCM) a uno o más usuarios.
 *
 * Busca los tokens FCM de cada usuario en la tabla push_tokens y envía
 * individualmente a cada token. Si un token está expirado o inválido,
 * lo elimina automáticamente de la base de datos.
 *
 * @param {string[]} userIds - Lista de IDs de usuario del backend
 * @param {string} title   - Título de la notificación
 * @param {string} body    - Cuerpo de la notificación
 * @param {object} data    - Datos adicionales (conversationId, productId, type, etc.)
 */
async function sendPush(userIds, title, body, data = {}) {
  // Cargar database aquí dentro para evitar dependencia circular
  const db = require('./database');
  ensureInitialized();
  if (!initialized) {
    console.warn('⚠️  Firebase no inicializado. No se puede enviar push.');
    return false;
  }
  if (!userIds || userIds.length === 0) {
    return false;
  }

  // Recolectar todos los tokens de los usuarios destino
  const tokens = [];
  for (const userId of userIds) {
    const userTokens = await db.getPushTokensForUser(userId);
    tokens.push(...userTokens);
  }
  if (tokens.length === 0) {
    console.log(`📭 Sin tokens push para ${userIds.length} usuario(s)`);
    return false;
  }
  console.log(`📨 Enviando push a ${tokens.length} dispositivo(s) para ${userIds.length} usuario(s)`);

  // ─── Agrupación por conversación ─────────────────────────────────
  // Cuando el push pertenece a un chat, sus notificaciones tienen que ser
  // localizables después para poder borrarlas al abrir esa conversación.
  //
  // El `tag` de Android lleva prefijo común + sufijo único a propósito:
  //   - con el prefijo, la app puede recorrer las notificaciones activas y
  //     cancelar las de un chat concreto (ver notification_cleaner.dart);
  //   - con el sufijo único, dos mensajes seguidos NO se reemplazan entre sí
  //     y se siguen apilando, que es el comportamiento actual y es deseado.
  // Un `tag` fijo por conversación rompería justo eso.
  const conversationId = data.conversationId ? String(data.conversationId) : null;
  const threadId = conversationId ? `chat_${conversationId}` : null;
  const androidTag = threadId ? `${threadId}_${Date.now()}_${Math.random().toString(36).slice(2, 6)}` : undefined;

  // Construir payload base
  const messageBase = {
    notification: {
      title,
      body
    },
    data: Object.fromEntries(Object.entries({
      ...data
    }).map(([k, v]) => [k, String(v ?? '')])),
    apns: {
      payload: {
        aps: {
          alert: {
            title,
            body
          },
          sound: 'default',
          badge: 1,
          // Agrupa las notificaciones del mismo chat en un solo hilo de iOS
          // y permite ubicarlas para borrarlas al abrir la conversación.
          ...(threadId ? {
            'thread-id': threadId
          } : {})
        }
      }
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'mercadito_um_default',
        notificationPriority: 'PRIORITY_HIGH',
        defaultSound: true,
        ...(androidTag ? {
          tag: androidTag
        } : {}),
        // Silueta blanca sobre transparente (android/app/.../drawable-*/ic_notification.png).
        // Ya está como default en el manifest, pero se declara explícito
        // acá para que quede claro sin tener que ir a leer el manifest.
        icon: 'ic_notification',
        color: '#3D5C70'
      }
    }
  };

  // Enviar a cada token individualmente para poder detectar tokens inválidos
  const results = await Promise.allSettled(tokens.map(async token => {
    try {
      const response = await admin.messaging().send({
        token,
        ...messageBase
      });
      console.log(`[Push Debug] Éxito al enviar a token ${token.slice(0, 10)}... Response ID:`, response);
      return {
        token,
        success: true,
        response
      };
    } catch (err) {
      console.log(`[Push Debug] Fallo al enviar a token ${token.slice(0, 10)}... Error:`, err.message);
      return {
        token,
        success: false,
        error: err
      };
    }
  }));
  let successCount = 0;
  let failCount = 0;
  const tokensToRemove = [];
  for (const result of results) {
    if (result.status === 'fulfilled' && result.value.success) {
      successCount++;
    } else if (result.status === 'fulfilled' && !result.value.success) {
      failCount++;
      const error = result.value.error;
      const token = result.value.token;

      // Códigos de error que indican token inválido/expirado
      if (error.code === 'messaging/registration-token-not-registered' || error.code === 'messaging/invalid-registration-token' || error.code === 'messaging/invalid-argument') {
        tokensToRemove.push(token);
        console.log(`  🗑️ Token inválido detectado, será eliminado: ${token.slice(0, 20)}...`);
      } else {
        console.error(`  ❌ Error FCM para token ${token.slice(0, 20)}...:`, error.code || error.message);
      }
    }
  }

  // Eliminar tokens inválidos de la BD
  if (tokensToRemove.length > 0) {
    const removeStmt = db.getDb().prepare('DELETE FROM push_tokens WHERE player_id = ?');
    const removeMany = db.getDb().transaction(tokens => {
      for (const t of tokens) {
        removeStmt.run(t);
      }
    });
    removeMany(tokensToRemove);
    console.log(`  🧹 Eliminados ${tokensToRemove.length} token(s) inválido(s)`);
  }
  console.log(`📬 Push completado: ${successCount} éxito, ${failCount} fallo(s)`);
  return successCount > 0;
}
module.exports = {
  sendPush,
  ensureInitialized
};
