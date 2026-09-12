const rateLimit = require('express-rate-limit');
const crypto = require('crypto');

function allowedOrigins() {
  return new Set([
    process.env.ALLOWED_ORIGINS,
    process.env.APP_PUBLIC_URL,
    process.env.ADMIN_PANEL_ORIGIN,
  ]
    .filter(Boolean).join(',')
    .split(',').map(value => value.trim()).filter(Boolean).map(value => {
      try { return new URL(value).origin; } catch { return null; }
    }).filter(Boolean));
}

function configuredAdminOrigin() {
  const raw = String(process.env.ADMIN_PANEL_ORIGIN || '').trim();
  if (!raw) return null;
  try {
    const parsed = new URL(raw);
    if (parsed.origin !== raw.replace(/\/$/, '')) return null;
    if (process.env.NODE_ENV === 'production' && parsed.protocol !== 'https:') return null;
    return parsed.origin;
  } catch {
    return null;
  }
}

// El panel habla con Express desde su BFF de Next y siempre envia su Origin
// configurado. A diferencia del CORS general (que admite apps moviles sin
// Origin), el namespace administrativo falla cerrado si falta o no coincide.
function adminCorsOrigin(origin, callback) {
  const allowed = configuredAdminOrigin();
  if (allowed && origin === allowed) return callback(null, true);
  const error = new Error('Origen administrativo no permitido.');
  error.status = 403;
  return callback(error);
}

// Las apps moviles y las llamadas servidor-a-servidor no mandan Origin.
// Un navegador si lo manda: solo esos requests se comparan con la allowlist.
function corsOrigin(origin, callback) {
  if (!origin) return callback(null, true);
  if (allowedOrigins().has(origin)) return callback(null, true);
  const error = new Error('Origen no permitido.');
  error.status = 403;
  return callback(error);
}

function securityHeaders(_req, res, next) {
  res.set({
    'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'",
    'Cross-Origin-Opener-Policy': 'same-origin',
    // Los archivos publicos se consumen tambien desde la app web en otro
    // host; CORS sigue gobernando las respuestas de API con datos.
    'Cross-Origin-Resource-Policy': 'cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(), payment=()',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
  });
  res.removeHeader('X-Powered-By');
  next();
}

function fingerprint(value) {
  return crypto.createHash('sha256').update(String(value)).digest('base64url');
}

function authIdentity(req) {
  const email = typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';
  const deviceId = typeof req.body?.deviceId === 'string' ? req.body.deviceId.trim() : '';
  return {
    account: fingerprint(email || `device:${deviceId || 'missing'}`),
    installation: fingerprint(deviceId || `account:${email || 'missing'}`),
  };
}

function authLimit({ limit, key }) {
  return rateLimit({
    windowMs: 15 * 60 * 1000,
    limit,
    keyGenerator: req => authIdentity(req)[key],
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skipSuccessfulRequests: true,
    message: { error: 'Demasiados intentos de acceso para esta cuenta o instalacion. Intenta mas tarde.' },
  });
}

function createAuthLimiters() {
  // Dos defensas independientes, ninguna basada en IP/NAT: una cuenta no se
  // puede atacar desde muchas instalaciones y una instalacion no puede rotar
  // correos ilimitadamente. Esto permite que todo el campus inicie sesion.
  return [
    authLimit({ limit: 15, key: 'account' }),
    authLimit({ limit: 60, key: 'installation' }),
  ];
}

function createAnonymousSessionLimiter() {
  return rateLimit({
    windowMs: 60 * 60 * 1000,
    limit: 10,
    keyGenerator: req => fingerprint(
      typeof req.body?.deviceId === 'string' ? req.body.deviceId.trim() : 'missing-device',
    ),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: { error: 'Demasiadas sesiones de invitado para esta instalación.' },
  });
}

function createChatMessageLimiter() {
  return rateLimit({
    windowMs: 5 * 60 * 1000,
    limit: 40,
    // Se monta después de requireAuth. Así cada cuenta o invitado firmado
    // tiene su propio cupo y una red universitaria compartida no se bloquea.
    keyGenerator: req => fingerprint(`chat:${req.user?.id || 'missing'}`),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: {
      error: 'Demasiados mensajes enviados. Espera unos minutos antes de continuar.',
    },
  });
}

function createReportLimiter() {
  // Nunca agrupar por IP: miles de personas pueden compartir la salida de la
  // universidad. La cuenta o sesion de invitado firmada es la unidad real.
  return rateLimit({
    windowMs: 60 * 60 * 1000,
    limit: 5,
    keyGenerator: req => fingerprint(`report:${req.user?.id || 'missing'}`),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: {
      error: 'Has enviado varios reportes. Espera un poco antes de enviar otro.',
    },
  });
}

function configureProxy(app) {
  // Evita el parser anidado `qs`: la API solo usa pares clave=valor. Ademas
  // elimina de la superficie los objetos profundos y arrays construidos con
  // notacion de corchetes que suelen usarse para agotamiento de recursos.
  app.set('query parser', 'simple');
  const raw = String(process.env.TRUST_PROXY || '').trim();
  if (!raw) return;
  if (!/^\d+$/.test(raw) || Number(raw) < 1 || Number(raw) > 10) {
    throw new Error('TRUST_PROXY debe ser un numero entre 1 y 10.');
  }
  app.set('trust proxy', Number(raw));
}

module.exports = {
  allowedOrigins,
  configuredAdminOrigin,
  corsOrigin,
  adminCorsOrigin,
  securityHeaders,
  authIdentity,
  createAuthLimiters,
  createAnonymousSessionLimiter,
  createChatMessageLimiter,
  createReportLimiter,
  configureProxy,
};
