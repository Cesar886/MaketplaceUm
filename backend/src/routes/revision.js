// API privada para la página de revisión. No es un sistema de usuarios: la
// página Next del mismo servidor guarda la llave en su entorno y la reenvía.
const crypto = require('crypto');
const express = require('express');
const { refrescarSellers } = require('../data');
const db = require('../database');

const MAX_MOTIVO = 500;

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
  if (!llaveValida(req)) return res.status(401).json({ error: 'No autorizado.' });
  next();
}

function leerMotivo(req, obligatorio) {
  const motivo = String(req.body?.reason || '').trim();
  if ((obligatorio && !motivo) || motivo.length > MAX_MOTIVO) return null;
  return motivo || null;
}

function obtenerSolicitud(database, id, estado) {
  return database.prepare(
    `SELECT v.usuario_id AS id, v.estado,
       v.responsable_negocio AS responsibleName,
       s.name, s.businessCategory, s.businessDescription, s.phone, s.verified
     FROM verificaciones v
     JOIN sellers s ON s.id = v.usuario_id
     WHERE v.usuario_id = ? AND v.tipo_cuenta = 'negocio'
       AND v.estado = ?`,
  ).get(id, estado);
}

function registrarDecision(database, solicitud, accion, motivo, decididoEn) {
  database.prepare(
    `INSERT INTO verification_review_log (
       usuario_id, accion, motivo, nombre_negocio, categoria_negocio,
       responsable_negocio, decidido_en
     ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    solicitud.id,
    accion,
    motivo,
    solicitud.name || solicitud.id,
    solicitud.businessCategory || null,
    solicitud.responsibleName || null,
    decididoEn,
  );
}

function router() {
  const api = express.Router();
  api.use(requireRevisionKey);

  api.get('/verificaciones', (req, res) => {
    if (req.query.status && req.query.status !== 'pending') {
      return res.status(400).json({ error: 'Solo se admite status=pending.' });
    }

    const rows = db.getDb().prepare(
      `SELECT v.usuario_id AS id, v.creado_en AS submittedAt,
         v.nombre_negocio AS requestedName,
         v.responsable_negocio AS responsibleName,
         v.ubicacion_lat AS requestedLat, v.ubicacion_lng AS requestedLng,
         v.link_red_social AS submittedSocialLink,
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
       ORDER BY v.creado_en ASC`,
    ).all();

    const ordenDocumento = {
      responsible_ine_front: 0,
      responsible_ine_back: 1,
      additional_evidence: 2,
    };
    const requests = rows.map(row => {
      const vistos = new Set();
      const documents = db.getDb().prepare(
        'SELECT id, doc_type AS type, file_url AS url, '
          + 'mime_type AS mimeType, content_hash AS contentHash '
          + 'FROM verification_documents WHERE usuario_id = ? '
          + 'ORDER BY uploaded_at DESC, id DESC',
      ).all(row.id).filter(document => {
        const clave = document.type === 'additional_evidence'
          ? document.type + ':' + (document.contentHash || document.id)
          : document.type;
        if (vistos.has(clave)) return false;
        vistos.add(clave);
        return true;
      }).map(document => ({
        id: document.id,
        type: document.type,
        url: document.url,
        mimeType: document.mimeType,
      })).sort((a, b) =>
        (ordenDocumento[a.type] ?? 99) - (ordenDocumento[b.type] ?? 99),
      );

      const tieneUbicacionSolicitud = Number.isFinite(row.requestedLat)
        && Number.isFinite(row.requestedLng);
      const tieneUbicacionPerfil = Number.isFinite(row.profileLat)
        && Number.isFinite(row.profileLng);

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
          paymentMethods: parsearJson(row.paymentMethods, []),
        },
        location: tieneUbicacionSolicitud
          ? { lat: row.requestedLat, lng: row.requestedLng, source: 'request' }
          : tieneUbicacionPerfil
            ? { lat: row.profileLat, lng: row.profileLng, source: 'profile' }
            : null,
        socialLinks: {
          submitted: row.submittedSocialLink || null,
          facebook: row.facebookUrl || null,
          instagram: row.instagramUrl || null,
          whatsapp: row.whatsappNumber || null,
          tiktok: row.tiktokUrl || null,
          twitter: row.twitterUrl || null,
        },
        documents,
      };
    });
    return res.json({ requests });
  });

  api.get('/historial', (_req, res) => {
    const rows = db.getDb().prepare(
      `SELECT h.id, h.usuario_id AS userId, h.accion AS action,
         h.motivo AS reason, h.nombre_negocio AS businessName,
         h.categoria_negocio AS businessCategory,
         h.responsable_negocio AS responsibleName,
         h.decidido_en AS decidedAt,
         COALESCE(s.verified, 0) AS currentVerified,
         CASE
           WHEN h.accion = 'approved'
             AND COALESCE(s.verified, 0) = 1
             AND h.id = (
               SELECT MAX(ultimo.id) FROM verification_review_log ultimo
               WHERE ultimo.usuario_id = h.usuario_id
             )
           THEN 1 ELSE 0
         END AS canRevoke
       FROM verification_review_log h
       LEFT JOIN sellers s ON s.id = h.usuario_id
       ORDER BY h.decidido_en DESC, h.id DESC`,
    ).all();

    return res.json({
      entries: rows.map(row => ({
        id: row.id,
        userId: row.userId,
        action: row.action,
        reason: row.reason || null,
        business: {
          name: row.businessName,
          category: row.businessCategory || null,
          responsibleName: row.responsibleName || null,
        },
        decidedAt: row.decidedAt,
        currentVerified: !!row.currentVerified,
        canRevoke: !!row.canRevoke,
      })),
    });
  });

  api.post('/verificaciones/:id/approve', (req, res) => {
    const motivo = leerMotivo(req, false);
    if (motivo === null && String(req.body?.reason || '').trim().length > MAX_MOTIVO) {
      return res.status(400).json({ error: `La nota no puede superar ${MAX_MOTIVO} caracteres.` });
    }

    const database = db.getDb();
    const decididoEn = new Date().toISOString();
    const updated = database.transaction(() => {
      const solicitud = obtenerSolicitud(database, req.params.id, 'pendiente');
      if (!solicitud || solicitud.verified) return false;
      database.prepare(
        `UPDATE verificaciones SET estado = 'verificado', fecha_verificacion = ?,
         motivo_rechazo = NULL, campo_rechazado = NULL WHERE usuario_id = ?`,
      ).run(decididoEn, solicitud.id);
      database.prepare('UPDATE sellers SET verified = 1 WHERE id = ?').run(solicitud.id);
      registrarDecision(database, solicitud, 'approved', motivo, decididoEn);
      return true;
    })();

    if (!updated) return res.status(404).json({ error: 'Solicitud pendiente no encontrada.' });
    refrescarSellers();
    return res.json({ status: 'approved' });
  });

  api.post('/verificaciones/:id/reject', (req, res) => {
    const motivo = leerMotivo(req, true);
    if (!motivo) {
      return res.status(400).json({
        error: `El motivo es obligatorio y no puede superar ${MAX_MOTIVO} caracteres.`,
      });
    }

    const database = db.getDb();
    const decididoEn = new Date().toISOString();
    const updated = database.transaction(() => {
      const solicitud = obtenerSolicitud(database, req.params.id, 'pendiente');
      if (!solicitud || solicitud.verified) return false;
      database.prepare(
        `UPDATE verificaciones SET estado = 'rechazado', fecha_verificacion = NULL,
         motivo_rechazo = ?, campo_rechazado = NULL WHERE usuario_id = ?`,
      ).run(motivo, solicitud.id);
      database.prepare('UPDATE sellers SET verified = 0 WHERE id = ?').run(solicitud.id);
      registrarDecision(database, solicitud, 'rejected', motivo, decididoEn);
      return true;
    })();

    if (!updated) return res.status(404).json({ error: 'Solicitud pendiente no encontrada.' });
    refrescarSellers();
    return res.json({ status: 'rejected' });
  });

  api.post('/verificaciones/:id/revoke', (req, res) => {
    const motivo = leerMotivo(req, true);
    if (!motivo) {
      return res.status(400).json({
        error: `El motivo es obligatorio y no puede superar ${MAX_MOTIVO} caracteres.`,
      });
    }

    const database = db.getDb();
    const decididoEn = new Date().toISOString();
    const revoked = database.transaction(() => {
      const solicitud = obtenerSolicitud(database, req.params.id, 'verificado');
      if (!solicitud || !solicitud.verified) return false;
      database.prepare(
        `UPDATE verificaciones SET estado = 'rechazado', fecha_verificacion = NULL,
         motivo_rechazo = ?, campo_rechazado = 'revision_manual'
         WHERE usuario_id = ?`,
      ).run(motivo, solicitud.id);
      database.prepare('UPDATE sellers SET verified = 0 WHERE id = ?').run(solicitud.id);
      registrarDecision(database, solicitud, 'revoked', motivo, decididoEn);
      return true;
    })();

    if (!revoked) {
      return res.status(409).json({ error: 'La cuenta ya no tiene una verificación activa.' });
    }
    refrescarSellers();
    return res.json({ status: 'revoked' });
  });

  return api;
}

function register(app) {
  app.use('/api/revision', router());
}

module.exports = { register };
