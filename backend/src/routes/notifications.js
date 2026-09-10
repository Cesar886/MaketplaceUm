const db = require('../database');
const {
  requireAuth,
  optionalAuth
} = require('../auth');
const {
  sendPush
} = require('../push');
const frecuencia = require('../notifications/frecuencia');
const metricas = require('../notifications/metricas');
const retargeting = require('../notifications/retargeting');

/**
 * Resuelve el sujeto de una petición que puede venir de una cuenta o de un
 * dispositivo anónimo, y rechaza el caso peligroso: mandar como `subjectId`
 * el id de otra persona. Un id anónimo tiene prefijo 'anon_' y no puede
 * coincidir con una cuenta (mismo criterio que /register-push-anon).
 *
 * @returns {{subjectId: string}|{error: string, status: number}}
 */
async function resolverSujeto(req) {
  if (req.user) return {
    subjectId: req.user.id
  };
  const subjectId = req.body?.subjectId || req.query?.subjectId;
  if (!subjectId) {
    return {
      error: 'subjectId es requerido sin sesión',
      status: 400
    };
  }
  if (!String(subjectId).startsWith('anon_')) {
    return {
      error: 'subjectId inválido para uso anónimo',
      status: 400
    };
  }
  const cuenta = await db.getDb().prepare('SELECT id FROM sellers WHERE id = ?').get(subjectId);
  if (cuenta) {
    return {
      error: 'subjectId no permitido',
      status: 403
    };
  }
  return {
    subjectId
  };
}

/**
 * Guardia de los endpoints de operación (disparar el job, leer métricas):
 * no son de usuario, son de infraestructura.
 *
 * Con NOTIFICATIONS_JOB_TOKEN definido exige ese token en la cabecera. Sin
 * definir, solo acepta llamadas desde loopback, para que en desarrollo se
 * pueda usar con curl sin dejar el endpoint abierto en un despliegue donde
 * alguien olvidó configurar la variable.
 */
function permitirOperacion(req, res) {
  const esperado = process.env.NOTIFICATIONS_JOB_TOKEN;
  if (esperado) {
    if (req.get('x-job-token') === esperado) return true;
    res.status(401).json({
      error: 'token de job inválido'
    });
    return false;
  }
  const ip = req.ip || '';
  if (ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1') return true;
  res.status(503).json({
    error: 'NOTIFICATIONS_JOB_TOKEN no está configurado; solo se acepta desde localhost'
  });
  return false;
}
function register(app) {
  // GET /api/notifications - obtener notificaciones del usuario autenticado
  app.get('/api/notifications', requireAuth, async (req, res) => {
    const notifications = await db.getNotifications(req.user.id);
    const unreadCount = await db.getUnreadNotificationCount(req.user.id);
    res.json({
      notifications,
      unreadCount
    });
  });

  // PATCH /api/notifications/:id/read - marcar una notificación como leída
  app.patch('/api/notifications/:id/read', requireAuth, async (req, res) => {
    const changed = await db.markNotificationRead(req.params.id, req.user.id);
    if (!changed) return res.status(404).json({
      error: 'Notificación no encontrada.'
    });
    res.json({
      success: true
    });
  });

  // PATCH /api/notifications/read-all - marcar todas como leídas
  app.patch('/api/notifications/read-all', requireAuth, async (req, res) => {
    await db.markAllNotificationsRead(req.user.id);
    res.json({
      success: true
    });
  });

  // PATCH /api/notifications/read-by-conversation - marcar como leídas las de
  // un chat. Lo llama la app al abrir la conversación: los mensajes ya se
  // marcan leídos solos al pedirlos, pero las notificaciones in-app que
  // alimentan el badge de la campana no, y el contador se quedaba inflado.
  app.patch('/api/notifications/read-by-conversation', requireAuth, async (req, res) => {
    const {
      conversationId
    } = req.body;
    if (!conversationId) {
      return res.status(400).json({
        error: 'conversationId es requerido'
      });
    }
    const marcadas = await db.markNotificationsReadForConversation(req.user.id, conversationId);
    res.json({
      success: true,
      marcadas,
      unreadCount: await db.getUnreadNotificationCount(req.user.id)
    });
  });

  // GET /api/notifications/unread-count - obtener solo el conteo
  app.get('/api/notifications/unread-count', requireAuth, async (req, res) => {
    const count = await db.getUnreadNotificationCount(req.user.id);
    res.json({
      count
    });
  });

  // ─── Category Interests ────────────────────────────────────

  // GET /api/notifications/interests - obtener categorías seguidas
  app.get('/api/notifications/interests', requireAuth, async (req, res) => {
    const interests = await db.getCategoryInterests(req.user.id);
    res.json({
      interests
    });
  });

  // POST /api/notifications/interests - seguir una categoría
  app.post('/api/notifications/interests', requireAuth, async (req, res) => {
    const {
      categoryId
    } = req.body;
    if (!categoryId) return res.status(400).json({
      error: 'categoryId es requerido'
    });
    await db.addCategoryInterest(req.user.id, categoryId);
    const interests = await db.getCategoryInterests(req.user.id);
    res.json({
      interests
    });
  });

  // DELETE /api/notifications/interests/:categoryId - dejar de seguir
  app.delete('/api/notifications/interests/:categoryId', requireAuth, async (req, res) => {
    await db.removeCategoryInterest(req.user.id, req.params.categoryId);
    const interests = await db.getCategoryInterests(req.user.id);
    res.json({
      interests
    });
  });

  // ─── Retargeting por interés ─────────────────────────────────────

  // GET /api/notifications/preferences - preferencias del sujeto.
  // optionalAuth: sirve igual a una cuenta (por el JWT) que a un dispositivo
  // anónimo (por ?subjectId=anon_...), porque ambos reciben estos pushes.
  app.get('/api/notifications/preferences', optionalAuth, async (req, res) => {
    const sujeto = await resolverSujeto(req);
    if (sujeto.error) return res.status(sujeto.status).json({
      error: sujeto.error
    });
    res.json({
      subjectId: sujeto.subjectId,
      preferences: await frecuencia.getPreferencias(sujeto.subjectId)
    });
  });

  // PUT /api/notifications/preferences - activar/desactivar un tipo
  app.put('/api/notifications/preferences', optionalAuth, async (req, res) => {
    const sujeto = await resolverSujeto(req);
    if (sujeto.error) return res.status(sujeto.status).json({
      error: sujeto.error
    });
    const {
      type,
      enabled
    } = req.body || {};
    if (typeof enabled !== 'boolean') {
      return res.status(400).json({
        error: 'enabled debe ser booleano'
      });
    }
    const tipo = type || frecuencia.TIPO_RETARGETING;
    if (tipo !== frecuencia.TIPO_RETARGETING) {
      return res.status(400).json({
        error: `type no soportado: ${tipo}`
      });
    }
    await frecuencia.setHabilitado(sujeto.subjectId, tipo, enabled);
    res.json({
      subjectId: sujeto.subjectId,
      preferences: await frecuencia.getPreferencias(sujeto.subjectId)
    });
  });

  // POST /api/notifications/interest-opened - la app abrió un push de
  // retargeting. Alimenta el open rate Y la reducción adaptativa: sin esta
  // llamada el sistema da por ignoradas todas las notificaciones y acaba
  // autopausándose solo.
  app.post('/api/notifications/interest-opened', optionalAuth, async (req, res) => {
    const sujeto = await resolverSujeto(req);
    if (sujeto.error) return res.status(sujeto.status).json({
      error: sujeto.error
    });
    const {
      notificationId,
      categoryId
    } = req.body || {};
    if (!notificationId && !categoryId) {
      return res.status(400).json({
        error: 'notificationId o categoryId es requerido'
      });
    }
    const marcadas = await frecuencia.registrarApertura({
      subjectId: sujeto.subjectId,
      notificationId,
      categoryId
    });
    res.json({
      success: true,
      marcadas
    });
  });

  // POST /api/notifications/trigger-interest-based - ejecuta una pasada del
  // job. Lo llama el intervalo interno de index.js; queda expuesto para
  // poder dispararlo desde un cron externo o a mano al depurar.
  app.post('/api/notifications/trigger-interest-based', async (req, res) => {
    if (!permitirOperacion(req, res)) return;
    (await retargeting.ejecutarJobRetargeting()).then(resumen => res.json({
      success: true,
      ...resumen
    })).catch(err => {
      console.error('[retargeting] el job falló:', err);
      res.status(500).json({
        error: err.message
      });
    });
  });

  // GET /api/notifications/metrics - open rate por tipo y por categoría
  app.get('/api/notifications/metrics', async (req, res) => {
    if (!permitirOperacion(req, res)) return;
    const dias = Number(req.query.dias) || metricas.VENTANA_METRICAS_DIAS;
    res.json(await metricas.getOpenRate({
      dias
    }));
  });

  // ─── Push Tokens (FCM) ───────────────────────────────────────────

  // POST /api/notifications/register-push - registrar un FCM device token
  app.post('/api/notifications/register-push', requireAuth, async (req, res) => {
    const {
      playerId
    } = req.body;
    if (!playerId) return res.status(400).json({
      error: 'playerId es requerido'
    });
    await db.registerPushToken(req.user.id, playerId, req.body.platform || 'unknown');
    res.json({
      success: true
    });
  });

  // DELETE /api/notifications/register-push - desregistrar un FCM device token
  app.delete('/api/notifications/register-push', requireAuth, async (req, res) => {
    const {
      playerId
    } = req.body;
    if (!playerId) return res.status(400).json({
      error: 'playerId es requerido'
    });
    await db.unregisterPushToken(req.user.id, playerId);
    res.json({
      success: true
    });
  });

  // DELETE /api/notifications/register-push/all - desregistrar todos los tokens del usuario
  app.delete('/api/notifications/register-push/all', requireAuth, async (req, res) => {
    await db.unregisterAllPushTokensForUser(req.user.id);
    res.json({
      success: true
    });
  });

  // POST /api/notifications/register-push-anon - FCM token para usuarios anónimos (sin auth)
  // El userId debe tener el prefijo 'anon_' (formato generado por AnonymousId en Flutter)
  // y NO puede coincidir con un usuario autenticado, para evitar hijacking de notificaciones.
  app.post('/api/notifications/register-push-anon', requireAuth, async (req, res) => {
    const {
      playerId,
      platform
    } = req.body;
    const userId = req.user.id;
    if (!playerId) {
      return res.status(400).json({
        error: 'playerId es requerido'
      });
    }

    // Solo se aceptan IDs anónimos (prefijo 'anon_')
    if (!req.user.anon || !userId.startsWith('anon_')) {
      return res.status(403).json({
        error: 'Se requiere una sesión de invitado.'
      });
    }

    // Rechazar si el ID corresponde a un usuario autenticado en la base de datos
    const existingSeller = await db.getDb().prepare('SELECT id FROM sellers WHERE id = ?').get(userId);
    if (existingSeller) {
      return res.status(403).json({
        error: 'userId no permitido'
      });
    }
    await db.registerPushToken(userId, playerId, platform || 'android');
    res.json({
      success: true
    });
  });
}
module.exports = {
  register
};
