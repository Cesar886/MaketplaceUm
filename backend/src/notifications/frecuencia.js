/**
 * Reglas de frecuencia del retargeting: preferencias del usuario, frequency
 * capping y reducción adaptativa.
 *
 * Todo se deriva de `notification_log` y `user_notification_preferences`. No
 * hay tabla de contadores ni de backoff a propósito: un contador es estado
 * duplicado que se desincroniza del historial en cuanto una escritura falle
 * a medias, y aquí el historial ya está y responde a todas las preguntas.
 */

const db = require('../database');

// Tipo único de notificación que gobierna este módulo. Vive aquí porque es
// la clave con la que se escribe notification_log y con la que el usuario
// activa o desactiva la categoría entera desde ajustes.
const TIPO_RETARGETING = 'interest_new_product';

// Capping base.
const MIN_HORAS_MISMA_CATEGORIA = 24;
const MAX_POR_SEMANA = 3;

// Reducción adaptativa: cuántos envíos seguidos sin abrir hacen falta para
// castigar, cuánto se pausa la categoría y cuánto se estira el intervalo.
const IGNORADAS_PARA_CASTIGO = 3;
const DIAS_PAUSA_CATEGORIA = 14;
const MULTIPLICADOR_INTERVALO = 2;

// Un push recién enviado todavía no está "ignorado": el usuario puede no
// haber mirado el teléfono. Solo cuentan como decididas las notificaciones
// con al menos estas horas encima. Sin esta gracia, tres envíos seguidos en
// un mismo día se leerían como desinterés y se autopausarían solas.
const GRACIA_APERTURA_HORAS = 24;

/**
 * ¿El sujeto tiene habilitado este tipo de notificación?
 *
 * Semántica opt-out: la ausencia de fila significa habilitado, así que un
 * usuario nuevo recibe notificaciones sin que nadie tenga que sembrarle
 * preferencias al registrarse.
 */
async function estaHabilitado(subjectId, tipo = TIPO_RETARGETING) {
  const fila = await db.getDb().prepare(`
    SELECT enabled FROM user_notification_preferences
    WHERE subject_id = ? AND notification_type = ?
  `).get(subjectId, tipo);
  return fila ? fila.enabled === 1 : true;
}
async function setHabilitado(subjectId, tipo, habilitado) {
  await db.getDb().prepare(`
    INSERT INTO user_notification_preferences (subject_id, notification_type, enabled, updated_at)
    VALUES (?, ?, ?, datetime('now'))
    ON CONFLICT(subject_id, notification_type) DO UPDATE SET
      enabled = excluded.enabled,
      updated_at = excluded.updated_at
  `).run(subjectId, tipo, habilitado ? 1 : 0);
}
async function getPreferencias(subjectId) {
  const filas = await db.getDb().prepare(`
    SELECT notification_type, enabled FROM user_notification_preferences
    WHERE subject_id = ?
  `).all(subjectId);
  const preferencias = {
    [TIPO_RETARGETING]: true
  };
  for (const fila of filas) {
    preferencias[fila.notification_type] = fila.enabled === 1;
  }
  return preferencias;
}

/**
 * Cuenta cuántos de los últimos envíos *decididos* (fuera del periodo de
 * gracia) quedaron sin abrir, de forma consecutiva y empezando por el más
 * reciente. En cuanto aparece uno abierto, la racha se corta.
 *
 * @param {string|null} categoryId  null = mirar el tipo entero, sin filtrar
 */
async function ignoradasSeguidas(subjectId, categoryId = null) {
  const filas = await db.getDb().prepare(`
    SELECT opened_at FROM notification_log
    WHERE subject_id = ?
      AND type = ?
      AND (? IS NULL OR category_id = ?)
      AND sent_at <= datetime('now', '-' || ? || ' hours')
    ORDER BY sent_at DESC
    LIMIT ?
  `).all(subjectId, TIPO_RETARGETING, categoryId, categoryId, GRACIA_APERTURA_HORAS, IGNORADAS_PARA_CASTIGO);
  let racha = 0;
  for (const fila of filas) {
    if (fila.opened_at) break;
    racha++;
  }
  return racha;
}

/**
 * Decide si se le puede mandar AHORA un push de retargeting a un sujeto por
 * una categoría, aplicando en orden: preferencia del usuario, pausa
 * adaptativa, tope semanal e intervalo por categoría (estirado si el sujeto
 * viene ignorando este tipo de notificación en general).
 *
 * @returns {{permitido: boolean, motivo: string, intervaloHoras?: number}}
 */
async function puedeEnviar(subjectId, categoryId) {
  if (!(await estaHabilitado(subjectId))) {
    return {
      permitido: false,
      motivo: 'preferencia_desactivada'
    };
  }
  const raw = db.getDb();

  // ─── Pausa adaptativa por categoría ──────────────────────────────
  // Tres avisos seguidos de esta categoría sin abrir: el usuario no la
  // quiere. Se pausa contando desde el último envío, no desde ahora.
  if ((await ignoradasSeguidas(subjectId, categoryId)) >= IGNORADAS_PARA_CASTIGO) {
    const enPausa = await raw.prepare(`
      SELECT 1 FROM notification_log
      WHERE subject_id = ? AND type = ? AND category_id = ?
        AND sent_at >= datetime('now', '-' || ? || ' days')
      LIMIT 1
    `).get(subjectId, TIPO_RETARGETING, categoryId, DIAS_PAUSA_CATEGORIA);
    if (enPausa) {
      return {
        permitido: false,
        motivo: 'categoria_pausada'
      };
    }
  }

  // ─── Tope semanal, sumando todas las categorías ──────────────────
  const {
    total
  } = await raw.prepare(`
    SELECT COUNT(*) AS total FROM notification_log
    WHERE subject_id = ? AND type = ?
      AND sent_at >= datetime('now', '-7 days')
  `).get(subjectId, TIPO_RETARGETING);
  if (total >= MAX_POR_SEMANA) {
    return {
      permitido: false,
      motivo: 'tope_semanal'
    };
  }

  // ─── Intervalo mínimo por categoría ──────────────────────────────
  // Si el sujeto viene ignorando este tipo de notificación en general (no
  // solo en esta categoría), el intervalo se duplica antes de comprobarlo.
  const intervaloHoras = (await ignoradasSeguidas(subjectId, null)) >= IGNORADAS_PARA_CASTIGO ? MIN_HORAS_MISMA_CATEGORIA * MULTIPLICADOR_INTERVALO : MIN_HORAS_MISMA_CATEGORIA;
  const reciente = await raw.prepare(`
    SELECT 1 FROM notification_log
    WHERE subject_id = ? AND type = ? AND category_id = ?
      AND sent_at >= datetime('now', '-' || ? || ' hours')
    LIMIT 1
  `).get(subjectId, TIPO_RETARGETING, categoryId, intervaloHoras);
  if (reciente) {
    return {
      permitido: false,
      motivo: 'intervalo_categoria',
      intervaloHoras
    };
  }
  return {
    permitido: true,
    motivo: 'ok',
    intervaloHoras
  };
}

/**
 * Deja constancia de un envío. Devuelve el id de la fila para poder ligarla
 * después con la apertura.
 */
async function registrarEnvio({
  subjectId,
  categoryId,
  productIds,
  notificationId
}) {
  const info = await db.getDb().prepare(`
    INSERT INTO notification_log
      (subject_id, type, category_id, product_ids, notification_id, sent_at)
    VALUES (?, ?, ?, ?, ?, datetime('now'))
  `).run(subjectId, TIPO_RETARGETING, categoryId, JSON.stringify(productIds || []), notificationId || null);
  return info.lastInsertRowid;
}

/**
 * Marca como abierta la notificación de retargeting que la app acaba de
 * abrir. Se localiza por la notificación in-app asociada, que es el id que
 * la app sí conoce; si no viene, se cae al último envío de esa categoría.
 *
 * Solo marca filas sin `opened_at`: la métrica es "se abrió", no "cuántas
 * veces se abrió", y reescribir la fecha falsearía el open rate.
 */
async function registrarApertura({
  subjectId,
  notificationId,
  categoryId
}) {
  const raw = db.getDb();
  if (notificationId) {
    const info = await raw.prepare(`
      UPDATE notification_log SET opened_at = datetime('now')
      WHERE subject_id = ? AND notification_id = ? AND opened_at IS NULL
    `).run(subjectId, notificationId);
    if (info.changes > 0) return info.changes;
  }
  if (!categoryId) return 0;
  const info = await raw.prepare(`
    UPDATE notification_log SET opened_at = datetime('now')
    WHERE id = (
      SELECT id FROM notification_log
      WHERE subject_id = ? AND type = ? AND category_id = ? AND opened_at IS NULL
      ORDER BY sent_at DESC LIMIT 1
    )
  `).run(subjectId, TIPO_RETARGETING, categoryId);
  return info.changes;
}
module.exports = {
  TIPO_RETARGETING,
  MIN_HORAS_MISMA_CATEGORIA,
  MAX_POR_SEMANA,
  IGNORADAS_PARA_CASTIGO,
  DIAS_PAUSA_CATEGORIA,
  MULTIPLICADOR_INTERVALO,
  GRACIA_APERTURA_HORAS,
  estaHabilitado,
  setHabilitado,
  getPreferencias,
  ignoradasSeguidas,
  puedeEnviar,
  registrarEnvio,
  registrarApertura
};
