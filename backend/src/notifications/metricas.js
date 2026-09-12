/**
 * Métricas de notificaciones: open rate por tipo y por categoría.
 *
 * Se calcula en vivo sobre notification_log en vez de mantener contadores.
 * El volumen es de una fila por push enviado y la consulta es un COUNT
 * agrupado sobre un índice, así que no compensa la complejidad de un
 * agregado que además habría que rellenar hacia atrás.
 */

const db = require('../database');

// Ventana por defecto de las métricas. 30 días es suficiente para ver una
// tendencia y corto para que un cambio de mensaje se note.
const VENTANA_METRICAS_DIAS = 30;

// Un push enviado hace diez minutos aún no es un "no abierto". Se excluyen
// de la métrica los envíos demasiado recientes para estar decididos; si no,
// publicar mucho justo antes de consultar hunde artificialmente el open rate.
const GRACIA_APERTURA_HORAS = 24;
function tasa(enviadas, abiertas) {
  return enviadas > 0 ? Math.round(abiertas / enviadas * 1000) / 10 : 0;
}

/**
 * @param {number} dias ventana hacia atrás
 * @returns {{ventanaDias, porTipo: [], porCategoria: []}} porcentajes de apertura
 */
async function getOpenRate({
  dias = VENTANA_METRICAS_DIAS
} = {}) {
  const raw = db.getDb();
  const filtro = `
    sent_at >= datetime('now', '-' || @dias || ' days')
    AND sent_at <= datetime('now', '-' || @gracia || ' hours')
  `;
  const params = {
    dias,
    gracia: GRACIA_APERTURA_HORAS
  };
  const porTipo = await raw.prepare(`
    SELECT
      type                                             AS tipo,
      COUNT(*)                                         AS enviadas,
      SUM(CASE WHEN opened_at IS NOT NULL THEN 1 ELSE 0 END) AS abiertas
    FROM notification_log
    WHERE ${filtro}
    GROUP BY type
    ORDER BY enviadas DESC
  `).all(params);
  const porCategoria = await raw.prepare(`
    SELECT
      nl.type                                             AS tipo,
      nl.category_id                                      AS categoryId,
      COALESCE(c.name, nl.category_id)                    AS categoria,
      COUNT(*)                                            AS enviadas,
      SUM(CASE WHEN nl.opened_at IS NOT NULL THEN 1 ELSE 0 END) AS abiertas
    FROM notification_log nl
    LEFT JOIN categories c ON c.id = nl.category_id
    WHERE ${filtro.replace(/sent_at/g, 'nl.sent_at')}
      AND nl.category_id IS NOT NULL
    GROUP BY nl.type, nl.category_id
    ORDER BY enviadas DESC
  `).all(params);
  return {
    ventanaDias: dias,
    graciaAperturaHoras: GRACIA_APERTURA_HORAS,
    porTipo: porTipo.map(f => ({
      ...f,
      openRate: tasa(f.enviadas, f.abiertas)
    })),
    porCategoria: porCategoria.map(f => ({
      ...f,
      openRate: tasa(f.enviadas, f.abiertas)
    }))
  };
}
module.exports = {
  VENTANA_METRICAS_DIAS,
  GRACIA_APERTURA_HORAS,
  getOpenRate
};
