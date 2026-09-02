const rateLimit = require('express-rate-limit');
const crypto = require('crypto');

function allowedOrigins() {
  return new Set([process.env.ALLOWED_ORIGINS, process.env.APP_PUBLIC_URL]
    .filter(Boolean).join(',')
    .split(',').map(value => value.trim()).filter(Boolean).map(value => {
      try { return new URL(value).origin; } catch { return null; }
    }).filter(Boolean));
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

module.exports = { allowedOrigins, corsOrigin, securityHeaders, authIdentity, createAuthLimiters, configureProxy };
