const ORDEN_DOCUMENTO = {
  responsible_ine_front: 0,
  responsible_ine_back: 1,
  additional_evidence: 2
};
function parsearJson(valor, respaldo) {
  if (!valor) return respaldo;
  try {
    return JSON.parse(valor);
  } catch {
    return respaldo;
  }
}
async function obtenerDocumentos(database, usuarioId) {
  const vistos = new Set();
  return (await database.prepare('SELECT id, doc_type AS type, file_url AS url, ' + 'mime_type AS mimeType, original_name AS originalName, ' + 'uploaded_at AS uploadedAt, content_hash AS contentHash ' + 'FROM verification_documents WHERE usuario_id = ? ' + 'ORDER BY uploaded_at DESC, id DESC').all(usuarioId)).filter(documento => {
    const clave = documento.type === 'additional_evidence' ? documento.type + ':' + (documento.contentHash || documento.id) : documento.type;
    if (vistos.has(clave)) return false;
    vistos.add(clave);
    return true;
  }).map(documento => ({
    id: documento.id,
    type: documento.type,
    url: documento.url,
    mimeType: documento.mimeType,
    originalName: documento.originalName,
    uploadedAt: documento.uploadedAt
  })).sort((a, b) => (ORDEN_DOCUMENTO[a.type] ?? 99) - (ORDEN_DOCUMENTO[b.type] ?? 99));
}
async function obtenerExpedienteVerificacion(database, usuarioId) {
  const row = await database.prepare(`SELECT v.usuario_id AS id, v.creado_en AS submittedAt,
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
     WHERE v.usuario_id = ? AND v.tipo_cuenta = 'negocio'`).get(usuarioId);
  if (!row) return null;
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
    documents: await obtenerDocumentos(database, row.id)
  };
}
module.exports = {
  obtenerExpedienteVerificacion
};
