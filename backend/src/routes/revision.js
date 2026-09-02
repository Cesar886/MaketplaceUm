// API privada para la página de revisión. No es un sistema de usuarios: la
// página Next del mismo servidor guarda la llave en su entorno y la reenvía.
const crypto = require('crypto');
const express = require('express');
const { refrescarSellers } = require('../data');
const db = require('../database');

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

function router() {
  const api = express.Router();
  api.use(requireRevisionKey);

  api.get('/verificaciones', (req, res) => {
    if (req.query.status && req.query.status !== 'pending') {
      return res.status(400).json({ error: 'Solo se admite status=pending.' });
    }

    const rows = db.getDb().prepare(
      'SELECT v.usuario_id AS id, v.responsable_negocio AS responsibleName, '
        + 's.name, s.businessCategory, s.businessDescription, s.phone '
        + 'FROM verificaciones v JOIN sellers s ON s.id = v.usuario_id '
        + "WHERE v.tipo_cuenta = 'negocio' AND v.estado = 'pendiente' "
        + 'AND s.verified = 0 ORDER BY v.creado_en ASC',
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

      return {
        id: row.id,
        business: {
          name: row.name,
          category: row.businessCategory || null,
          responsibleName: row.responsibleName || null,
          description: row.businessDescription || null,
          phone: row.phone || null,
        },
        documents,
      };
    });
    return res.json({ requests });
  });

  api.post('/verificaciones/:id/approve', (req, res) => {
    const id = req.params.id;
    const updated = db.getDb().transaction(() => {
      const verification = db.getDb().prepare(
        `SELECT usuario_id FROM verificaciones
         WHERE usuario_id = ? AND tipo_cuenta = 'negocio' AND estado = 'pendiente'`,
      ).get(id);
      if (!verification) return false;
      db.getDb().prepare(
        `UPDATE verificaciones SET estado = 'verificado', fecha_verificacion = ?,
         motivo_rechazo = NULL, campo_rechazado = NULL WHERE usuario_id = ?`,
      ).run(new Date().toISOString(), id);
      db.getDb().prepare('UPDATE sellers SET verified = 1 WHERE id = ?').run(id);
      return true;
    })();
    if (!updated) return res.status(404).json({ error: 'Solicitud pendiente no encontrada.' });
    refrescarSellers();
    return res.json({ status: 'approved' });
  });

  api.post('/verificaciones/:id/reject', (req, res) => {
    const reason = String(req.body.reason || '').trim();
    if (!reason || reason.length > 500) {
      return res.status(400).json({ error: 'El motivo es obligatorio y no puede superar 500 caracteres.' });
    }
    const result = db.getDb().prepare(
      `UPDATE verificaciones SET estado = 'rechazado', motivo_rechazo = ?,
       campo_rechazado = NULL WHERE usuario_id = ? AND tipo_cuenta = 'negocio' AND estado = 'pendiente'`,
    ).run(reason, req.params.id);
    if (!result.changes) return res.status(404).json({ error: 'Solicitud pendiente no encontrada.' });
    return res.json({ status: 'rejected' });
  });

  return api;
}

function register(app) {
  app.use('/api/revision', router());
}

module.exports = { register };
