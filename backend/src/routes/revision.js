// API privada para la página de revisión. No es un sistema de usuarios: la
// página Next del mismo servidor guarda la llave en su entorno y la reenvía.
const crypto = require('crypto');
const express = require('express');
const rateLimit = require('express-rate-limit');
const path = require('path');
const {
  registrarAuditoriaAdmin
} = require('../adminAudit');
const {
  refrescarSellers
} = require('../data');
const db = require('../database');
const {
  obtenerExpedienteVerificacion
} = require('../verificationDossier');
const MAX_MOTIVO = 500;
const MIN_MOTIVO_ADMIN = 10;
const MAX_BUSQUEDA = 100;
const MAX_ACTOR = 100;
const MAX_ACCOUNT_ID = 180;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');
function parsearJson(valor, respaldo) {
  if (!valor) return respaldo;
  try {
    return JSON.parse(valor);
  } catch {
    return respaldo;
  }
}
function llaveValida(req) {
  const esperada = process.env.REVISION_API_KEY;
  const recibida = req.get('x-revision-api-key');
  if (!esperada || !recibida) return false;
  const a = Buffer.from(esperada);
  const b = Buffer.from(recibida);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
function requireRevisionKey(req, res, next) {
  if (!llaveValida(req)) return res.status(401).json({
    error: 'No autorizado.'
  });
  next();
}
function leerMotivo(req, obligatorio) {
  const motivo = String(req.body?.reason || '').trim();
  if (obligatorio && !motivo || motivo.length > MAX_MOTIVO) return null;
  return motivo || null;
}
function leerMotivoAdmin(req) {
  const motivo = String(req.body?.reason || '').trim();
  if (motivo.length < MIN_MOTIVO_ADMIN || motivo.length > MAX_MOTIVO) return null;
  return motivo;
}
function actorRevision(req) {
  if (req.admin?.username) return req.admin.username;
  const actor = String(req.get('x-revision-actor') || 'panel-revision').trim();
  if (!actor || actor.length > MAX_ACTOR || /[\u0000-\u001f\u007f]/.test(actor)) {
    return 'panel-revision';
  }
  return actor;
}
function idCuentaValido(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= MAX_ACCOUNT_ID && !/[\u0000-\u001f\u007f]/.test(value);
}
function rolCuenta(row) {
  if (row.tipoCuenta === 'negocio') return 'negocio';
  return row.tipoVerificacion === 'empleado' ? 'empleado' : 'estudiante';
}
function escapeLike(value) {
  return value.replace(/[\\%_]/g, match => '\\' + match);
}
async function obtenerSolicitud(database, id, estado) {
  return await database.prepare(`SELECT v.usuario_id AS id, v.estado,
       v.responsable_negocio AS responsibleName,
       COALESCE(NULLIF(v.nombre_negocio, ''), s.name) AS name,
       s.businessCategory, s.businessDescription, s.phone, s.verified
     FROM verificaciones v
     JOIN sellers s ON s.id = v.usuario_id
     WHERE v.usuario_id = ? AND v.tipo_cuenta = 'negocio'
       AND v.estado = ?`).get(id, estado);
}
async function registrarDecision(database, solicitud, accion, motivo, decididoEn) {
  const solicitudGuardada = await database.prepare('SELECT solicitud_json FROM verificaciones WHERE usuario_id = ?').get(solicitud.id);
  const expediente = parsearJson(solicitudGuardada?.solicitud_json, null) || (await obtenerExpedienteVerificacion(database, solicitud.id));
  await database.prepare(`INSERT INTO verification_review_log (
       usuario_id, accion, motivo, nombre_negocio, categoria_negocio,
       responsable_negocio, decidido_en, solicitud_json
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).run(solicitud.id, accion, motivo, solicitud.name || solicitud.id, solicitud.businessCategory || null, solicitud.responsibleName || null, decididoEn, expediente ? JSON.stringify(expediente) : null);
}
function router({
  authenticate = requireRevisionKey
} = {}) {
  const api = express.Router();
  api.use(authenticate);
  api.use(rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 300,
    // El panel autenticado se limita por administrador. El acceso legacy de
    // pruebas se limita por su llave compartida. Ninguno usa la IP.
    keyGenerator: req => crypto.createHash('sha256').update(String(
      req.admin?.id ? `admin:${req.admin.id}` : `revision:${req.get('x-revision-api-key') || 'missing'}`
    )).digest('base64url'),
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: {
      error: 'Demasiadas solicitudes al panel. Intenta más tarde.'
    }
  }));
  api.use((_req, res, next) => {
    res.set({
      'Cache-Control': 'private, no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    next();
  });
  api.get('/documento', async (req, res) => {
    const fileUrl = String(req.query.path || '');
    if (!/^\/uploads\/[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(fileUrl)) {
      return res.status(400).json({
        error: 'Documento inválido.'
      });
    }
    const database = db.getDb();
    const esDocumento = await database.prepare('SELECT 1 FROM verification_documents WHERE file_url = ? LIMIT 1').get(fileUrl);
    const esLogo = await database.prepare('SELECT 1 FROM sellers WHERE logoUrl = ? OR avatarUrl = ? LIMIT 1').get(fileUrl, fileUrl);
    if (!esDocumento && !esLogo) {
      return res.status(404).json({
        error: 'Documento no encontrado.'
      });
    }
    res.set({
      'Cache-Control': 'private, no-store',
      'Content-Disposition': 'inline',
      'X-Content-Type-Options': 'nosniff'
    });
    return res.sendFile(path.basename(fileUrl), {
      root: UPLOADS_DIR,
      dotfiles: 'deny'
    }, error => {
      if (error && !res.headersSent) {
        res.status(error.statusCode === 404 ? 404 : 500).json({
          error: error.statusCode === 404 ? 'Documento no encontrado.' : 'No se pudo cargar el documento.'
        });
      }
    });
  });
  api.get('/cuentas', async (req, res) => {
    const tipo = String(req.query.type || 'all');
    const estado = String(req.query.verified || 'all');
    const busquedaCruda = String(req.query.q || '').trim();
    if (!['all', 'business', 'student', 'employee'].includes(tipo)) {
      return res.status(400).json({
        error: 'Tipo de cuenta inválido.'
      });
    }
    if (!['all', 'verified', 'unverified'].includes(estado)) {
      return res.status(400).json({
        error: 'Estado de verificación inválido.'
      });
    }
    if (busquedaCruda.length > MAX_BUSQUEDA) {
      return res.status(400).json({
        error: `La búsqueda no puede superar ${MAX_BUSQUEDA} caracteres.`
      });
    }
    const paginaPedida = Number.parseInt(String(req.query.page || '1'), 10);
    const limitePedido = Number.parseInt(String(req.query.limit || '25'), 10);
    const requestedPage = Number.isSafeInteger(paginaPedida) && paginaPedida > 0 ? paginaPedida : 1;
    const limit = Number.isSafeInteger(limitePedido) ? Math.min(100, Math.max(10, limitePedido)) : 25;
    const roleSql = `CASE
      WHEN s.tipo_cuenta = 'negocio' THEN 'negocio'
      WHEN COALESCE(v.tipo_verificacion, s.tipo_verificacion) = 'empleado'
        THEN 'empleado'
      ELSE 'estudiante'
    END`;
    const condiciones = ["s.tipo_cuenta IN ('negocio','estudiante')", '(COALESCE(s.verified, 0) = 1 OR v.usuario_id IS NOT NULL)'];
    const params = [];
    if (tipo !== 'all') {
      condiciones.push(`${roleSql} = ?`);
      params.push(tipo === 'business' ? 'negocio' : tipo === 'employee' ? 'empleado' : 'estudiante');
    }
    if (estado !== 'all') {
      condiciones.push('COALESCE(s.verified, 0) = ?');
      params.push(estado === 'verified' ? 1 : 0);
    }
    if (busquedaCruda) {
      const patron = `%${escapeLike(busquedaCruda.toLowerCase())}%`;
      condiciones.push(`(
        lower(s.name) LIKE ? ESCAPE '\\'
        OR lower(COALESCE(s.email, '')) LIKE ? ESCAPE '\\'
        OR lower(s.id) LIKE ? ESCAPE '\\'
        OR lower(COALESCE(v.correo_institucional, '')) LIKE ? ESCAPE '\\'
      )`);
      params.push(patron, patron, patron, patron);
    }
    const database = db.getDb();
    const whereSql = condiciones.join(' AND ');
    const total = (await database.prepare(`SELECT COUNT(*) AS total
       FROM sellers s
       LEFT JOIN verificaciones v ON v.usuario_id = s.id
       WHERE ${whereSql}`).get(...params)).total;
    const totalPages = Math.max(1, Math.ceil(total / limit));
    const page = Math.min(requestedPage, totalPages);
    const offset = (page - 1) * limit;
    const resumen = await database.prepare(`SELECT COUNT(*) AS total,
         COALESCE(SUM(CASE WHEN COALESCE(s.verified, 0) = 1 THEN 1 ELSE 0 END), 0)
           AS verified
       FROM sellers s
       LEFT JOIN verificaciones v ON v.usuario_id = s.id
       WHERE s.tipo_cuenta IN ('negocio','estudiante')
         AND (COALESCE(s.verified, 0) = 1 OR v.usuario_id IS NOT NULL)`).get();
    const rows = await database.prepare(`SELECT s.id, s.name, s.email, s.created_at AS createdAt,
         s.tipo_cuenta AS tipoCuenta,
         COALESCE(v.tipo_verificacion, s.tipo_verificacion) AS tipoVerificacion,
         COALESCE(s.verified, 0) AS verified,
         v.estado AS verificationState,
         v.fecha_verificacion AS verifiedAt,
         v.identidad_confirmada_en AS identityConfirmedAt,
         COALESCE(v.correo_institucional, s.email) AS contactEmail,
         a.action AS lastAction, a.reason AS lastReason,
         a.actor AS lastActor, a.decided_at AS lastChangedAt,
         EXISTS(
           SELECT 1 FROM verification_review_log h
           WHERE h.usuario_id = s.id
             AND h.accion IN ('approved','revoked','restored')
         ) AS hasPriorReview
       FROM sellers s
       LEFT JOIN verificaciones v ON v.usuario_id = s.id
       LEFT JOIN verification_admin_log a ON a.id = (
         SELECT al.id FROM verification_admin_log al
         WHERE al.usuario_id = s.id
         ORDER BY al.decided_at DESC, al.id DESC
         LIMIT 1
       )
       WHERE ${whereSql}
       ORDER BY COALESCE(s.verified, 0) DESC,
         COALESCE(v.fecha_verificacion, a.decided_at, s.created_at) DESC,
         lower(s.name), s.id
       LIMIT ? OFFSET ?`).all(...params, limit, offset);
    return res.json({
      accounts: rows.map(row => {
        const verified = !!row.verified;
        const canVerify = !verified && row.verificationState === 'rechazado' && (!!row.identityConfirmedAt || !!row.hasPriorReview);
        let verificationBlockedReason = null;
        if (!verified && !canVerify) {
          verificationBlockedReason = row.verificationState === 'pendiente' ? row.tipoCuenta === 'negocio' ? 'La solicitud pendiente debe aprobarse desde la pestaña Pendientes.' : 'La cuenta debe completar su verificación institucional.' : 'No existe una verificación previa comprobada para reactivar.';
        }
        return {
          id: row.id,
          name: row.name,
          email: row.contactEmail || row.email || null,
          role: rolCuenta(row),
          verified,
          verificationState: row.verificationState || null,
          verifiedAt: row.verifiedAt || null,
          createdAt: row.createdAt || null,
          canVerify,
          canUnverify: verified,
          verificationBlockedReason,
          lastChange: row.lastAction ? {
            action: row.lastAction,
            reason: row.lastReason,
            actor: row.lastActor,
            decidedAt: row.lastChangedAt
          } : null
        };
      }),
      pagination: {
        page,
        limit,
        total,
        totalPages
      },
      summary: {
        total: resumen.total,
        verified: resumen.verified,
        unverified: resumen.total - resumen.verified
      }
    });
  });

  // Expediente amplio bajo demanda. Nunca expone hashes, codigos OTP,
  // identificadores de Google ni tokens de pago/push.
  api.get('/cuentas/:id', async (req, res) => {
    const accountId = req.params.id;
    if (!idCuentaValido(accountId)) return res.status(400).json({
      error: 'Cuenta invalida.'
    });
    const database = db.getDb();
    const account = await database.prepare(`SELECT id, name, email, phone, avatarInitials, major, isBusiness,
       logoUrl, avatarUrl, rating, reviews, verified, businessDescription,
       businessCategory, businessHours, location_lat AS locationLat,
       location_lng AS locationLng, paymentMethods, tipo_cuenta AS accountType,
       carrera, tipo_verificacion AS verificationType, colorAcento AS accentColor,
       producto_fijado_id AS pinnedProductId,
       median_response_minutes AS medianResponseMinutes,
       facebook_url AS facebook, instagram_url AS instagram,
       whatsapp_number AS whatsapp, tiktok_url AS tiktok, twitter_url AS twitter,
       last_active AS lastActive, show_online_status AS showOnlineStatus,
       auth_provider AS authProvider, socio_fundador AS foundingPartner,
       created_at AS createdAt, insignias_ocultas AS hiddenBadges
       FROM sellers WHERE id = ?`).get(accountId);
    if (!account) return res.status(404).json({
      error: 'Cuenta no encontrada.'
    });
    const verification = (await database.prepare(`SELECT id, tipo_cuenta AS accountType, estado AS status,
       fecha_verificacion AS verifiedAt, creado_en AS createdAt,
       correo_institucional AS institutionalEmail, matricula AS enrollment,
       nombre_negocio AS businessName, responsable_negocio AS responsibleName,
       ubicacion_lat AS locationLat, ubicacion_lng AS locationLng,
       link_red_social AS submittedSocialLink, telefono AS phone,
       motivo_rechazo AS rejectionReason, campo_rechazado AS rejectedField,
       intentos_envio AS sendAttempts, ventana_envio_inicio AS sendingWindowStartedAt,
       intentos_confirmacion AS confirmationAttempts, carrera,
       tipo_verificacion AS verificationType,
       identidad_confirmada_en AS identityConfirmedAt
       FROM verificaciones WHERE usuario_id = ?`).get(accountId)) || null;
    const documents = await database.prepare(`SELECT id, doc_type AS type, file_url AS url, original_name AS originalName,
       mime_type AS mimeType, uploaded_at AS uploadedAt
       FROM verification_documents WHERE usuario_id = ? ORDER BY uploaded_at DESC, id DESC`).all(accountId);
    const verificationHistory = await database.prepare(`SELECT id, accion AS action, motivo AS reason, nombre_negocio AS businessName,
       categoria_negocio AS businessCategory, responsable_negocio AS responsibleName,
       decidido_en AS decidedAt FROM verification_review_log
       WHERE usuario_id = ? ORDER BY decidido_en DESC, id DESC`).all(accountId);
    const adminHistory = await database.prepare(`SELECT id, action, previous_verified AS previousVerified,
       new_verified AS newVerified, reason, actor, decided_at AS decidedAt
       FROM verification_admin_log WHERE usuario_id = ? ORDER BY decided_at DESC, id DESC`).all(accountId);
    const badges = await database.prepare(`SELECT clave AS key, otorgada_en AS awardedAt FROM insignias_otorgadas
       WHERE seller_id = ? ORDER BY otorgada_en DESC`).all(accountId);
    const count = async (sql, ...params) => (await database.prepare(sql).get(...params)).total;
    const activity = {
      products: await count('SELECT COUNT(*) AS total FROM products WHERE seller = ?', accountId),
      wantedPosts: await count('SELECT COUNT(*) AS total FROM wanted_posts WHERE user_id = ?', accountId),
      purchases: await count('SELECT COUNT(*) AS total FROM orders WHERE buyer_id = ?', accountId),
      sales: await count('SELECT COUNT(*) AS total FROM orders WHERE vendor_id = ?', accountId),
      comments: await count('SELECT COUNT(*) AS total FROM product_comments WHERE user_id = ?', accountId),
      questions: await count('SELECT COUNT(*) AS total FROM product_questions WHERE asked_by = ?', accountId),
      conversations: await count('SELECT COUNT(*) AS total FROM conversations WHERE buyer_id = ? OR seller_id = ?', accountId, accountId),
      notifications: await count('SELECT COUNT(*) AS total FROM notifications WHERE user_id = ?', accountId)
    };
    return res.json({
      account,
      verification,
      documents,
      badges,
      activity,
      verificationHistory,
      adminHistory
    });
  });
  api.post('/cuentas/:id/verificacion', async (req, res) => {
    const accountId = req.params.id;
    const targetVerified = req.body?.verified;
    const expectedVerified = req.body?.expectedVerified;
    const requestId = String(req.body?.requestId || '').trim();
    const reason = leerMotivoAdmin(req);
    if (!idCuentaValido(accountId)) {
      return res.status(400).json({
        error: 'ID de cuenta inválido.'
      });
    }
    if (typeof targetVerified !== 'boolean' || typeof expectedVerified !== 'boolean') {
      return res.status(400).json({
        error: 'Estado de verificación inválido.'
      });
    }
    if (!UUID.test(requestId)) {
      return res.status(400).json({
        error: 'Identificador de operación inválido.'
      });
    }
    if (!reason) {
      return res.status(400).json({
        error: `El motivo debe tener entre ${MIN_MOTIVO_ADMIN} y ${MAX_MOTIVO} caracteres.`
      });
    }
    const database = db.getDb();
    const decidedAt = new Date().toISOString();
    const actor = actorRevision(req);
    const resultado = await database.transaction(async () => {
      const repetida = await database.prepare(`SELECT usuario_id AS userId, new_verified AS newVerified
         FROM verification_admin_log WHERE request_id = ?`).get(requestId);
      if (repetida) {
        if (repetida.userId === accountId && !!repetida.newVerified === targetVerified) {
          return {
            replayed: true,
            changed: false
          };
        }
        return {
          error: 'Ese identificador de operación ya fue utilizado.',
          status: 409
        };
      }
      let account = await database.prepare(`SELECT s.id, s.name, s.created_at AS createdAt,
           s.tipo_cuenta AS tipoCuenta, s.tipo_verificacion AS sellerVerificationType,
           COALESCE(s.verified, 0) AS verified,
           v.estado AS verificationState, v.fecha_verificacion AS verifiedAt,
           v.identidad_confirmada_en AS identityConfirmedAt,
           v.correo_institucional AS institutionalEmail, v.matricula,
           v.carrera, v.tipo_verificacion AS verificationType
         FROM sellers s
         LEFT JOIN verificaciones v ON v.usuario_id = s.id
         WHERE s.id = ?`).get(accountId);
      if (!account) return {
        error: 'Cuenta no encontrada.',
        status: 404
      };
      if (!['negocio', 'estudiante'].includes(account.tipoCuenta)) {
        return {
          error: 'Las cuentas externas no pueden recibir la verificación.',
          status: 403
        };
      }
      const currentVerified = !!account.verified;
      if (currentVerified !== expectedVerified) {
        return {
          error: 'El estado cambió desde que abriste la tabla. Recárgala antes de continuar.',
          status: 409
        };
      }
      if (currentVerified === targetVerified) {
        return {
          error: targetVerified ? 'La cuenta ya está verificada.' : 'La cuenta ya está sin verificar.',
          status: 409
        };
      }
      const role = rolCuenta({
        tipoCuenta: account.tipoCuenta,
        tipoVerificacion: account.verificationType || account.sellerVerificationType
      });
      if (targetVerified) {
        const hasPriorReview = await database.prepare(`SELECT 1 FROM verification_review_log
           WHERE usuario_id = ?
             AND accion IN ('approved','revoked','restored')
           LIMIT 1`).get(accountId);
        if (account.verificationState !== 'rechazado' || !account.identityConfirmedAt && !hasPriorReview) {
          return {
            error: account.verificationState === 'pendiente' ? 'La verificación pendiente debe completar su flujo normal.' : 'No hay una identidad previamente comprobada que se pueda reactivar.',
            status: 409
          };
        }
        if (account.tipoCuenta === 'estudiante') {
          const correo = account.institutionalEmail || null;
          const matricula = account.matricula || null;
          const duplicada = await database.prepare(`SELECT usuario_id FROM verificaciones
             WHERE usuario_id != ? AND estado = 'verificado'
               AND (
                 (? IS NOT NULL AND correo_institucional = ?)
                 OR (? IS NOT NULL AND matricula = ?)
               )
             LIMIT 1`).get(accountId, correo, correo, matricula, matricula);
          if (duplicada) {
            return {
              error: 'El correo institucional o la matrícula ya verifican otra cuenta.',
              status: 409
            };
          }
        }
        await database.prepare(`UPDATE verificaciones SET estado = 'verificado',
             fecha_verificacion = ?, motivo_rechazo = NULL,
             campo_rechazado = NULL WHERE usuario_id = ?`).run(decidedAt, accountId);
        if (account.tipoCuenta === 'estudiante') {
          const verificationType = account.verificationType || account.sellerVerificationType || 'estudiante';
          await database.prepare(`UPDATE sellers SET verified = 1, carrera = ?,
             tipo_verificacion = ? WHERE id = ?`).run(account.carrera || null, verificationType, accountId);
        } else {
          await database.prepare('UPDATE sellers SET verified = 1 WHERE id = ?').run(accountId);
        }
      } else {
        if (!account.verificationState) {
          const verificationType = account.tipoCuenta === 'estudiante' ? account.sellerVerificationType || 'estudiante' : null;
          await database.prepare(`INSERT INTO verificaciones (
               usuario_id, tipo_cuenta, estado, fecha_verificacion, creado_en,
               identidad_confirmada_en, tipo_verificacion
             ) VALUES (?, ?, 'verificado', ?, ?, ?, ?)`).run(accountId, account.tipoCuenta, decidedAt, account.createdAt || decidedAt, decidedAt, verificationType);
          account = {
            ...account,
            verificationState: 'verificado'
          };
        } else {
          await database.prepare(`UPDATE verificaciones SET identidad_confirmada_en =
               COALESCE(identidad_confirmada_en, fecha_verificacion, ?)
             WHERE usuario_id = ?`).run(decidedAt, accountId);
        }
        await database.prepare(`UPDATE verificaciones SET estado = 'rechazado',
             fecha_verificacion = NULL, motivo_rechazo = ?,
             campo_rechazado = 'revision_manual' WHERE usuario_id = ?`).run(reason, accountId);
        await database.prepare('UPDATE sellers SET verified = 0 WHERE id = ?').run(accountId);
      }
      await database.prepare(`INSERT INTO verification_admin_log (
           request_id, usuario_id, account_name, account_type, action,
           previous_verified, new_verified, reason, actor, decided_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(requestId, accountId, account.name || accountId, role, targetVerified ? 'verified' : 'unverified', currentVerified ? 1 : 0, targetVerified ? 1 : 0, reason, actor, decidedAt);
      if (req.admin) {
        await registrarAuditoriaAdmin(database, req, {
          action: 'verification.set',
          entityType: 'account',
          entityId: accountId,
          details: {
            requestId,
            role,
            previousVerified: currentVerified,
            newVerified: targetVerified,
            reason
          },
          createdAt: decidedAt
        });
      }
      return {
        changed: true,
        replayed: false
      };
    })();
    if (resultado.error) {
      return res.status(resultado.status).json({
        error: resultado.error
      });
    }
    if (resultado.changed) await refrescarSellers();
    return res.json({
      status: targetVerified ? 'verified' : 'unverified',
      replayed: resultado.replayed
    });
  });
  api.get('/verificaciones', async (req, res) => {
    if (req.query.status && req.query.status !== 'pending') {
      return res.status(400).json({
        error: 'Solo se admite status=pending.'
      });
    }
    const rows = await db.getDb().prepare(`SELECT v.usuario_id AS id, v.creado_en AS submittedAt,
         v.nombre_negocio AS requestedName,
         v.responsable_negocio AS responsibleName,
         v.ubicacion_lat AS requestedLat, v.ubicacion_lng AS requestedLng,
         v.link_red_social AS submittedSocialLink,
         v.solicitud_json AS requestJson,
         s.name, s.businessCategory, s.businessDescription, s.phone, s.email,
         s.logoUrl, s.created_at AS accountCreatedAt,
         s.businessHours, s.paymentMethods,
         s.location_lat AS profileLat, s.location_lng AS profileLng,
         s.facebook_url AS facebookUrl, s.instagram_url AS instagramUrl,
         s.whatsapp_number AS whatsappNumber, s.tiktok_url AS tiktokUrl,
         s.twitter_url AS twitterUrl
       FROM verificaciones v
       JOIN sellers s ON s.id = v.usuario_id
       WHERE v.tipo_cuenta = 'negocio' AND v.estado = 'pendiente'
         AND v.responsable_negocio IS NOT NULL AND s.verified = 0
       ORDER BY v.creado_en ASC`).all();
    const ordenDocumento = {
      responsible_ine_front: 0,
      responsible_ine_back: 1,
      additional_evidence: 2
    };
    const requests = await Promise.all(rows.map(async row => {
      const expedienteGuardado = parsearJson(row.requestJson, null);
      if (expedienteGuardado) return expedienteGuardado;
      const vistos = new Set();
      const documents = (await db.getDb().prepare('SELECT id, doc_type AS type, file_url AS url, ' + 'mime_type AS mimeType, content_hash AS contentHash ' + 'FROM verification_documents WHERE usuario_id = ? ' + 'ORDER BY uploaded_at DESC, id DESC').all(row.id)).filter(document => {
        const clave = document.type === 'additional_evidence' ? document.type + ':' + (document.contentHash || document.id) : document.type;
        if (vistos.has(clave)) return false;
        vistos.add(clave);
        return true;
      }).map(document => ({
        id: document.id,
        type: document.type,
        url: document.url,
        mimeType: document.mimeType
      })).sort((a, b) => (ordenDocumento[a.type] ?? 99) - (ordenDocumento[b.type] ?? 99));
      const tieneUbicacionSolicitud = Number.isFinite(row.requestedLat) && Number.isFinite(row.requestedLng);
      const tieneUbicacionPerfil = Number.isFinite(row.profileLat) && Number.isFinite(row.profileLng);
      return {
        id: row.id,
        submittedAt: row.submittedAt || null,
        business: {
          name: row.requestedName || row.name,
          profileName: row.name || null,
          category: row.businessCategory || null,
          responsibleName: row.responsibleName || null,
          description: row.businessDescription || null,
          phone: row.phone || null,
          email: row.email || null,
          logoUrl: row.logoUrl || null,
          accountCreatedAt: row.accountCreatedAt || null,
          businessHours: parsearJson(row.businessHours, {}),
          paymentMethods: parsearJson(row.paymentMethods, [])
        },
        location: tieneUbicacionSolicitud ? {
          lat: row.requestedLat,
          lng: row.requestedLng,
          source: 'request'
        } : tieneUbicacionPerfil ? {
          lat: row.profileLat,
          lng: row.profileLng,
          source: 'profile'
        } : null,
        socialLinks: {
          submitted: row.submittedSocialLink || null,
          facebook: row.facebookUrl || null,
          instagram: row.instagramUrl || null,
          whatsapp: row.whatsappNumber || null,
          tiktok: row.tiktokUrl || null,
          twitter: row.twitterUrl || null
        },
        documents
      };
    }));
    return res.json({
      requests
    });
  });
  api.get('/historial', async (_req, res) => {
    const database = db.getDb();
    const rows = await database.prepare(`SELECT h.id, h.usuario_id AS userId, h.accion AS action,
         h.motivo AS reason, h.nombre_negocio AS businessName,
         h.categoria_negocio AS businessCategory,
         h.responsable_negocio AS responsibleName,
         h.decidido_en AS decidedAt, h.solicitud_json AS requestJson,
         s.id AS accountId, COALESCE(s.verified, 0) AS currentVerified,
         v.estado AS currentVerificationState
       FROM verification_review_log h
       LEFT JOIN sellers s ON s.id = h.usuario_id
       LEFT JOIN verificaciones v ON v.usuario_id = h.usuario_id
       ORDER BY h.decidido_en DESC, h.id DESC`).all();
    const expedientesActuales = new Map();
    const entries = await Promise.all(rows.map(async row => {
        const expedienteGuardado = parsearJson(row.requestJson, null);
        if (!expedientesActuales.has(row.userId)) {
          expedientesActuales.set(row.userId, await obtenerExpedienteVerificacion(database, row.userId));
        }
        const expedienteActual = expedientesActuales.get(row.userId);
        const request = expedienteGuardado || (expedienteActual ? JSON.parse(JSON.stringify(expedienteActual)) : null);

        // Las decisiones anteriores a solicitud_json usan el mejor expediente
        // aún disponible, pero conservan los tres datos que sí eran históricos.
        if (!expedienteGuardado && request) {
          request.business = {
            ...request.business,
            name: row.businessName,
            category: row.businessCategory || request.business.category || null,
            responsibleName: row.responsibleName || request.business.responsibleName || null
          };
        }
        const accountExists = !!row.accountId;
        const currentVerified = !!row.currentVerified;
        return {
          id: row.id,
          userId: row.userId,
          action: row.action,
          reason: row.reason || null,
          business: {
            name: row.businessName,
            category: row.businessCategory || null,
            responsibleName: row.responsibleName || null
          },
          decidedAt: row.decidedAt,
          currentVerified,
          canRevoke: accountExists && currentVerified,
          canRestore: accountExists && !currentVerified && row.currentVerificationState === 'rechazado',
          request
        };
      }));
    return res.json({ entries });
  });
  api.post('/verificaciones/:id/approve', async (req, res) => {
    const motivo = leerMotivo(req, false);
    if (motivo === null && String(req.body?.reason || '').trim().length > MAX_MOTIVO) {
      return res.status(400).json({
        error: `La nota no puede superar ${MAX_MOTIVO} caracteres.`
      });
    }
    const database = db.getDb();
    const decididoEn = new Date().toISOString();
    const updated = await database.transaction(async () => {
      const solicitud = await obtenerSolicitud(database, req.params.id, 'pendiente');
      if (!solicitud || solicitud.verified) return false;
      await database.prepare(`UPDATE verificaciones SET estado = 'verificado', fecha_verificacion = ?,
         identidad_confirmada_en = COALESCE(identidad_confirmada_en, ?),
         motivo_rechazo = NULL, campo_rechazado = NULL WHERE usuario_id = ?`).run(decididoEn, decididoEn, solicitud.id);
      await database.prepare('UPDATE sellers SET verified = 1 WHERE id = ?').run(solicitud.id);
      await registrarDecision(database, solicitud, 'approved', motivo, decididoEn);
      if (req.admin) {
        await registrarAuditoriaAdmin(database, req, {
          action: 'verification.approve',
          entityType: 'verification',
          entityId: solicitud.id,
          details: {
            previousStatus: 'pendiente',
            newStatus: 'verificado',
            previousVerified: false,
            newVerified: true,
            reason: motivo
          },
          createdAt: decididoEn
        });
      }
      return true;
    })();
    if (!updated) return res.status(404).json({
      error: 'Solicitud pendiente no encontrada.'
    });
    await refrescarSellers();
    return res.json({
      status: 'approved'
    });
  });
  api.post('/verificaciones/:id/reject', async (req, res) => {
    const motivo = leerMotivo(req, true);
    if (!motivo) {
      return res.status(400).json({
        error: `El motivo es obligatorio y no puede superar ${MAX_MOTIVO} caracteres.`
      });
    }
    const database = db.getDb();
    const decididoEn = new Date().toISOString();
    const updated = await database.transaction(async () => {
      const solicitud = await obtenerSolicitud(database, req.params.id, 'pendiente');
      if (!solicitud || solicitud.verified) return false;
      await database.prepare(`UPDATE verificaciones SET estado = 'rechazado', fecha_verificacion = NULL,
         motivo_rechazo = ?, campo_rechazado = NULL WHERE usuario_id = ?`).run(motivo, solicitud.id);
      await database.prepare('UPDATE sellers SET verified = 0 WHERE id = ?').run(solicitud.id);
      await registrarDecision(database, solicitud, 'rejected', motivo, decididoEn);
      if (req.admin) {
        await registrarAuditoriaAdmin(database, req, {
          action: 'verification.reject',
          entityType: 'verification',
          entityId: solicitud.id,
          details: {
            previousStatus: 'pendiente',
            newStatus: 'rechazado',
            previousVerified: false,
            newVerified: false,
            reason: motivo
          },
          createdAt: decididoEn
        });
      }
      return true;
    })();
    if (!updated) return res.status(404).json({
      error: 'Solicitud pendiente no encontrada.'
    });
    await refrescarSellers();
    return res.json({
      status: 'rejected'
    });
  });
  api.post('/verificaciones/:id/revoke', async (req, res) => {
    const motivo = leerMotivo(req, true);
    if (!motivo) {
      return res.status(400).json({
        error: `El motivo es obligatorio y no puede superar ${MAX_MOTIVO} caracteres.`
      });
    }
    const database = db.getDb();
    const decididoEn = new Date().toISOString();
    const revoked = await database.transaction(async () => {
      const solicitud = await obtenerSolicitud(database, req.params.id, 'verificado');
      if (!solicitud || !solicitud.verified) return false;
      await database.prepare(`UPDATE verificaciones SET estado = 'rechazado', fecha_verificacion = NULL,
         motivo_rechazo = ?, campo_rechazado = 'revision_manual'
         WHERE usuario_id = ?`).run(motivo, solicitud.id);
      await database.prepare('UPDATE sellers SET verified = 0 WHERE id = ?').run(solicitud.id);
      await registrarDecision(database, solicitud, 'revoked', motivo, decididoEn);
      if (req.admin) {
        await registrarAuditoriaAdmin(database, req, {
          action: 'verification.revoke',
          entityType: 'verification',
          entityId: solicitud.id,
          details: {
            previousStatus: 'verificado',
            newStatus: 'rechazado',
            previousVerified: true,
            newVerified: false,
            reason: motivo
          },
          createdAt: decididoEn
        });
      }
      return true;
    })();
    if (!revoked) {
      return res.status(409).json({
        error: 'La cuenta ya no tiene una verificación activa.'
      });
    }
    await refrescarSellers();
    return res.json({
      status: 'revoked'
    });
  });
  api.post('/verificaciones/:id/restore', async (req, res) => {
    const motivo = leerMotivo(req, false);
    if (motivo === null && String(req.body?.reason || '').trim().length > MAX_MOTIVO) {
      return res.status(400).json({
        error: `La nota no puede superar ${MAX_MOTIVO} caracteres.`
      });
    }
    const database = db.getDb();
    const decididoEn = new Date().toISOString();
    const restored = await database.transaction(async () => {
      const solicitud = await obtenerSolicitud(database, req.params.id, 'rechazado');
      if (!solicitud || solicitud.verified) return false;
      await database.prepare(`UPDATE verificaciones SET estado = 'verificado', fecha_verificacion = ?,
         identidad_confirmada_en = COALESCE(identidad_confirmada_en, ?),
         motivo_rechazo = NULL, campo_rechazado = NULL WHERE usuario_id = ?`).run(decididoEn, decididoEn, solicitud.id);
      await database.prepare('UPDATE sellers SET verified = 1 WHERE id = ?').run(solicitud.id);
      await registrarDecision(database, solicitud, 'restored', motivo, decididoEn);
      if (req.admin) {
        await registrarAuditoriaAdmin(database, req, {
          action: 'verification.restore',
          entityType: 'verification',
          entityId: solicitud.id,
          details: {
            previousStatus: 'rechazado',
            newStatus: 'verificado',
            previousVerified: false,
            newVerified: true,
            reason: motivo
          },
          createdAt: decididoEn
        });
      }
      return true;
    })();
    if (!restored) {
      return res.status(409).json({
        error: 'La cuenta no está disponible para volver a verificarse.'
      });
    }
    await refrescarSellers();
    return res.json({
      status: 'restored'
    });
  });
  return api;
}
function register(app) {
  app.use('/api/revision', router());
}
module.exports = {
  register,
  router
};
