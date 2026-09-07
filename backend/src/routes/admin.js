const crypto = require('crypto');
const express = require('express');
const rateLimit = require('express-rate-limit');
const { ipKeyGenerator } = require('express-rate-limit');
const net = require('net');
const { registrarAuditoriaAdmin } = require('../adminAudit');
const db = require('../database');
const {
  authenticateAdmin,
  normalizeAdminUsername,
  requireAdmin,
} = require('../adminAuth');
const {
  DEFAULT_PUBLICATION_POLICIES,
  PUBLICATION_POLICY_FIELDS,
  PUBLICATION_POLICY_KEYS,
  PUBLICATION_POLICY_RANGES,
  rowToPublicationPolicy,
} = require('../publicationPolicy');
const revision = require('./revision');
const adminOperations = require('./adminOperations');

const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const CONFIG_SELECT = `SELECT key, products_active, products_daily,
  wanted_active, wanted_daily, duration_days, updated_by_admin_id, updated_at
  FROM config`;

function fingerprint(value) {
  return crypto.createHash('sha256').update(String(value)).digest('base64url');
}

function secretBffConfigurado() {
  const value = String(process.env.ADMIN_BFF_SHARED_SECRET || '');
  return value.length >= 32 ? value : null;
}

// Next recibe la IP real desde Apache y la firma antes de hablar por
// loopback con Express. Sin esta prueba un cliente podria inventar el header
// para rotar buckets; una prueba ausente/invalida cae a req.ip, que Apache
// determina con TRUST_PROXY=1 para las llamadas directas al API.
function clientIpForRateLimit(req) {
  const sharedSecret = secretBffConfigurado();
  const forwardedIp = String(req.get('x-admin-client-ip') || '').trim();
  const timestamp = String(req.get('x-admin-client-time') || '').trim();
  const signature = String(req.get('x-admin-client-signature') || '').trim();
  if (
    sharedSecret
    && net.isIP(forwardedIp)
    && /^\d{10}$/.test(timestamp)
    && /^[a-f0-9]{64}$/.test(signature)
    && Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp)) <= 60
  ) {
    const expected = crypto
      .createHmac('sha256', sharedSecret)
      .update(`${timestamp}.${forwardedIp}`)
      .digest('hex');
    const expectedBuffer = Buffer.from(expected);
    const suppliedBuffer = Buffer.from(signature);
    if (
      expectedBuffer.length === suppliedBuffer.length
      && crypto.timingSafeEqual(expectedBuffer, suppliedBuffer)
    ) {
      return forwardedIp;
    }
  }
  return req.ip;
}

function loginLimiter({ limit, keyGenerator }) {
  return rateLimit({
    windowMs: LOGIN_WINDOW_MS,
    limit,
    keyGenerator,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skipSuccessfulRequests: true,
    message: { error: 'Demasiados intentos de acceso. Intenta de nuevo mas tarde.' },
  });
}

function createLoginLimiters() {
  return [
    // Detiene un ataque distribuido contra el mismo nombre de administrador.
    loginLimiter({
      limit: 8,
      keyGenerator: req => fingerprint(
        normalizeAdminUsername(req.body?.username) || 'usuario-invalido',
      ),
    }),
    // Y evita que una sola red rote nombres de usuario indefinidamente.
    loginLimiter({
      limit: 30,
      keyGenerator: req => ipKeyGenerator(clientIpForRateLimit(req)),
    }),
  ];
}

function configKeyExists(key) {
  return PUBLICATION_POLICY_KEYS.includes(key);
}

function getConfig(database, key) {
  const row = database.prepare(`${CONFIG_SELECT} WHERE key = ?`).get(key);
  return row ? rowToPublicationPolicy(row) : null;
}

function validateConfigPayload(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return { error: 'El cuerpo debe ser un objeto de configuracion.' };
  }
  const receivedFields = Object.keys(body).sort();
  const expectedFields = [...PUBLICATION_POLICY_FIELDS].sort();
  if (
    receivedFields.length !== expectedFields.length
    || receivedFields.some((field, index) => field !== expectedFields[index])
  ) {
    return {
      error: `El cuerpo debe contener exactamente: ${PUBLICATION_POLICY_FIELDS.join(', ')}.`,
    };
  }

  for (const field of PUBLICATION_POLICY_FIELDS) {
    const value = body[field];
    const range = PUBLICATION_POLICY_RANGES[field];
    if (!Number.isSafeInteger(value) || value < range.min || value > range.max) {
      return {
        error: `${field} debe ser un entero entre ${range.min} y ${range.max}.`,
      };
    }
  }
  return { value: Object.fromEntries(PUBLICATION_POLICY_FIELDS.map(field => [field, body[field]])) };
}

function writeConfig(database, key, policy, adminId, updatedAt) {
  database.prepare(
    `UPDATE config SET products_active = ?, products_daily = ?,
       wanted_active = ?, wanted_daily = ?, duration_days = ?,
       updated_by_admin_id = ?, updated_at = ?
     WHERE key = ?`,
  ).run(
    policy.productsActive,
    policy.productsDaily,
    policy.wantedActive,
    policy.wantedDaily,
    policy.durationDays,
    adminId,
    updatedAt,
    key,
  );
}

function router() {
  const api = express.Router();
  api.use((_req, res, next) => {
    res.set({
      'Cache-Control': 'private, no-store',
      Pragma: 'no-cache',
      'X-Content-Type-Options': 'nosniff',
    });
    next();
  });

  // Unica excepcion publica del namespace admin: todavía no existe un token
  // que se pueda validar. Contraseña y TOTP se comprueban juntos y las
  // respuestas fallidas no revelan cuál de los dos fue incorrecto.
  api.post('/auth/login', ...createLoginLimiters(), async (req, res, next) => {
    try {
      const result = await authenticateAdmin(req.body || {});
      if (result.configurationError) {
        return res.status(503).json({
          error: 'La autenticacion administrativa no esta configurada.',
        });
      }
      if (!result.authenticated) {
        return res.status(401).json({
          error: 'Credenciales o codigo de autenticacion invalidos.',
        });
      }
      return res.json({
        token: result.token,
        expiresIn: result.expiresIn,
        admin: result.admin,
      });
    } catch (error) {
      return next(error);
    }
  });

  // Todo endpoint agregado debajo de esta línea queda autenticado por defecto.
  // El middleware verifica firma, algoritmo, issuer, audience, expiración,
  // versión de sesión, revocación y que el admin siga activo en SQLite.
  api.use(requireAdmin);

  api.get('/auth/session', (req, res) => {
    res.json({ admin: req.admin });
  });

  api.post('/auth/logout', (req, res) => {
    db.getDb().prepare(
      `INSERT OR IGNORE INTO admin_revoked_tokens
       (jti, admin_id, expires_at) VALUES (?, ?, ?)`,
    ).run(req.adminSession.jti, req.admin.id, req.adminSession.expiresAt);
    res.status(204).end();
  });

  api.get('/config', (_req, res) => {
    const rows = db.getDb().prepare(CONFIG_SELECT).all();
    const rowsByKey = new Map(rows.map(row => [row.key, row]));
    const config = PUBLICATION_POLICY_KEYS.map(key => rowsByKey.get(key))
      .filter(Boolean)
      .map(rowToPublicationPolicy);
    if (config.length !== PUBLICATION_POLICY_KEYS.length) {
      throw new Error('La configuracion de publicaciones esta incompleta.');
    }
    res.json({ config });
  });

  api.get('/config/:key', (req, res) => {
    if (!configKeyExists(req.params.key)) {
      return res.status(404).json({ error: 'Configuracion no encontrada.' });
    }
    const config = getConfig(db.getDb(), req.params.key);
    if (!config) throw new Error('La configuracion de publicaciones esta incompleta.');
    return res.json({ config });
  });

  api.put('/config/:key', (req, res) => {
    if (!configKeyExists(req.params.key)) {
      return res.status(404).json({ error: 'Configuracion no encontrada.' });
    }
    const validated = validateConfigPayload(req.body);
    if (validated.error) return res.status(400).json({ error: validated.error });

    const database = db.getDb();
    const updatedAt = new Date().toISOString();
    const result = database.transaction(() => {
      const before = getConfig(database, req.params.key);
      if (!before) throw new Error('La configuracion de publicaciones esta incompleta.');
      writeConfig(database, req.params.key, validated.value, req.admin.id, updatedAt);
      const after = getConfig(database, req.params.key);
      registrarAuditoriaAdmin(database, req, {
        action: 'config.update',
        entityType: 'config',
        entityId: req.params.key,
        details: { before, after },
        createdAt: updatedAt,
      });
      return { before, after };
    })();
    return res.json({ config: result.after });
  });

  // DELETE no elimina una de las cinco filas fijas: restablece sus limites a
  // los defaults versionados y conserva quien hizo el reset y cuando.
  api.delete('/config/:key', (req, res) => {
    if (!configKeyExists(req.params.key)) {
      return res.status(404).json({ error: 'Configuracion no encontrada.' });
    }

    const database = db.getDb();
    const updatedAt = new Date().toISOString();
    const result = database.transaction(() => {
      const before = getConfig(database, req.params.key);
      if (!before) throw new Error('La configuracion de publicaciones esta incompleta.');
      writeConfig(
        database,
        req.params.key,
        DEFAULT_PUBLICATION_POLICIES[req.params.key],
        req.admin.id,
        updatedAt,
      );
      const after = getConfig(database, req.params.key);
      registrarAuditoriaAdmin(database, req, {
        action: 'config.reset',
        entityType: 'config',
        entityId: req.params.key,
        details: { before, after },
        createdAt: updatedAt,
      });
      return { before, after };
    })();
    return res.json({
      config: result.after,
      resetToDefaults: true,
      message: 'La fila se conservo y sus limites se restablecieron a los valores predeterminados.',
    });
  });

  api.use(adminOperations.router());

  // Se reutiliza el router probado de revisión; la autenticación ya ocurrió en
  // el padre, por lo que no se duplica la lógica ni se reescribe la función.
  api.use('/revision', revision.router({ authenticate: (_req, _res, next) => next() }));

  return api;
}

function register(app) {
  app.use('/api/admin', router());
}

module.exports = {
  createLoginLimiters,
  register,
  router,
  validateConfigPayload,
};
